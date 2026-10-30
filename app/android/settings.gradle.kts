pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

// mapbox_maps_flutter_mobile 3.33.0 only applies 'kotlin-android' for AGP < 9,
// assuming AGP 9 built-in Kotlin. Flutter sets android.builtInKotlin=false and
// skips its own KGP fallback because the plugin script mentions kotlin-android,
// so the project ends up with no Kotlin plugin and fails on its `kotlin {}` block.
gradle.beforeProject {
    if (name == "mapbox_maps_flutter_mobile") {
        pluginManager.apply("org.jetbrains.kotlin.android")
    }
}

include(":app")
