// Cuántas familias de cada evento masivo que viene quedan, con las cuentas de
// VENDER de la 6.9.3, en "Pagó todo: puede retirar", "Debe: a caja", "Revisar"
// y "Ya retiró", y cuántas tienen algo "a confirmar" (una mesa adicional o una
// silla extra que no está paga entera). Sobre una COPIA de la base del usuario
// (auditoría del 21/22-nov: saber antes de publicar cuántas quedan trabadas).
//
// Las cuentas son las mismas que usa VENDER (`RetiroEntradas.deudaDe`,
// `EntregaPorPartes.grupoDe`, `APagarDeLaFamilia.de`), sin otra cuenta al lado.
// Sin la foto de los lugares al sorteo: todo lo aparte va con descuento, que no
// cambia qué está pago.
//
// Nunca abre la base real ni la nube. La lista lleva nombres y lo que debe cada
// uno: va a `salida`, fuera de git.
//
//   python -I tool/copiar_base_solo_lectura.py <copia>
//   flutter test tool/familias_para_vender_test.dart
//     --dart-define=copia=<copia de data.db>
//     --dart-define=salida=<carpeta, fuera de git>

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/features/barra/cuentas/pesos.dart';
import 'package:arguello_events/features/eventos/services/entrega_por_partes.dart';
import 'package:arguello_events/features/eventos/services/lugares_pagos.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/core/utils/pago_interes_mora.dart'
    show esPagoInteresMoraPorConcepto, kLineKindInteresMora;
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');

void main() {
  test('las familias de cada fiesta que viene, en los grupos de VENDER', () async {
    if (_copia.isEmpty) {
      print('Falta --dart-define=copia=<copia de data.db>: no se corre.');
      return;
    }
    expect(File(_copia).existsSync(), isTrue, reason: 'no está la copia');
    expect(
      _copia.replaceAll('\\', '/').toLowerCase(),
      isNot(endsWith('junior eventos/data.db')),
      reason: 'esto se corre sobre una copia, nunca sobre la base de verdad',
    );
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      File(_copia).absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final hoy = ArTime.nowAr();
    final desde = DateTime(hoy.year, hoy.month, hoy.day).subtract(const Duration(days: 1));
    final conNombres = StringBuffer()
      ..writeln('Las familias de cada evento masivo que viene, con las cuentas de VENDER '
          '(6.9.3), ${ArTime.formatFechaHora(ArTime.nowUtc())}')
      ..writeln('Sobre una copia de la base. No se guardó nada en ningún lado.')
      ..writeln();
    final resumen = StringBuffer();

    final eventos = await db.rawQuery(
      'SELECT e.id AS id, c.nombre_completo AS nombre, e.fecha_evento AS fecha '
      'FROM eventos e LEFT JOIN clientes c ON c.id = e.cliente_id '
      "WHERE lower(e.modalidad) = 'masivo' ORDER BY e.fecha_evento",
    );
    for (final e in eventos) {
      final fecha = DateTime.tryParse('${e['fecha']}');
      if (fecha == null || fecha.isBefore(desde)) continue;
      final id = e['id'] as String;
      final alumnos = [
        for (final r in await db.query(
          'contratos_alumnos',
          where: 'evento_id = ?',
          whereArgs: [id],
          orderBy: 'nombre_alumno COLLATE NOCASE ASC',
        ))
          ContratoAlumno.fromJson(Map<String, dynamic>.from(r)),
      ].where((a) => !a.esBajaTemporal).toList();
      if (alumnos.isEmpty) continue;

      final grupos = {for (final g in GrupoDeRetiro.values) g: <String>[]};
      final aConfirmar = <String>[];
      for (final a in alumnos) {
        final pagos = [
          for (final p in await db.query(
            'pagos_contrato_alumno',
            where: 'contrato_alumno_id = ?',
            whereArgs: [a.id],
            orderBy: 'fecha_pago ASC',
          ))
            Map<String, dynamic>.from(p),
        ];
        var mora = 0.0;
        for (final p in pagos) {
          if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
          final lk = (p['line_kind'] as String?)?.trim();
          if (lk == kLineKindInteresMora ||
              esPagoInteresMoraPorConcepto(p['concepto'] as String? ?? '')) {
            mora += (p['monto'] as num).toDouble();
          }
        }
        final deuda = RetiroEntradas.deudaDe(a, pagos: pagos, moraCobradaHistorial: mora);
        final filas = await db.query(
          'entradas_retiro',
          where: 'contrato_alumno_id = ?',
          whereArgs: [a.id],
        );
        final estado = EstadoDeLaEntrega.deAlumno(
          a,
          retiro: filas.isEmpty ? null : EntradasRetiro.fromMap(Map<String, dynamic>.from(filas.first)),
          renglones: const [],
        );
        final grupo = EntregaPorPartes.grupoDe(a, deuda: deuda, estado: estado);
        final nombre = a.nombreAlumno.trim();
        grupos[grupo]!.add(switch (grupo) {
          GrupoDeRetiro.debe => '$nombre (debe ${pesos(deuda.total)})',
          GrupoDeRetiro.revisar => '$nombre (${RetiroEntradas.bloqueo(a, deuda).name})',
          _ => nombre,
        });
        final aPagar = APagarDeLaFamilia.de(a, pagos: pagos);
        final sinPagar = aPagar.lineas.where((l) => l.aConfirmar > 0).length;
        if (sinPagar > 0) {
          aConfirmar.add('$nombre (${aPagar.textoAConfirmar ?? '$sinPagar sin pagar entera'})');
        }
      }
      int n(GrupoDeRetiro g) => grupos[g]!.length;
      final titulo = '${e['nombre'] ?? 'Sin nombre'} · ${ArTime.formatFechaCorta(fecha)} · '
          '${alumnos.length} familias';
      final linea = '  puede retirar ${n(GrupoDeRetiro.puedeRetirar)} · '
          'debe ${n(GrupoDeRetiro.debe)} · revisar ${n(GrupoDeRetiro.revisar)} · '
          'ya retiró ${n(GrupoDeRetiro.yaRetiro)} · con algo a confirmar ${aConfirmar.length}';
      resumen
        ..writeln(titulo)
        ..writeln(linea);
      conNombres
        ..writeln(titulo)
        ..writeln(linea);
      for (final g in [GrupoDeRetiro.revisar, GrupoDeRetiro.debe]) {
        if (grupos[g]!.isEmpty) continue;
        conNombres.writeln('  ${g == GrupoDeRetiro.revisar ? 'REVISAR' : 'DEBE'}:');
        for (final x in grupos[g]!) {
          conNombres.writeln('    $x');
        }
      }
      if (aConfirmar.isNotEmpty) {
        conNombres.writeln('  A CONFIRMAR:');
        for (final x in aConfirmar) {
          conNombres.writeln('    $x');
        }
      }
      conNombres.writeln();
    }
    await db.close();
    print(resumen);
    if (_salida.isNotEmpty) {
      final dir = Directory(_salida)..createSync(recursive: true);
      final archivo = File('${dir.path}${Platform.pathSeparator}familias_para_vender.txt');
      archivo.writeAsStringSync(conNombres.toString());
      print('Con nombres en ${archivo.path}');
    }
  });
}
