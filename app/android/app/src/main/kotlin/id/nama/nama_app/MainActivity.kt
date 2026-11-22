package id.nama.nama_app

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.ContactsContract
import android.provider.MediaStore
import id.nama.nama_app.media.HiqeoVideoCompressor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import id.nama.nama_app.offgrid.HiqeoOffGridPlugin
import id.nama.nama_app.sos.HiqeoSmsHelper
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var offGridPlugin: HiqeoOffGridPlugin? = null
    private var pendingContactResult: MethodChannel.Result? = null
    private var pendingSmsPermissionResult: MethodChannel.Result? = null
    private var powerSaveReceiver: BroadcastReceiver? = null
    private var savedMusicVolume: Int? = null
    private var rearFlashCameraId: String? = null
    private val mediaExecutor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        private const val REQ_PICK_CONTACT = 4107
        private const val REQ_SEND_SMS = 4108
    }

    private fun readOsPowerSaveMode(): Boolean {
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        return powerManager?.isPowerSaveMode == true
    }

    private fun unregisterPowerSaveReceiver() {
        val receiver = powerSaveReceiver ?: return
        powerSaveReceiver = null
        try {
            unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // Receiver sudah tidak terdaftar.
        }
    }

    private fun resolveRearFlashCameraId(cm: CameraManager): String? {
        rearFlashCameraId?.let { return it }
        return try {
            for (id in cm.cameraIdList) {
                val chars = cm.getCameraCharacteristics(id)
                val hasFlash = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                if (hasFlash && facing == CameraCharacteristics.LENS_FACING_BACK) {
                    rearFlashCameraId = id
                    return id
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun setTorchEnabled(enabled: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return false
            val camId = resolveRearFlashCameraId(cm) ?: return false
            cm.setTorchMode(camId, enabled)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun setMaxMusicVolume(): Boolean {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
            if (savedMusicVolume == null) {
                savedMusicVolume = am.getStreamVolume(AudioManager.STREAM_MUSIC)
            }
            val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            am.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol, 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun restoreMusicVolume() {
        val prev = savedMusicVolume ?: return
        savedMusicVolume = null
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            am.setStreamVolume(AudioManager.STREAM_MUSIC, prev, 0)
        } catch (_: Exception) {
            // Abaikan bila sistem menolak perubahan volume.
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        offGridPlugin = HiqeoOffGridPlugin(applicationContext).also {
            it.registerWith(flutterEngine)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "id.nama.nama_app/dialer")
            .setMethodCallHandler { call, result ->
                if (call.method != "dial") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val number = call.argument<String>("number")
                if (number == null || !Regex("^[0-9]{2,4}$").matches(number)) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")))
                    result.success(true)
                } catch (error: ActivityNotFoundException) {
                    result.success(false)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "id.nama.nama_app/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> {
                        val name = call.argument<String>("name")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (name == null || bytes == null || name.isEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        result.success(saveImage(name, bytes))
                    }
                    "saveMedia" -> {
                        val name = call.argument<String>("name")
                        val mimeType = call.argument<String>("mimeType")
                        val bytes = call.argument<ByteArray>("bytes")
                        val filePath = call.argument<String>("filePath")
                        if (name.isNullOrEmpty() || mimeType.isNullOrEmpty() || (bytes == null && filePath.isNullOrEmpty())) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        mediaExecutor.execute {
                            val saved = saveMediaToGallery(name, mimeType, bytes, filePath)
                            mainHandler.post { result.success(saved) }
                        }
                    }
                    "extractVideoThumbnail" -> {
                        val source = call.argument<String>("source")
                        val maxWidth = call.argument<Int>("maxWidth") ?: 960
                        if (source.isNullOrEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        mediaExecutor.execute {
                            val thumb = extractVideoThumbnail(source, maxWidth)
                            mainHandler.post { result.success(thumb) }
                        }
                    }
                    "compressVideo" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val maxHeight = call.argument<Int>("maxHeight") ?: 720
                        val bitrateBps = call.argument<Int>("bitrateBps") ?: 3000000
                        val maxBytes = call.argument<Int>("maxBytes") ?: (25 * 1024 * 1024)
                        if (sourcePath.isNullOrEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        mediaExecutor.execute {
                            val compressedPath = HiqeoVideoCompressor.compressVideo(
                                cacheDir = cacheDir,
                                sourcePath = sourcePath,
                                maxHeight = maxHeight,
                                bitrateBps = bitrateBps,
                                maxBytes = maxBytes,
                            )
                            mainHandler.post { result.success(compressedPath) }
                        }
                    }
                    "getAppVersion" -> {
                        result.success(readAppVersionMarker())
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "id.nama.nama_app/contacts")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickContact") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingContactResult != null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                val intent = Intent(
                    Intent.ACTION_PICK,
                    ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                )
                try {
                    pendingContactResult = result
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, REQ_PICK_CONTACT)
                } catch (error: ActivityNotFoundException) {
                    pendingContactResult = null
                    result.success(null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "id.nama.nama_app/power")
            .setMethodCallHandler { call, result ->
                if (call.method != "isPowerSaveMode") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                result.success(readOsPowerSaveMode())
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "id.nama.nama_app/power_save_changes")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    unregisterPowerSaveReceiver()
                    events?.success(readOsPowerSaveMode())
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            if (intent?.action == PowerManager.ACTION_POWER_SAVE_MODE_CHANGED) {
                                events?.success(readOsPowerSaveMode())
                            }
                        }
                    }
                    powerSaveReceiver = receiver
                    val filter = IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        @Suppress("DEPRECATION")
                        registerReceiver(receiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    unregisterPowerSaveReceiver()
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "id.nama.nama_app/sos_hardware")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setTorch" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        result.success(setTorchEnabled(enabled))
                    }
                    "setMaxVolume" -> {
                        result.success(setMaxMusicVolume())
                    }
                    "restoreVolume" -> {
                        restoreMusicVolume()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "id.nama.nama_app/sos_sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasSmsPermission" -> {
                        result.success(HiqeoSmsHelper.hasSendSmsPermission(this))
                    }
                    "requestSmsPermission" -> {
                        if (HiqeoSmsHelper.hasSendSmsPermission(this)) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (pendingSmsPermissionResult != null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        pendingSmsPermissionResult = result
                        requestPermissions(arrayOf(Manifest.permission.SEND_SMS), REQ_SEND_SMS)
                    }
                    "sendSmsBatch" -> {
                        val phones = call.argument<List<String>>("phones") ?: emptyList()
                        val message = call.argument<String>("message") ?: ""
                        mediaExecutor.execute {
                            val summary = HiqeoSmsHelper.sendSmsBatch(
                                applicationContext,
                                phones,
                                message,
                            )
                            mainHandler.post { result.success(summary) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == REQ_SEND_SMS) {
            val callback = pendingSmsPermissionResult
            pendingSmsPermissionResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            callback?.success(granted)
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    @Deprecated("Dipakai untuk kompatibilitas FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_PICK_CONTACT) {
            val callback = pendingContactResult
            pendingContactResult = null
            if (callback == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                callback.success(null)
                return
            }
            val uri = data.data!!
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
            )
            try {
                contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIdx = cursor.getColumnIndex(
                            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                        )
                        val phoneIdx = cursor.getColumnIndex(
                            ContactsContract.CommonDataKinds.Phone.NUMBER,
                        )
                        val name = if (nameIdx >= 0) cursor.getString(nameIdx) ?: "" else ""
                        val phone = if (phoneIdx >= 0) cursor.getString(phoneIdx) ?: "" else ""
                        callback.success(mapOf("name" to name, "phone" to phone))
                        return
                    }
                }
            } catch (_: Exception) {
                // Kembalikan null jika kueri kontak gagal
            }
            callback.success(null)
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        setTorchEnabled(false)
        restoreMusicVolume()
        unregisterPowerSaveReceiver()
        offGridPlugin?.dispose()
        mediaExecutor.shutdownNow()
        super.onDestroy()
    }

    /// Menyimpan PNG ke Pictures/Hiqeo lewat MediaStore.
    private fun saveImage(name: String, bytes: ByteArray): String? =
        saveMediaToGallery(name, "image/png", bytes, null)

    /// Menyimpan gambar atau video komunitas ke Movies/Hiqeo atau Pictures/Hiqeo lewat MediaStore.
    private fun saveMediaToGallery(
        name: String,
        mimeType: String,
        bytes: ByteArray?,
        filePath: String?,
    ): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val resolver = contentResolver
        val isVideo = mimeType.startsWith("video/")
        val collection = if (isVideo) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val dir = if (isVideo) {
            "${Environment.DIRECTORY_MOVIES}/Hiqeo"
        } else {
            "${Environment.DIRECTORY_PICTURES}/Hiqeo"
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, dir)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = try {
            resolver.insert(collection, values)
        } catch (_: Exception) {
            null
        } ?: return null
        return try {
            val out = resolver.openOutputStream(uri)
                ?: run {
                    resolver.delete(uri, null, null)
                    return null
                }
            out.use { stream ->
                if (bytes != null) {
                    stream.write(bytes)
                } else if (!filePath.isNullOrEmpty()) {
                    File(filePath).inputStream().use { input -> input.copyTo(stream) }
                }
            }
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
            uri.toString()
        } catch (_: Exception) {
            resolver.delete(uri, null, null)
            null
        }
    }

    private fun readAppVersionMarker(): String {
        return try {
            val pm = packageManager
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(
                    packageName,
                    android.content.pm.PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(packageName, 0)
            }
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            "${info.versionName ?: "0"}+$code"
        } catch (_: Exception) {
            "0+0"
        }
    }

    /// Mengekstrak frame pertama video menjadi byte WebP terkompresi tanpa library eksternal.
    private fun extractVideoThumbnail(source: String, maxWidth: Int): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            if (source.startsWith("https://")) {
                retriever.setDataSource(
                    source,
                    hashMapOf("User-Agent" to "Hiqeo/1.0 (Android; Mobile)"),
                )
            } else if (source.startsWith("http://")) {
                return null
            } else {
                retriever.setDataSource(source)
            }
            val raw = retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.getFrameAtTime(-1L)
                ?: return null
            val scaled = if (maxWidth > 0 && raw.width > maxWidth) {
                val targetH = ((raw.height.toFloat() * maxWidth) / raw.width).toInt().coerceAtLeast(1)
                Bitmap.createScaledBitmap(raw, maxWidth, targetH, true).also {
                    if (it !== raw && !raw.isRecycled) raw.recycle()
                }
            } else {
                raw
            }
            val format = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Bitmap.CompressFormat.WEBP_LOSSY
            } else {
                @Suppress("DEPRECATION")
                Bitmap.CompressFormat.WEBP
            }
            val out = ByteArrayOutputStream()
            scaled.compress(format, 85, out)
            if (!scaled.isRecycled) scaled.recycle()
            out.toByteArray()
        } catch (_: Throwable) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
                // Abaikan galat penutupan retriever.
            }
        }
    }
}
