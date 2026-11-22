package id.nama.nama_app.sos

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager

object HiqeoSmsHelper {
    private val phoneRegex = Regex("^\\+?[0-9]{6,16}$")

    fun hasSendSmsPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return context.checkSelfPermission(
            Manifest.permission.SEND_SMS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun resolveSmsManager(context: Context): SmsManager? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
        } catch (_: Throwable) {
            null
        }
    }

    fun sendSmsBatch(
        context: Context,
        phones: List<String>,
        message: String,
    ): Map<String, Any> {
        val cleaned = phones.map { it.trim() }.filter { phoneRegex.matches(it) }
        if (!hasSendSmsPermission(context)) {
            return mapOf(
                "sentCount" to 0,
                "failedCount" to cleaned.size,
                "permissionDenied" to true,
                "sentPhones" to emptyList<String>(),
                "failedPhones" to cleaned,
            )
        }
        val smsManager = resolveSmsManager(context)
            ?: return mapOf(
                "sentCount" to 0,
                "failedCount" to cleaned.size,
                "permissionDenied" to false,
                "sentPhones" to emptyList<String>(),
                "failedPhones" to cleaned,
            )

        val sent = mutableListOf<String>()
        val failed = mutableListOf<String>()

        for (phone in cleaned) {
            try {
                val parts = smsManager.divideMessage(message)
                if (parts != null && parts.size > 1) {
                    smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                } else {
                    smsManager.sendTextMessage(phone, null, message, null, null)
                }
                sent.add(phone)
            } catch (_: Throwable) {
                failed.add(phone)
            }
        }

        return mapOf(
            "sentCount" to sent.size,
            "failedCount" to failed.size,
            "permissionDenied" to false,
            "sentPhones" to sent,
            "failedPhones" to failed,
        )
    }
}
