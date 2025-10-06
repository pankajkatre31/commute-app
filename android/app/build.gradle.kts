plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.commute_app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.commute_app"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Add this line, it's good practice for large apps
        multiDexEnabled = true
    }

    compileOptions {
        // This enables the desugaring feature in Kotlin script.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions { jvmTarget = "17" }
    kotlin { jvmToolchain(17) }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ================== THIS IS THE FIX ==================
    // Updated the version from 2.0.4 to 2.1.4 as required by the build error.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // =======================================================

    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
}

