import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La clave de firma de las tablets. `android/key.properties` no va a git: la clave y su
// contraseña viven en Documentos\Junior Eventos\claves (ver su LEEME.txt). Android solo
// actualiza la app si la versión nueva viene firmada con la misma clave.
val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
val hayClaveDeFirma = keyPropertiesFile.exists()
if (hayClaveDeFirma) {
    FileInputStream(keyPropertiesFile).use { keyProperties.load(it) }
}

android {
    namespace = "com.example.arguello_events"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // El id de la app en Android. Se cambió el 3-nov-2026, antes de instalarla en ninguna
        // tablet: cambiarlo después la haría otra app, sin las ventas guardadas en la vieja.
        applicationId = "ar.com.junioreventos.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayClaveDeFirma) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Con la clave, firma con ella. Sin la clave (otra PC), la de prueba, para que
            // `flutter run --release` ande igual; el instalador frena antes de armar un APK
            // así (`installer/build_installer.ps1`): ninguna tablet recibe uno con la de prueba.
            signingConfig = if (hayClaveDeFirma) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
