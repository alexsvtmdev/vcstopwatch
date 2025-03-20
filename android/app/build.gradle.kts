import java.io.File
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.libervibe.vcstopwatch"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.libervibe.vcstopwatch"
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = 3
        versionName = "1.0.0"
    }

    signingConfigs {
        create("release") {
            val keystorePropertiesFile = File(rootProject.projectDir, "key.properties")

            println("📂 Checking key.properties at: ${keystorePropertiesFile.absolutePath}")
            println("✅ File exists? ${keystorePropertiesFile.exists()}")

            if (keystorePropertiesFile.exists()) {
                val keystoreProperties = Properties().apply {
                    load(FileInputStream(keystorePropertiesFile))
                }

                storeFile = File(rootProject.projectDir, "release-key.jks")
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            } else {
                println("⚠️ WARNING: key.properties not found! Release builds will not be signed!")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
