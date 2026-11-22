# Flutter engine & wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Hiqeo native classes & channels
-keep class id.nama.nama_app.** { *; }

# Firebase & Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Mapbox Maps SDK
-keep class com.mapbox.** { *; }
-dontwarn com.mapbox.**

# Local notifications & foreground task
-keep class com.dexterous.** { *; }
-keep class com.pravera.** { *; }
-dontwarn com.dexterous.**
-dontwarn com.pravera.**

# Flutter Secure Storage & Tink crypto
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# Gson / serialization & SQLite native FFI
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keep class com.google.gson.** { *; }
-keep class org.sqlite.** { *; }
-dontwarn org.sqlite.**

# Video Player (Media3 / ExoPlayer) & Media Compression for R2 media playback
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class com.fluttercandies.flutter_image_compress.** { *; }
-keep class com.example.flutterimagecompress.** { *; }
-dontwarn com.fluttercandies.flutter_image_compress.**

# OkHttp / Okio / TLS / Kotlin Coroutines for Supabase & Cloudflare R2 HTTPS
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okio.** { *; }
-dontwarn okio.**
-keep class org.conscrypt.** { *; }
-dontwarn org.conscrypt.**
-keep class javax.net.ssl.** { *; }
-keep class kotlin.Metadata { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
