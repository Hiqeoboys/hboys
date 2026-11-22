package id.nama.nama_app.offgrid

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.WpsInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/**
 * Mesin Wi-Fi Direct P2P + TCP Socket lokal (port 8988) untuk transfer file
 * pesan suara `.m4a` offline saat anggota grup berdekatan tanpa internet.
 *
 * - Memasang [BroadcastReceiver] untuk `WIFI_P2P_PEERS_CHANGED_ACTION` dan
 *   `WIFI_P2P_CONNECTION_CHANGED_ACTION` (RECEIVER_EXPORTED untuk broadcast sistem).
 * - Secara otomatis memanggil `requestPeers()` -> `connect(WifiP2pConfig)` ke
 *   peer yang tersedia agar grup P2P terbentuk dan `groupOwnerAddress` terisi.
 * - Saat klien terhubung ke Group Owner, mengirim handshake ringan agar Group
 *   Owner mencatat IP klien dan dapat mengirim balik pesan suara `.m4a`.
 * - Berjalan terpisah dari [BleDualRoleEngine] sehingga pengiriman pesan teks
 *   offline tetap penuh via BLE Mesh meski Wi-Fi Direct belum terbentuk.
 */
class WifiDirectAudioEngine(
    private val context: Context,
    private val onAudioReceived: (localPath: String, meta: Map<String, Any?>, fromPeer: String?) -> Unit,
    private val onConnectionChanged: ((groupFormed: Boolean) -> Unit)? = null,
) {
    companion object {
        private const val TCP_PORT = 8988
        private const val CONNECT_TIMEOUT_MS = 5000
        private const val PEER_CONNECT_COOLDOWN_MS = 10000L
        private const val GLOBAL_CONNECT_COOLDOWN_MS = 5000L
        private const val DISCOVERY_REFRESH_INTERVAL_MS = 20000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val manager: WifiP2pManager? =
        context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
    private var channel: WifiP2pManager.Channel? = null
    private var receiverRegistered = false

    private val executor = Executors.newCachedThreadPool()
    private var serverSocket: ServerSocket? = null
    @Volatile
    private var running = false

    private val discoveredPeers = CopyOnWriteArrayList<WifiP2pDevice>()
    private val lastConnectAttemptMs = ConcurrentHashMap<String, Long>()
    @Volatile
    private var lastGlobalConnectMs: Long = 0L
    @Volatile
    private var connectInProgress: Boolean = false
    @Volatile
    private var groupFormed: Boolean = false
    @Volatile
    private var groupOwnerIp: String? = null
    @Volatile
    private var isGroupOwner: Boolean = false
    private val knownClientIps = CopyOnWriteArrayList<String>()

    private val discoveryRefreshRunnable = object : Runnable {
        @SuppressLint("MissingPermission")
        override fun run() {
            if (!running) return
            if (!groupFormed && hasWifiP2pPermission()) {
                val mgr = manager
                val ch = channel
                if (mgr != null && ch != null) {
                    try {
                        mgr.discoverPeers(ch, null)
                    } catch (_: Exception) {}
                }
            }
            mainHandler.postDelayed(this, DISCOVERY_REFRESH_INTERVAL_MS)
        }
    }

    private val p2pReceiver = object : BroadcastReceiver() {
        @SuppressLint("MissingPermission")
        override fun onReceive(ctx: Context, intent: Intent) {
            if (!running) return
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    if (!hasWifiP2pPermission()) return
                    val ch = channel ?: return
                    manager?.requestPeers(ch) { peers ->
                        discoveredPeers.clear()
                        discoveredPeers.addAll(peers.deviceList)
                        autoConnectIfNeeded()
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    val ch = channel ?: return
                    manager?.requestConnectionInfo(ch) { info: WifiP2pInfo? ->
                        if (info != null && info.groupFormed) {
                            groupFormed = true
                            connectInProgress = false
                            isGroupOwner = info.isGroupOwner
                            val ownerHost = info.groupOwnerAddress?.hostAddress
                            groupOwnerIp = ownerHost
                            if (!info.isGroupOwner && !ownerHost.isNullOrBlank()) {
                                sendClientRegistrationHandshake(ownerHost)
                            }
                            onConnectionChanged?.invoke(true)
                        } else {
                            val wasFormed = groupFormed
                            groupFormed = false
                            isGroupOwner = false
                            groupOwnerIp = null
                            knownClientIps.clear()
                            if (wasFormed) {
                                onConnectionChanged?.invoke(false)
                            }
                            if (running && hasWifiP2pPermission()) {
                                try {
                                    manager?.discoverPeers(ch, null)
                                } catch (_: Exception) {}
                            }
                        }
                    }
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun start() {
        if (running) return
        running = true
        val p2pMgr = manager
        if (p2pMgr != null) {
            channel = p2pMgr.initialize(context, Looper.getMainLooper(), null)
            registerReceiver()
            if (hasWifiP2pPermission()) {
                try {
                    p2pMgr.discoverPeers(channel, null)
                } catch (_: Exception) {}
            }
            mainHandler.postDelayed(discoveryRefreshRunnable, DISCOVERY_REFRESH_INTERVAL_MS)
        }
        startTcpServer()
    }

    @SuppressLint("MissingPermission")
    private fun autoConnectIfNeeded() {
        if (!running || groupFormed || connectInProgress || !hasWifiP2pPermission()) return
        val mgr = manager ?: return
        val ch = channel ?: return

        val now = System.currentTimeMillis()
        if (now - lastGlobalConnectMs < GLOBAL_CONNECT_COOLDOWN_MS) return

        // Pilih peer AVAILABLE yang belum dicoba dalam rentang cooldown.
        val candidates = discoveredPeers.filter { peer ->
            peer.status == WifiP2pDevice.AVAILABLE &&
                !peer.deviceAddress.isNullOrBlank() &&
                (now - (lastConnectAttemptMs[peer.deviceAddress] ?: 0L)) >= PEER_CONNECT_COOLDOWN_MS
        }
        if (candidates.isEmpty()) return

        // Prioritaskan peer yang namanya mengandung "hiqeo" bila ada.
        val target = candidates.firstOrNull {
            it.deviceName?.contains("hiqeo", ignoreCase = true) == true
        } ?: candidates.first()

        val config = WifiP2pConfig().apply {
            deviceAddress = target.deviceAddress
            wps.setup = WpsInfo.PBC
        }
        connectInProgress = true
        lastGlobalConnectMs = now
        lastConnectAttemptMs[target.deviceAddress] = now

        try {
            mgr.connect(
                ch,
                config,
                object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        // Menunggu WIFI_P2P_CONNECTION_CHANGED_ACTION untuk mengisi groupOwnerAddress.
                        mainHandler.postDelayed({ connectInProgress = false }, PEER_CONNECT_COOLDOWN_MS)
                    }

                    override fun onFailure(reason: Int) {
                        connectInProgress = false
                    }
                },
            )
        } catch (_: Exception) {
            connectInProgress = false
        }
    }

    /**
     * Mengirim frame registrasi ringan (`metaLen = 0`) ke Group Owner agar IP
     * klien langsung tercatat di `knownClientIps` sehingga Group Owner dapat
     * mengirim file `.m4a` ke klien secara dua arah.
     */
    private fun sendClientRegistrationHandshake(ownerHost: String) {
        executor.execute {
            try {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress(ownerHost, TCP_PORT), CONNECT_TIMEOUT_MS)
                    DataOutputStream(BufferedOutputStream(socket.getOutputStream())).use { out ->
                        out.writeInt(0)
                        out.writeLong(0L)
                        out.flush()
                    }
                }
            } catch (_: Exception) {
                // Coba ulang sekali bila TCP server Group Owner masih baru terbuka.
                try {
                    Thread.sleep(800)
                    if (!running || !groupFormed) return@execute
                    Socket().use { socket ->
                        socket.connect(InetSocketAddress(ownerHost, TCP_PORT), CONNECT_TIMEOUT_MS)
                        DataOutputStream(BufferedOutputStream(socket.getOutputStream())).use { out ->
                            out.writeInt(0)
                            out.writeLong(0L)
                            out.flush()
                        }
                    }
                } catch (_: Exception) {}
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun sendAudioFile(peerId: String, filePath: String, meta: Map<String, Any?>): Boolean {
        val file = File(filePath)
        if (!file.exists()) return false

        // Trigger negosiasi Wi-Fi Direct bila grup P2P belum terbentuk.
        val mgr = manager
        val ch = channel
        if (!groupFormed || groupOwnerIp == null) {
            if (mgr != null && ch != null && hasWifiP2pPermission()) {
                val targetPeer = discoveredPeers.firstOrNull {
                    it.status == WifiP2pDevice.AVAILABLE &&
                        (peerId == "broadcast" || it.deviceAddress == peerId)
                }
                if (targetPeer != null) {
                    val config = WifiP2pConfig().apply {
                        deviceAddress = targetPeer.deviceAddress
                        wps.setup = WpsInfo.PBC
                    }
                    try {
                        mgr.connect(ch, config, null)
                    } catch (_: Exception) {}
                } else {
                    try {
                        mgr.discoverPeers(ch, null)
                    } catch (_: Exception) {}
                }
            }
            return false
        }

        val targetHosts = buildList {
            if (!isGroupOwner && groupOwnerIp != null) add(groupOwnerIp!!)
            if (isGroupOwner) addAll(knownClientIps)
        }.distinct()
        if (targetHosts.isEmpty()) return false

        executor.execute {
            for (host in targetHosts) {
                try {
                    Socket().use { socket ->
                        socket.connect(InetSocketAddress(host, TCP_PORT), CONNECT_TIMEOUT_MS)
                        DataOutputStream(BufferedOutputStream(socket.getOutputStream())).use { out ->
                            val metaBytes = JSONObject(meta).toString().toByteArray(Charsets.UTF_8)
                            out.writeInt(metaBytes.size)
                            out.write(metaBytes)
                            out.writeLong(file.length())
                            file.inputStream().use { input ->
                                input.copyTo(out)
                            }
                            out.flush()
                        }
                    }
                } catch (_: Exception) {
                    // Biarkan pengirim mencoba ulang saat peer kembali terjangkau.
                }
            }
        }
        return true
    }

    fun stop() {
        running = false
        mainHandler.removeCallbacks(discoveryRefreshRunnable)
        try {
            serverSocket?.close()
        } catch (_: Exception) {}
        serverSocket = null
        if (receiverRegistered) {
            try {
                context.unregisterReceiver(p2pReceiver)
            } catch (_: Exception) {}
            receiverRegistered = false
        }
        discoveredPeers.clear()
        lastConnectAttemptMs.clear()
        knownClientIps.clear()
        connectInProgress = false
        groupFormed = false
        isGroupOwner = false
        groupOwnerIp = null
    }

    private fun startTcpServer() {
        executor.execute {
            try {
                val server = ServerSocket(TCP_PORT)
                serverSocket = server
                while (running) {
                    val client = try {
                        server.accept()
                    } catch (_: Exception) {
                        break
                    }
                    val remoteIp = client.inetAddress?.hostAddress
                    if (remoteIp != null && !knownClientIps.contains(remoteIp)) {
                        knownClientIps.add(remoteIp)
                    }
                    executor.execute { handleIncomingClient(client, remoteIp) }
                }
            } catch (_: Exception) {}
        }
    }

    private fun handleIncomingClient(client: Socket, remoteIp: String?) {
        client.use { socket ->
            try {
                socket.soTimeout = 15000
                val input = DataInputStream(BufferedInputStream(socket.getInputStream()))
                val metaLen = input.readInt()
                if (metaLen == 0) {
                    // Handshake registrasi IP klien ke Group Owner (sudah dicatat di knownClientIps).
                    return
                }
                if (metaLen < 0 || metaLen > 65536) return
                val metaBytes = ByteArray(metaLen)
                input.readFully(metaBytes)
                val metaJson = JSONObject(String(metaBytes, Charsets.UTF_8))
                val fileLength = input.readLong()
                if (fileLength < 0 || fileLength > 25 * 1024 * 1024) return

                val msgId = metaJson.optString("client_msg_id")
                    .replace(Regex("[^a-zA-Z0-9_-]"), "")
                    .ifBlank { System.currentTimeMillis().toString() }
                val voiceDir = File(context.filesDir, "offgrid_voice").apply { mkdirs() }
                val outFile = File(voiceDir, "$msgId.m4a")
                if (!outFile.canonicalPath.startsWith(voiceDir.canonicalPath + File.separator)) {
                    return
                }
                outFile.outputStream().use { out ->
                    val buffer = ByteArray(8192)
                    var remaining = fileLength
                    while (remaining > 0) {
                        val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                        if (read < 0) break
                        out.write(buffer, 0, read)
                        remaining -= read
                    }
                }

                val metaMap = mutableMapOf<String, Any?>()
                for (key in metaJson.keys()) {
                    metaMap[key] = metaJson.opt(key)
                }
                onAudioReceived(outFile.absolutePath, metaMap, remoteIp)
            } catch (_: Exception) {}
        }
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        // Broadcast Wi-Fi Direct dikirim oleh sistem Android sehingga memakai RECEIVER_EXPORTED.
        ContextCompat.registerReceiver(
            context,
            p2pReceiver,
            filter,
            ContextCompat.RECEIVER_EXPORTED,
        )
        receiverRegistered = true
    }

    private fun hasWifiP2pPermission(): Boolean {
        val nearbyWifi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.NEARBY_WIFI_DEVICES,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val location = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        return nearbyWifi || location
    }
}
