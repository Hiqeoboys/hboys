package id.nama.nama_app.offgrid

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import id.nama.nama_app.R

/**
 * Android Foreground Service bertipe `connectedDevice` untuk menjaga BLE Mesh
 * dan Wi-Fi Direct tetap aktif saat perangkat benar-benar offline di Ruang Obrolan.
 *
 * - TIDAK dijalankan saat aplikasi online atau idle.
 * - Notifikasi bersifat dapat dihilangkan (`setOngoing(false)`) dan memiliki
 *   tombol aksi "Hentikan / Tutup" untuk mematikan layanan dengan aman.
 */
class HiqeoMeshForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "hiqeo_mesh_channel"
        private const val NOTIFICATION_ID = 4851
        private const val STOP_REQUEST_CODE = 4852
        const val ACTION_START = "id.nama.nama_app.offgrid.START"
        const val ACTION_STOP = "id.nama.nama_app.offgrid.STOP"
        const val ACTION_UPDATE_PEERS = "id.nama.nama_app.offgrid.UPDATE_PEERS"
        const val EXTRA_PEER_COUNT = "peer_count"

        @Volatile
        var isServiceRunning: Boolean = false
            private set

        @Volatile
        var onStopRequested: (() -> Unit)? = null

        fun startService(context: Context) {
            val appCtx = context.applicationContext
            isServiceRunning = true
            val intent = Intent(appCtx, HiqeoMeshForegroundService::class.java).apply {
                action = ACTION_START
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appCtx.startForegroundService(intent)
                } else {
                    appCtx.startService(intent)
                }
            } catch (_: Exception) {
                isServiceRunning = false
            }
        }

        /**
         * Memperbarui teks jumlah perangkat pada notifikasi HANYA bila service
         * memang sedang berjalan — tidak pernah memaksa menyalakan ulang
         * Foreground Service saat aplikasi online/idle atau sesudah dihentikan.
         */
        fun updatePeerCount(context: Context, peers: Int) {
            if (!isServiceRunning) return
            val appCtx = context.applicationContext
            try {
                val manager = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    ?: return
                ensureChannel(manager)
                manager.notify(NOTIFICATION_ID, createNotification(appCtx, peers))
            } catch (_: Exception) {
                // Abaikan bila izin notifikasi belum diberikan.
            }
        }

        fun stopService(context: Context) {
            val appCtx = context.applicationContext
            isServiceRunning = false
            try {
                val manager = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                manager?.cancel(NOTIFICATION_ID)
            } catch (_: Exception) {}
            try {
                appCtx.stopService(Intent(appCtx, HiqeoMeshForegroundService::class.java))
            } catch (_: Exception) {}
        }

        private fun ensureChannel(manager: NotificationManager) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                    val channel = NotificationChannel(
                        CHANNEL_ID,
                        "Hiqeo Mesh Off-Grid",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        description = "Menjaga sinkronisasi BLE Mesh & Wi-Fi Direct saat di luar jaringan."
                        setShowBadge(false)
                    }
                    manager.createNotificationChannel(channel)
                }
            }
        }

        private fun createStopPendingIntent(context: Context): PendingIntent {
            val stopIntent = Intent(context, HiqeoMeshForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            return PendingIntent.getService(context, STOP_REQUEST_CODE, stopIntent, flags)
        }

        private fun createNotification(context: Context, peerCount: Int): Notification {
            val detail = if (peerCount > 0) {
                "$peerCount perangkat sekitar terhubung"
            } else {
                "Memindai perangkat Hiqeo sekitar melalui BLE Mesh"
            }
            val stopPendingIntent = createStopPendingIntent(context)
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_hiqeo)
                .setContentTitle("Hiqeo Mesh Aktif")
                .setContentText(detail)
                .setOngoing(false)
                .setAutoCancel(false)
                .setSilent(true)
                .setOnlyAlertOnce(true)
                .setDeleteIntent(stopPendingIntent)
                .addAction(
                    0,
                    "Hentikan / Tutup",
                    stopPendingIntent,
                )
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                isServiceRunning = false
                try {
                    onStopRequested?.invoke()
                } catch (_: Exception) {}
                detachForegroundAndStop()
                return START_NOT_STICKY
            }
            ACTION_UPDATE_PEERS -> {
                if (!isServiceRunning) {
                    detachForegroundAndStop()
                    return START_NOT_STICKY
                }
                val peers = intent.getIntExtra(EXTRA_PEER_COUNT, 0)
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                if (manager != null) {
                    ensureChannel(manager)
                    manager.notify(NOTIFICATION_ID, createNotification(this, peers))
                }
                return START_NOT_STICKY
            }
            else -> {
                isServiceRunning = true
                promoteToForeground(0)
                return START_NOT_STICKY
            }
        }
    }

    override fun onDestroy() {
        isServiceRunning = false
        super.onDestroy()
    }

    private fun detachForegroundAndStop() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {}
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {}
        stopSelf()
    }

    private fun promoteToForeground(peerCount: Int) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        if (manager != null) {
            ensureChannel(manager)
        }
        val notification = createNotification(this, peerCount)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: SecurityException) {
            // Jangan crash jika izin Nearby/Bluetooth Android 14+ belum diberikan user.
            isServiceRunning = false
        }
    }
}
