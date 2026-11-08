package com.example.arguello_events

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // La pantalla de la tablet de la barra no se apaga mientras VENDER está
        // abierta (`PantallaDespierta`, en lib/features/barra/services/).
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
    }
}
