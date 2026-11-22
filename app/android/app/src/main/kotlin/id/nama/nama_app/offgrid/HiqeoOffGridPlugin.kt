package id.nama.nama_app.offgrid

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Plugin MethodChannel & EventChannel Android untuk menjembatani Dart [MeshRouterService]
 * dengan BLE Mesh Dual-Role, Wi-Fi Direct P2P audio, dan Foreground Service `connectedDevice`.
 */
class HiqeoOffGridPlugin(private val context: Context) {

    companion object {
        private const val METHOD_CHANNEL = "id.nama.nama_app/offgrid_method"
        private const val PACKETS_EVENT_CHANNEL = "id.nama.nama_app/offgrid_packets"
        private const val AUDIO_EVENT_CHANNEL = "id.nama.nama_app/offgrid_audio"
        private const val PEERS_EVENT_CHANNEL = "id.nama.nama_app/offgrid_peers"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var packetSink: EventChannel.EventSink? = null
    private var audioSink: EventChannel.EventSink? = null
    private var peerSink: EventChannel.EventSink? = null

    private val bleEngine = BleDualRoleEngine(
        context = context,
        onPacketReceived = { bytes ->
            mainHandler.post { packetSink?.success(bytes) }
        },
        onPeersChanged = { count ->
            mainHandler.post {
                peerSink?.success(count)
                // Hanya perbarui notifikasi bila Foreground Service sedang aktif.
                if (HiqeoMeshForegroundService.isServiceRunning) {
                    HiqeoMeshForegroundService.updatePeerCount(context, count)
                }
            }
        },
    )

    private val wifiAudioEngine = WifiDirectAudioEngine(
        context = context,
        onAudioReceived = { localPath, meta, fromPeer ->
            mainHandler.post {
                audioSink?.success(
                    mapOf(
                        "localPath" to localPath,
                        "meta" to meta,
                        "fromPeerId" to fromPeer,
                    ),
                )
            }
        },
        onConnectionChanged = { formed ->
            if (formed) {
                mainHandler.post {
                    // Picu flush antrean audio tertunda di Dart ketika grup Wi-Fi Direct terbentuk.
                    val peers = maxOf(1, bleEngine.currentPeerCount())
                    peerSink?.success(peers)
                }
            }
        },
    )

    private fun stopEnginesInternal() {
        HiqeoMeshForegroundService.stopService(context)
        bleEngine.stop()
        wifiAudioEngine.stop()
        peerSink?.success(0)
    }

    fun registerWith(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Ketika user menekan "Hentikan / Tutup" atau menggeser notifikasi Mesh,
        // matikan mesin BLE Mesh & Wi-Fi Direct secara bersih.
        HiqeoMeshForegroundService.onStopRequested = {
            mainHandler.post {
                bleEngine.stop()
                wifiAudioEngine.stop()
                peerSink?.success(0)
            }
        }

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val highDuty = call.argument<Boolean>("highDuty") ?: false
                    val useForegroundService = call.argument<Boolean>("useForegroundService") ?: false
                    if (useForegroundService) {
                        try {
                            HiqeoMeshForegroundService.startService(context)
                        } catch (_: Throwable) {}
                    }
                    // BLE Mesh untuk pesan teks selalu dimulai terpisah dan tidak
                    // bergantung pada status koneksi Wi-Fi Direct.
                    bleEngine.start(highDuty)
                    wifiAudioEngine.start()
                    result.success(null)
                }
                "stop" -> {
                    stopEnginesInternal()
                    result.success(null)
                }
                "setDutyMode" -> {
                    val highDuty = call.argument<Boolean>("highDuty") ?: false
                    bleEngine.setDutyMode(highDuty)
                    result.success(null)
                }
                "sendPacket" -> {
                    val payload = call.argument<ByteArray>("payload")
                    if (payload != null) {
                        bleEngine.sendPacket(payload)
                    }
                    result.success(null)
                }
                "sendAudioFile" -> {
                    val peerId = call.argument<String>("peerId") ?: "broadcast"
                    val filePath = call.argument<String>("filePath")
                    val meta = call.argument<Map<String, Any?>>("meta") ?: emptyMap()
                    if (filePath.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        result.success(wifiAudioEngine.sendAudioFile(peerId, filePath, meta))
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, PACKETS_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var localSink: EventChannel.EventSink? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    localSink = events
                    packetSink = events
                }

                override fun onCancel(arguments: Any?) {
                    if (packetSink === localSink) {
                        packetSink = null
                    }
                    localSink = null
                }
            },
        )

        EventChannel(messenger, AUDIO_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var localSink: EventChannel.EventSink? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    localSink = events
                    audioSink = events
                }

                override fun onCancel(arguments: Any?) {
                    if (audioSink === localSink) {
                        audioSink = null
                    }
                    localSink = null
                }
            },
        )

        EventChannel(messenger, PEERS_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var localSink: EventChannel.EventSink? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    localSink = events
                    peerSink = events
                    events?.success(bleEngine.currentPeerCount())
                }

                override fun onCancel(arguments: Any?) {
                    if (peerSink === localSink) {
                        peerSink = null
                    }
                    localSink = null
                }
            },
        )
    }

    fun dispose() {
        HiqeoMeshForegroundService.onStopRequested = null
        stopEnginesInternal()
    }
}
