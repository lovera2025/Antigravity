package com.example.arguello_events

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    /// La Tele 1 oye a la Tele 2 que la busca por el wifi (`RedDeLaTele`).
    private var multicast: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // La pantalla de la tablet de la barra no se apaga mientras VENDER está
        // abierta (`PantallaDespierta`, en lib/features/barra/services/), ni la
        // tele mientras muestra el tótem.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "junior_eventos/pantalla")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "despierta" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // La tele es el tótem (24-nov-2026): `lib/features/tele/red_de_la_tele.dart`.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "junior_eventos/red")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "multicast" -> {
                        try {
                            ponerMulticast(call.arguments == true)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("multicast", e.message, null)
                        }
                    }
                    "copiarPuesto" -> {
                        val destino = call.arguments as? String
                        if (destino == null) {
                            result.success(false)
                        } else {
                            // Fuera del hilo de la pantalla: son unos cuantos MB.
                            Thread {
                                val ok = try {
                                    copiarPuesto(File(destino))
                                } catch (e: Exception) {
                                    false
                                }
                                runOnUiThread { result.success(ok) }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // Lo que se sabe del aparato, para "Cómo anda" de la app de prueba de la
        // tele (25-nov-2026, `lib/features/tele/aparato_de_la_tele.dart`).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "junior_eventos/aparato")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "datos" -> Thread {
                        val datos = HashMap<String, Any?>()
                        datos["bits"] = if (android.os.Process.is64Bit()) 64 else 32
                        datos["modelo"] = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
                        datos["dibuja"] = conQueDibuja()
                        runOnUiThread { result.success(datos) }
                    }.start()
                    // Solo la app de prueba los trae (Gradle los copia con
                    // JUNIOR_APK_DE_PRUEBA=1): los salones de verdad, sin nombres.
                    "salonesDePrueba" -> Thread {
                        val texto = try {
                            assets.open("salones_prueba/salones.json").bufferedReader().use { it.readText() }
                        } catch (e: Exception) {
                            null
                        }
                        runOnUiThread { result.success(texto) }
                    }.start()
                    else -> result.notImplemented()
                }
            }
    }

    /// Con qué dibuja Flutter: lo dice el motor en el registro de la app al
    /// arrancar ("Using the Impeller rendering backend (Vulkan)").
    private fun conQueDibuja(): String? {
        return try {
            val proceso = Runtime.getRuntime().exec(arrayOf("logcat", "-d", "-v", "raw", "-t", "3000"))
            val linea = proceso.inputStream.bufferedReader().useLines { lineas ->
                lineas.lastOrNull { it.contains("rendering backend") }
            }
            proceso.destroy()
            when {
                linea == null -> null
                linea.contains("Vulkan", ignoreCase = true) -> "Vulkan"
                linea.contains("OpenGL", ignoreCase = true) -> "OpenGL"
                else -> linea.trim().take(40)
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun ponerMulticast(prender: Boolean) {
        if (prender) {
            if (multicast?.isHeld == true) return
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val bloqueo = wifi.createMulticastLock("junior_eventos_tele")
            bloqueo.setReferenceCounted(false)
            bloqueo.acquire()
            multicast = bloqueo
        } else {
            multicast?.let { if (it.isHeld) it.release() }
            multicast = null
        }
    }

    /// Copia la página del celular (los archivos `puesto/` del APK) a [destino], una vez
    /// por versión instalada: la marca es la fecha en que se instaló el APK.
    private fun copiarPuesto(destino: File): Boolean {
        val instalada = packageManager.getPackageInfo(packageName, 0).lastUpdateTime.toString()
        val marca = File(destino, ".version")
        if (marca.exists() && marca.readText() == instalada && File(destino, "index.html").exists()) {
            return true
        }
        val archivos = assets.list("puesto") ?: return false
        if (archivos.isEmpty()) return false
        if (destino.exists()) destino.deleteRecursively()
        copiarCarpeta("puesto", destino)
        marca.writeText(instalada)
        return File(destino, "index.html").exists()
    }

    private fun copiarCarpeta(desde: String, hacia: File) {
        val hijos = assets.list(desde) ?: return
        if (hijos.isEmpty()) {
            // Un archivo (assets.list de un archivo devuelve vacío).
            hacia.parentFile?.mkdirs()
            assets.open(desde).use { entrada ->
                hacia.outputStream().use { salida -> entrada.copyTo(salida) }
            }
            return
        }
        hacia.mkdirs()
        for (hijo in hijos) {
            copiarCarpeta("$desde/$hijo", File(hacia, hijo))
        }
    }

    override fun onDestroy() {
        multicast?.let { if (it.isHeld) it.release() }
        multicast = null
        super.onDestroy()
    }
}
