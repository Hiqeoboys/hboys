package id.nama.nama_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }
}
