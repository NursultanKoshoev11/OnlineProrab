plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Keep local/CI debug builds on one explicit certificate instead of the
// machine-specific Android Studio debug keystore. The keystore itself stays
// outside the repository. CI can provide it through STROY_KEYSTORE_PATH and
// the STROY_* signing environment variables.
val stroyKeystorePath = System.getenv("STROY_KEYSTORE_PATH")
    ?: "${System.getProperty("user.home")}/.android/stroy-debug.keystore"
val stroyKeystore = file(stroyKeystorePath)
val stroyStorePassword = System.getenv("STROY_KEYSTORE_PASSWORD") ?: "android"
val stroyKeyAlias = System.getenv("STROY_KEY_ALIAS") ?: "androiddebugkey"
val stroyKeyPassword = System.getenv("STROY_KEY_PASSWORD") ?: "android"

android {
    namespace = "com.onlineprorab.online_prorab"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.onlineprorab.online_prorab"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
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
            signingConfig = if (stroyKeystore.exists()) {
                signingConfigs.getByName("stroyStable")
            } else {
                signingConfigs.getByName("debug")
            }
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
