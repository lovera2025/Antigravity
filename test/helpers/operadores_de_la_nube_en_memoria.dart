// Los operadores y sus permisos **como los devuelve la nube** (con `activo` booleano),
// en una lista. Lo usan `test/encargada_en_la_web_test.dart` y la ventana de prueba
// `tool/encargada_web_prueba.dart`. Nada toca la nube de verdad.
import 'dart:async';

import 'package:arguello_events/features/caja_sesiones/services/operador_por_la_nube.dart';

class OperadoresDeLaNubeEnMemoria implements OperadoresDeLaNube {
  final operadores = <Map<String, dynamic>>[];
  final permisos = <Map<String, dynamic>>[];

  /// Si está, cada consulta falla con esto (sin internet).
  Object? falla;

  /// La nube no contesta nunca.
  bool colgada = false;

  /// Cuántas veces se le preguntó por un PIN.
  var consultas = 0;

  /// Suma un operador. [barra]: 0 nada, 1 cajera, 2 encargada. Con [conFila] en
  /// false no tiene fila de permisos (es de Cobros solo).
  void poner(
    String id,
    String nombre,
    String pin, {
    Object activo = true,
    bool conFila = true,
    int cobros = 0,
    int entradas = 0,
    int barra = 0,
  }) {
    operadores.add({
      'id': id,
      'nombre': nombre,
      'pin': pin,
      'activo': activo,
      'created_at': '2026-11-01T12:00:00+00:00',
      'updated_at': '2026-11-01T12:00:00+00:00',
    });
    if (!conFila) return;
    permisos.add({
      'id': 'f${id.substring(1)}',
      'operador_id': id,
      'cobros': cobros,
      'entradas': entradas,
      'barra': barra,
      'hecho_por': 'Jefe',
      'device_id': null,
      'created_at': '2026-11-01T12:00:00+00:00',
      'updated_at': '2026-11-01T12:00:00+00:00',
    });
  }

  Future<List<Map<String, dynamic>>> _contestar(List<Map<String, dynamic>> filas) {
    if (falla != null) return Future.error(falla!);
    if (colgada) return Completer<List<Map<String, dynamic>>>().future;
    return Future.value(filas);
  }

  @override
  Future<List<Map<String, dynamic>>> conPin(String pin) {
    consultas++;
    return _contestar([for (final o in operadores) if (o['pin'] == pin) o]);
  }

  @override
  Future<List<Map<String, dynamic>>> permisosDe(String operadorId) =>
      _contestar([for (final p in permisos) if (p['operador_id'] == operadorId) p]);
}
