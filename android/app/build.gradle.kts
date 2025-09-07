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
    }

    compileOptions {
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
    // You can omit these because FlutterFire plugins bring them in,
    // but leaving them with the BoM is fine.
    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
}
