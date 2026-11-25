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
        manifestPlaceholders["etiquetaDeLaApp"] = "Junior Eventos"
        // Una ventana de prueba armada como APK (`JUNIOR_APK_DE_PRUEBA=1`, la tele es el
        // tótem, 24-nov-2026) es otra app: se instala al lado de la de verdad, nunca encima.
        if (System.getenv("JUNIOR_APK_DE_PRUEBA") == "1") {
            applicationIdSuffix = ".prueba"
            manifestPlaceholders["etiquetaDeLaApp"] = "Junior Eventos · prueba"
        }
    }

    // La página del celular de la puerta adentro del APK (la tele es la central,
    // 24-nov-2026): `build/puesto`, la que arma el instalador, en los archivos propios de
    // Android y no en los de Flutter (así Windows no la lleva dos veces). La tele la copia
    // a su carpeta al abrir el modo tele (`PaginaDelCelularEnAndroid`).
    sourceSets {
        getByName("main") {
            assets.srcDir(layout.buildDirectory.dir("generated/puesto"))
            // Solo en la app de prueba: los salones de verdad, sin nombres (ver
            // `salonesDePrueba`, abajo).
            assets.srcDir(layout.buildDirectory.dir("generated/salones_prueba"))
        }
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

// Copia `build/puesto` (sin los `.symbols`, que solo sirven para depurar) a
// `generated/puesto/puesto`: en el APK queda como `assets/puesto/...`. Sin la carpeta,
// el APK sale sin la página y la tele lo dice en su menú.
// Una página a medio armar (sin las letras ni los íconos) no se copia: el APK no sale. Así
// salió la 6.6.0 en la PC (íconos como cuadraditos y, sin internet, nada), y el 24-nov un
// `flutter build web` hecho encima de otro dejó la carpeta sin `assets/FontManifest.json`.
val copiarPaginaDelCelular = tasks.register<Copy>("copiarPaginaDelCelular") {
    val pagina = rootProject.file("../build/puesto")
    doFirst {
        if (!pagina.exists()) {
            logger.warn("Sin build/puesto: el APK sale sin la página del celular de la puerta.")
        } else {
            val faltan = listOf("index.html", "main.dart.js", "assets/FontManifest.json")
                .filter { !File(pagina, it).exists() }
            if (faltan.isNotEmpty()) {
                throw GradleException(
                    "La página del celular (build/puesto) está a medio armar: falta $faltan. " +
                        "Borrá build/puesto y .dart_tool/flutter_build y armala de nuevo.",
                )
            }
        }
    }
    from(pagina) {
        exclude("**/*.symbols")
    }
    into(layout.buildDirectory.dir("generated/puesto/puesto"))
}
tasks.named("preBuild") { dependsOn(copiarPaginaDelCelular) }

// La app de prueba de la tele (`JUNIOR_APK_DE_PRUEBA=1`, 25-nov-2026) trae los salones de
// los eventos masivos de verdad, sin nombres (`tool/salones_de_verdad.py` los deja en
// `build/salones_prueba`), para medir el tótem con salones de verdad. **La app de verdad no
// los lleva nunca**: sin la variable, la carpeta se vacía antes de armar.
val salonesDePrueba = tasks.register("salonesDePrueba") {
    outputs.upToDateWhen { false }
    doLast {
        val destino = layout.buildDirectory.dir("generated/salones_prueba/salones_prueba").get().asFile
        destino.deleteRecursively()
        val origen = rootProject.file("../build/salones_prueba/salones.json")
        if (System.getenv("JUNIOR_APK_DE_PRUEBA") == "1") {
            if (origen.exists()) {
                destino.mkdirs()
                origen.copyTo(File(destino, "salones.json"), overwrite = true)
            } else {
                logger.warn("Sin build/salones_prueba: la app de prueba va con el salón inventado.")
            }
        }
    }
}
tasks.named("preBuild") { dependsOn(salonesDePrueba) }
