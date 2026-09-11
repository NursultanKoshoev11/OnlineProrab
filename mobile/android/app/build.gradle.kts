plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The production keystore stays outside the repository. CI and local release
// builds must provide it through STROY_KEYSTORE_PATH and STROY_* variables.
val stroyKeystorePath = System.getenv("STROY_KEYSTORE_PATH")
    ?: "${System.getProperty("user.home")}/.android/stroy-debug.keystore"
val stroyKeystore = file(stroyKeystorePath)
val stroyStorePassword = System.getenv("STROY_KEYSTORE_PASSWORD") ?: "android"
val stroyKeyAlias = System.getenv("STROY_KEY_ALIAS") ?: "androiddebugkey"
val stroyKeyPassword = System.getenv("STROY_KEY_PASSWORD") ?: "android"
val stroyApplicationId = System.getenv("STROY_APPLICATION_ID")
    ?: "com.onlineprorab.online_prorab"

android {
    namespace = "com.onlineprorab.online_prorab"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = stroyApplicationId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (stroyKeystore.exists()) {
            create("stroyStable") {
                storeFile = stroyKeystore
                storePassword = stroyStorePassword
                keyAlias = stroyKeyAlias
                keyPassword = stroyKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = if (stroyKeystore.exists()) {
                signingConfigs.getByName("stroyStable")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        release {
            if (System.getenv("STROY_APPLICATION_ID").isNullOrBlank()) {
                throw GradleException(
                    "Release package id requires STROY_APPLICATION_ID to match the Play Console app",
                )
            }
            if (!stroyKeystore.exists()) {
                throw GradleException(
                    "Release signing requires STROY_KEYSTORE_PATH to point to a production keystore",
                )
            }
            signingConfig = signingConfigs.getByName("stroyStable")
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
