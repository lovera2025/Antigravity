allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// universal_ble 3.1.0 (el Bluetooth de la barra) escribe su bloque `kotlin {}` sin aplicar
// el plugin de Kotlin: cuenta con el que trae adentro el Android Gradle Plugin 9. Con el 8
// que usa esta app, sin esto no compila ("Could not find method kotlin()"). Se le aplica
// apenas aplica el de Android, antes de que llegue a ese bloque. Sacarlo al pasar al 9.
subprojects {
    if (name == "universal_ble") {
        pluginManager.withPlugin("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
