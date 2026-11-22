package id.nama.nama_app.offgrid

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.content.ContextCompat
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Mesin BLE Mesh Dual-Role simultan (Peripheral + Central):
 * - AdvertiseData HANYA menyertakan 128-bit Service UUID (<= 21 byte, aman di
 *   bawah batas 31 byte BLE legacy & 100% kompatibel iOS CoreBluetooth).
 * - Menggunakan antrean penulisan GATT berurutan (sequential write queue per
 *   perangkat + sequential server notification queue) sehingga potongan chunk
 *   AES-GCM (<= 180 byte) tidak saling menimpa atau hilang diam-diam.
 * - Mengirimkan jumlah perangkat BLE Hiqeo sekitar secara realtime ke Dart UI
 *   (`Offline · X perangkat sekitar`).
 */
class BleDualRoleEngine(
    private val context: Context,
    private val onPacketReceived: (ByteArray) -> Unit,
    private val onPeersChanged: (Int) -> Unit,
) {
    companion object {
        // 128-bit UUID standar Bluetooth Base ("HQ" = 0x4851)
        val SERVICE_UUID: UUID = UUID.fromString("00004851-0000-1000-8000-00805f9b34fb")
        val CHAR_UUID: UUID = UUID.fromString("00004852-0000-1000-8000-00805f9b34fb")
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        private const val IDLE_SCAN_WINDOW_MS = 2000L
        private const val IDLE_PAUSE_WINDOW_MS = 8000L
        private const val REQUESTED_MTU = 247
        private const val WRITE_WATCHDOG_MS = 1500L
        private const val NEARBY_PEER_TTL_MS = 20000L
        private const val PEER_PRUNE_INTERVAL_MS = 5000L
        private const val MAX_QUEUED_CHUNKS_PER_PEER = 128
    }

    private val handler = Handler(Looper.getMainLooper())
    private val bluetoothManager: BluetoothManager? =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val adapter: BluetoothAdapter? get() = bluetoothManager?.adapter

    private var advertiser: BluetoothLeAdvertiser? = null
    private var scanner: BluetoothLeScanner? = null
    private var gattServer: BluetoothGattServer? = null
    private var notifyCharacteristic: BluetoothGattCharacteristic? = null

    private val centralClients = ConcurrentHashMap<String, BluetoothGatt>()
    private val subscribedCentrals = ConcurrentHashMap<String, BluetoothDevice>()
    private val discoveredNearbyPeers = ConcurrentHashMap<String, Long>()

    // Antrean penulisan GATT berurutan (Central -> Peripheral) & notifikasi berurutan (Peripheral -> Central)
    private val queueLock = Any()
    private val readyClients = HashSet<String>()
    private val clientWriteQueues = HashMap<String, ArrayDeque<ByteArray>>()
    private val clientWriteInFlight = HashSet<String>()
    private val clientWatchdogs = HashMap<String, Runnable>()

    private val serverNotifyQueue = ArrayDeque<Pair<BluetoothDevice, ByteArray>>()
    private var serverNotifyInFlight = false
    private var serverNotifyWatchdog: Runnable? = null

    private var isStarted = false
    private var isHighDuty = false
    private var isScanning = false
    private var lastReportedPeerCount = -1

    private val peerPruneRunnable = object : Runnable {
        override fun run() {
            if (!isStarted) return
            pruneStaleDiscoveredPeers()
            handler.postDelayed(this, PEER_PRUNE_INTERVAL_MS)
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {}

    fun currentPeerCount(): Int {
        val now = System.currentTimeMillis()
        val unique = HashSet<String>()
        unique.addAll(centralClients.keys)
        unique.addAll(subscribedCentrals.keys)
        for ((addr, seenAt) in discoveredNearbyPeers.entries) {
            if (now - seenAt <= NEARBY_PEER_TTL_MS) {
                unique.add(addr)
            }
        }
        return unique.size
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                subscribedCentrals.remove(device.address)
                synchronized(queueLock) {
                    val iterator = serverNotifyQueue.iterator()
                    while (iterator.hasNext()) {
                        if (iterator.next().first.address == device.address) {
                            iterator.remove()
                        }
                    }
                }
                notifyPeers()
            } else if (newState == BluetoothProfile.STATE_CONNECTED) {
                discoveredNearbyPeers[device.address] = System.currentTimeMillis()
                notifyPeers()
            }
        }

        @SuppressLint("MissingPermission")
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            if (characteristic.uuid == CHAR_UUID) {
                discoveredNearbyPeers[device.address] = System.currentTimeMillis()
                onPacketReceived(value.copyOf())
            }
            if (responseNeeded && hasBleConnectPermission()) {
                try {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
                } catch (_: Exception) {}
            }
        }

        @SuppressLint("MissingPermission")
        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            if (descriptor.uuid == CCCD_UUID) {
                if (value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)) {
                    subscribedCentrals[device.address] = device
                    discoveredNearbyPeers[device.address] = System.currentTimeMillis()
                } else {
                    subscribedCentrals.remove(device.address)
                }
                notifyPeers()
            }
            if (responseNeeded && hasBleConnectPermission()) {
                try {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
                } catch (_: Exception) {}
            }
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            synchronized(queueLock) {
                serverNotifyWatchdog?.let { handler.removeCallbacks(it) }
                serverNotifyWatchdog = null
                serverNotifyInFlight = false
            }
            drainServerNotifyQueue()
        }
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device ?: return
            val address = device.address ?: return
            if (!isStarted || !hasBleConnectPermission()) return

            val wasNew = !discoveredNearbyPeers.containsKey(address)
            discoveredNearbyPeers[address] = System.currentTimeMillis()
            if (wasNew) {
                notifyPeers()
            }

            if (centralClients.containsKey(address)) return

            val gatt = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    device.connectGatt(context, false, createGattClientCallback(), BluetoothDevice.TRANSPORT_LE)
                } else {
                    device.connectGatt(context, false, createGattClientCallback())
                }
            } catch (_: Exception) {
                null
            }
            if (gatt != null) {
                centralClients[address] = gatt
                notifyPeers()
            }
        }
    }

    private fun createGattClientCallback(): BluetoothGattCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            val address = gatt.device?.address ?: return
            if (!hasBleConnectPermission()) return
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    discoveredNearbyPeers[address] = System.currentTimeMillis()
                    val mtuRequested = try {
                        gatt.requestMtu(REQUESTED_MTU)
                    } catch (_: Exception) {
                        false
                    }
                    if (!mtuRequested) {
                        try {
                            gatt.discoverServices()
                        } catch (_: Exception) {}
                    }
                    notifyPeers()
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    cleanupClientConnection(address, gatt)
                    notifyPeers()
                }
            }
        }

        @SuppressLint("MissingPermission")
        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (hasBleConnectPermission()) {
                try {
                    gatt.discoverServices()
                } catch (_: Exception) {}
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val address = gatt.device?.address ?: return
            if (status != BluetoothGatt.GATT_SUCCESS || !hasBleConnectPermission()) return
            val char = gatt.getService(SERVICE_UUID)?.getCharacteristic(CHAR_UUID) ?: return
            gatt.setCharacteristicNotification(char, true)
            val cccd = char.getDescriptor(CCCD_UUID)
            if (cccd == null) {
                markClientReadyAndDrain(address)
                return
            }
            val descriptorStarted = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.writeDescriptor(
                        cccd,
                        BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
                    ) == BluetoothStatusCodes.SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    gatt.writeDescriptor(cccd)
                }
            } catch (_: Exception) {
                false
            }
            if (!descriptorStarted) {
                markClientReadyAndDrain(address)
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            val address = gatt.device?.address ?: return
            markClientReadyAndDrain(address)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            val address = gatt.device?.address ?: return
            synchronized(queueLock) {
                clientWatchdogs.remove(address)?.let { handler.removeCallbacks(it) }
                clientWriteInFlight.remove(address)
            }
            drainClientWriteQueue(address)
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            if (characteristic.uuid == CHAR_UUID) {
                gatt.device?.address?.let {
                    discoveredNearbyPeers[it] = System.currentTimeMillis()
                }
                onPacketReceived(value.copyOf())
            }
        }

        @Deprecated("Deprecated in API 33")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU && characteristic.uuid == CHAR_UUID) {
                @Suppress("DEPRECATION")
                val bytes = characteristic.value ?: return
                gatt.device?.address?.let {
                    discoveredNearbyPeers[it] = System.currentTimeMillis()
                }
                onPacketReceived(bytes.copyOf())
            }
        }
    }

    fun start(highDuty: Boolean) {
        if (isStarted) {
            setDutyMode(highDuty)
            return
        }
        val btAdapter = adapter ?: return
        if (!btAdapter.isEnabled) return

        isStarted = true
        isHighDuty = highDuty
        lastReportedPeerCount = -1
        startGattServerAndAdvertising(btAdapter)
        scanner = btAdapter.bluetoothLeScanner
        scheduleScanLoop()
        handler.postDelayed(peerPruneRunnable, PEER_PRUNE_INTERVAL_MS)
        notifyPeers()
    }

    fun setDutyMode(highDuty: Boolean) {
        isHighDuty = highDuty
        if (!isStarted) return
        handler.removeCallbacksAndMessages(null)
        scheduleScanLoop()
        handler.postDelayed(peerPruneRunnable, PEER_PRUNE_INTERVAL_MS)
    }

    @SuppressLint("MissingPermission")
    fun sendPacket(payload: ByteArray) {
        if (!isStarted || !hasBleConnectPermission()) return
        val copy = payload.copyOf()

        // 1. Masukkan ke antrean penulisan GATT berurutan untuk tiap Peripheral terhubung
        for (address in centralClients.keys) {
            enqueueClientWrite(address, copy)
        }

        // 2. Masukkan ke antrean notifikasi GATT Server berurutan untuk tiap Central berlangganan
        for (device in subscribedCentrals.values) {
            enqueueServerNotification(device, copy)
        }
    }

    private fun markClientReadyAndDrain(address: String) {
        synchronized(queueLock) {
            readyClients.add(address)
        }
        drainClientWriteQueue(address)
        // Paksa laporan peer agar Dart MeshRouterService segera mengirim ulang
        // pesan store-and-forward tanpa perlu menutup/membuka ulang aplikasi.
        notifyPeers(force = true)
    }

    private fun enqueueClientWrite(address: String, payload: ByteArray) {
        synchronized(queueLock) {
            val queue = clientWriteQueues.getOrPut(address) { ArrayDeque() }
            if (queue.size >= MAX_QUEUED_CHUNKS_PER_PEER) {
                queue.pollFirst()
            }
            queue.addLast(payload)
        }
        drainClientWriteQueue(address)
    }

    @SuppressLint("MissingPermission")
    private fun drainClientWriteQueue(address: String) {
        if (!isStarted || !hasBleConnectPermission()) return

        val nextPayload: ByteArray
        val gatt = centralClients[address] ?: return

        synchronized(queueLock) {
            if (!readyClients.contains(address)) return
            if (clientWriteInFlight.contains(address)) return
            val queue = clientWriteQueues[address] ?: return
            nextPayload = queue.pollFirst() ?: return
            clientWriteInFlight.add(address)
        }

        val char = gatt.getService(SERVICE_UUID)?.getCharacteristic(CHAR_UUID)
        if (char == null) {
            synchronized(queueLock) {
                clientWriteInFlight.remove(address)
            }
            return
        }

        val writeType =
            if ((char.properties and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0) {
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            } else {
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            }

        val initiated = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeCharacteristic(char, nextPayload, writeType) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                char.writeType = writeType
                @Suppress("DEPRECATION")
                char.value = nextPayload
                @Suppress("DEPRECATION")
                gatt.writeCharacteristic(char)
            }
        } catch (_: Exception) {
            false
        }

        if (!initiated) {
            synchronized(queueLock) {
                clientWriteInFlight.remove(address)
            }
            handler.postDelayed({ drainClientWriteQueue(address) }, 60L)
            return
        }

        val watchdog = Runnable {
            synchronized(queueLock) {
                clientWatchdogs.remove(address)
                clientWriteInFlight.remove(address)
            }
            drainClientWriteQueue(address)
        }
        synchronized(queueLock) {
            clientWatchdogs.put(address, watchdog)?.let { handler.removeCallbacks(it) }
        }
        handler.postDelayed(watchdog, WRITE_WATCHDOG_MS)
    }

    private fun enqueueServerNotification(device: BluetoothDevice, payload: ByteArray) {
        synchronized(queueLock) {
            if (serverNotifyQueue.size >= MAX_QUEUED_CHUNKS_PER_PEER) {
                serverNotifyQueue.pollFirst()
            }
            serverNotifyQueue.addLast(device to payload)
        }
        drainServerNotifyQueue()
    }

    @SuppressLint("MissingPermission")
    private fun drainServerNotifyQueue() {
        if (!isStarted || !hasBleConnectPermission()) return
        val server = gattServer ?: return
        val serverChar = notifyCharacteristic ?: return

        val item: Pair<BluetoothDevice, ByteArray>
        synchronized(queueLock) {
            if (serverNotifyInFlight) return
            item = serverNotifyQueue.pollFirst() ?: return
            serverNotifyInFlight = true
        }

        val (device, payload) = item
        val initiated = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                server.notifyCharacteristicChanged(
                    device,
                    serverChar,
                    false,
                    payload,
                ) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                serverChar.value = payload
                @Suppress("DEPRECATION")
                server.notifyCharacteristicChanged(device, serverChar, false)
            }
        } catch (_: Exception) {
            false
        }

        if (!initiated) {
            synchronized(queueLock) {
                serverNotifyInFlight = false
            }
            handler.postDelayed({ drainServerNotifyQueue() }, 60L)
            return
        }

        val watchdog = Runnable {
            synchronized(queueLock) {
                serverNotifyWatchdog = null
                serverNotifyInFlight = false
            }
            drainServerNotifyQueue()
        }
        synchronized(queueLock) {
            serverNotifyWatchdog?.let { handler.removeCallbacks(it) }
            serverNotifyWatchdog = watchdog
        }
        handler.postDelayed(watchdog, WRITE_WATCHDOG_MS)
    }

    @SuppressLint("MissingPermission")
    private fun cleanupClientConnection(address: String, gatt: BluetoothGatt) {
        centralClients.remove(address)
        synchronized(queueLock) {
            readyClients.remove(address)
            clientWriteQueues.remove(address)
            clientWriteInFlight.remove(address)
            clientWatchdogs.remove(address)?.let { handler.removeCallbacks(it) }
        }
        try {
            gatt.close()
        } catch (_: Exception) {}
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        isStarted = false
        handler.removeCallbacksAndMessages(null)
        stopScan()

        if (hasBleAdvertisePermission()) {
            try {
                advertiser?.stopAdvertising(advertiseCallback)
            } catch (_: Exception) {}
        }
        if (hasBleConnectPermission()) {
            for (gatt in centralClients.values) {
                try {
                    gatt.disconnect()
                    gatt.close()
                } catch (_: Exception) {}
            }
            try {
                gattServer?.close()
            } catch (_: Exception) {}
        }
        centralClients.clear()
        subscribedCentrals.clear()
        discoveredNearbyPeers.clear()
        synchronized(queueLock) {
            readyClients.clear()
            clientWriteQueues.clear()
            clientWriteInFlight.clear()
            clientWatchdogs.clear()
            serverNotifyQueue.clear()
            serverNotifyInFlight = false
            serverNotifyWatchdog = null
        }
        gattServer = null
        notifyCharacteristic = null
        notifyPeers(force = true)
    }

    @SuppressLint("MissingPermission")
    private fun startGattServerAndAdvertising(btAdapter: BluetoothAdapter) {
        val manager = bluetoothManager ?: return
        if (hasBleConnectPermission()) {
            val server = manager.openGattServer(context, gattServerCallback)
            if (server != null) {
                val char = BluetoothGattCharacteristic(
                    CHAR_UUID,
                    BluetoothGattCharacteristic.PROPERTY_WRITE or
                        BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                        BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                    BluetoothGattCharacteristic.PERMISSION_WRITE or
                        BluetoothGattCharacteristic.PERMISSION_READ,
                ).apply {
                    addDescriptor(
                        BluetoothGattDescriptor(
                            CCCD_UUID,
                            BluetoothGattDescriptor.PERMISSION_READ or
                                BluetoothGattDescriptor.PERMISSION_WRITE,
                        ),
                    )
                }
                val service = BluetoothGattService(
                    SERVICE_UUID,
                    BluetoothGattService.SERVICE_TYPE_PRIMARY,
                ).apply { addCharacteristic(char) }
                server.addService(service)
                notifyCharacteristic = char
                gattServer = server
            }
        }

        if (hasBleAdvertisePermission()) {
            advertiser = btAdapter.bluetoothLeAdvertiser
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(
                    if (isHighDuty) AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY
                    else AdvertiseSettings.ADVERTISE_MODE_BALANCED,
                )
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(true)
                .build()

            // PENTING: Hanya sertakan Service UUID (21 byte <= batas 31 byte BLE legacy).
            // Jangan sertakan nama perangkat atau TX power level agar tidak gagal
            // dengan ADVERTISE_FAILED_DATA_TOO_LARGE dan tetap kompatibel iOS.
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addServiceUuid(ParcelUuid(SERVICE_UUID))
                .build()
            try {
                advertiser?.startAdvertising(settings, data, advertiseCallback)
            } catch (_: Exception) {}
        }
    }

    private fun scheduleScanLoop() {
        if (!isStarted) return
        if (isHighDuty) {
            startScan(lowLatency = true)
            return
        }
        // Adaptive duty-cycling saat idle: scan 2 detik, lalu jeda 8 detik
        startScan(lowLatency = false)
        handler.postDelayed({
            if (!isStarted || isHighDuty) return@postDelayed
            stopScan()
            handler.postDelayed({
                if (!isStarted || isHighDuty) return@postDelayed
                scheduleScanLoop()
            }, IDLE_PAUSE_WINDOW_MS)
        }, IDLE_SCAN_WINDOW_MS)
    }

    @SuppressLint("MissingPermission")
    private fun startScan(lowLatency: Boolean) {
        if (isScanning || !hasBleScanPermission()) return
        val leScanner = scanner ?: return
        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(
                if (lowLatency) ScanSettings.SCAN_MODE_LOW_LATENCY
                else ScanSettings.SCAN_MODE_LOW_POWER,
            )
            .build()
        try {
            leScanner.startScan(listOf(filter), settings, scanCallback)
            isScanning = true
        } catch (_: Exception) {}
    }

    @SuppressLint("MissingPermission")
    private fun stopScan() {
        if (!isScanning || !hasBleScanPermission()) return
        try {
            scanner?.stopScan(scanCallback)
        } catch (_: Exception) {}
        isScanning = false
    }

    private fun pruneStaleDiscoveredPeers() {
        val now = System.currentTimeMillis()
        var removedAny = false
        val iterator = discoveredNearbyPeers.entries.iterator()
        while (iterator.hasNext()) {
            val (addr, seenAt) = iterator.next()
            if (now - seenAt > NEARBY_PEER_TTL_MS &&
                !centralClients.containsKey(addr) &&
                !subscribedCentrals.containsKey(addr)
            ) {
                iterator.remove()
                removedAny = true
            }
        }
        if (removedAny) {
            notifyPeers()
        }
    }

    private fun notifyPeers(force: Boolean = false) {
        val count = currentPeerCount()
        if (!force && count == lastReportedPeerCount) return
        lastReportedPeerCount = count
        onPeersChanged(count)
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun hasBleScanPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hasPermission(android.Manifest.permission.BLUETOOTH_SCAN)
        } else {
            hasPermission(android.Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun hasBleConnectPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hasPermission(android.Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            true
        }

    private fun hasBleAdvertisePermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hasPermission(android.Manifest.permission.BLUETOOTH_ADVERTISE)
        } else {
            true
        }
}
