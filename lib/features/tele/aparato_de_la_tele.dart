import 'dart:io';

import 'package:flutter/services.dart';

/// Lo que se sabe del aparato, para "Cómo anda" **en la app de prueba**
/// (25-nov-2026): si la app corre en 32 o 64 bits, con qué dibuja (Vulkan u
/// OpenGL), el modelo. Lo pregunta a Android (`MainActivity.kt`, canal
/// `junior_eventos/aparato`). En la app de verdad no se muestra.
class AparatoDeLaTele {
  const AparatoDeLaTele({this.bits, this.dibujaCon, this.modelo});

  final int? bits;
  final String? dibujaCon;
  final String? modelo;

  static const _canal = MethodChannel('junior_eventos/aparato');

  /// Null fuera de Android o si no contesta.
  static Future<AparatoDeLaTele?> leer() async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await _canal.invokeMapMethod<String, Object?>('datos');
      if (m == null) return null;
      return AparatoDeLaTele(
        bits: m['bits'] as int?,
        dibujaCon: m['dibuja'] as String?,
        modelo: m['modelo'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// "64 bits · Vulkan · Quint QT1-50".
  String get texto => [
        if (bits != null) '$bits bits',
        ?dibujaCon,
        ?modelo,
      ].join(' · ');

  /// Lo que trae la app de prueba de la tele, si lo trae: los salones de los
  /// eventos de verdad, sin nombres (`tool/salones_de_verdad.py`). En la app
  /// de verdad no está.
  static Future<String?> salonesDePrueba() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _canal.invokeMethod<String>('salonesDePrueba');
    } catch (_) {
      return null;
    }
  }
}
