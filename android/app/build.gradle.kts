plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Keep local builds working before Firebase configuration is supplied. Once
// google-services.json is added, the official plugin generates Firebase's
// Android resources automatically.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val uploadStore = System.getenv("ARENA_USER_KEYSTORE")
val uploadStorePassword = System.getenv("ARENA_USER_STORE_PASSWORD")
val uploadAlias = System.getenv("ARENA_USER_KEY_ALIAS")
val uploadKeyPassword = System.getenv("ARENA_USER_KEY_PASSWORD")
val uploadSigningReady = !uploadStore.isNullOrBlank() && !uploadStorePassword.isNullOrBlank() &&
    !uploadAlias.isNullOrBlank() && !uploadKeyPassword.isNullOrBlank()

gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release") } && !uploadSigningReady) {
        throw GradleException("Release signing missing. Configure private ARENA_USER signing environment variables; Debug signing is never used for Release.")
    }
}

android {
    namespace = "com.example.playon"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.playon"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // firebase_messaging 16 uses native APIs available from Android 6.0.
        minSdk = 23
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (uploadSigningReady) {
            create("release") {
                storeFile = file(uploadStore!!)
                storePassword = uploadStorePassword
                keyAlias = uploadAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Release upload credentials are supplied privately by the account holder.
            signingConfig = if (uploadSigningReady) signingConfigs.getByName("release") else null
        }
    }
}

flutter {
    source = "../.."
}
