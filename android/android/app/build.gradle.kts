plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "it.athlynk.athlynk"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Per-flavor resValue (app_name) needs this — disabled by default in AGP 9.
    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires java.time desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "it.athlynk.athlynk"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two apps from one codebase, mirroring the iOS project's two targets
    // (Athlynk athlete + AthlynkCoach). Each flavor gets its own application
    // id, launcher label and deep-link scheme (Stripe redirect callbacks).
    flavorDimensions += "app"
    productFlavors {
        create("athlete") {
            dimension = "app"
            applicationId = "it.athlynk.athlynk"
            resValue("string", "app_name", "Athlynk")
            manifestPlaceholders["deepLinkScheme"] = "athlynk"
        }
        create("coach") {
            dimension = "app"
            applicationId = "it.athlynk.athlynk.coach"
            resValue("string", "app_name", "Athlynk Coach")
            manifestPlaceholders["deepLinkScheme"] = "athlynkcoach"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
