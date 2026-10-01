// Control de mesas y sillas con los datos reales, para llegar al sorteo
// sabiendo quién tiene qué y quién lo pagó.
//
// Por cada fiesta masiva dice lo mismo que el chip "Mesas y sillas" de la
// grilla: cuántas mesas hay cargadas, cuántas daría hoy el sorteo con lo
// pagado, y la lista de lo que hay que mirar (sin pago de la base, mesa
// agregada o sillas sin pagar, y los avisos del salón).
//
// **Solo lectura.** La base real se abre con `readOnly` y no se copia ni se
// escribe nada en ella. Es una foto del momento: conviene volver a correrlo
// cerca del sorteo.
//
//   flutter test tool/extras_muestra_test.dart
//   flutter test tool/extras_muestra_test.dart --dart-define=salida=<carpeta>
//
// Con `salida`, además de imprimirlo lo guarda en <carpeta>/mesas_y_sillas.txt.
// Opcional: --dart-define=base=<ruta> para otra base (siempre solo lectura).

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/features/eventos/services/filtro_mesas_sillas.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

String _baseReal() {
  const elegida = String.fromEnvironment('base');
  if (elegida.isNotEmpty) return elegida;
  final perfil = Platform.environment['USERPROFILE'] ?? '';
  return '$perfil\\Documents\\Junior Eventos\\data.db';
}

String _plata(double v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '\$$b';
}

void main() {
  test('mesas y sillas de cada fiesta, con los datos reales (solo lectura)',
      () async {
    sqfliteFfiInit();
    final ruta = _baseReal();
    if (!File(ruta).existsSync()) fail('No encuentro la base en $ruta');
    final db = await databaseFactoryFfi.openDatabase(
      ruta,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    final out = StringBuffer();
    void decir([String linea = '']) {
      print(linea);
      out.writeln(linea);
    }

    try {
      final eventos = await db.rawQuery(
        "SELECT e.id, e.encabezado_evento, e.fecha_evento "
        "FROM eventos e WHERE e.modalidad = 'masivo' "
        "ORDER BY e.encabezado_evento",
      );
      decir('MESAS Y SILLAS POR FIESTA · ${DateTime.now()}');
      decir('Base: $ruta (solo lectura)');
      var totalRevisar = 0;
      for (final ev in eventos) {
        final filas = await db.query(
          'contratos_alumnos',
          where: 'evento_id = ?',
          whereArgs: [ev['id']],
          orderBy: 'nombre_alumno',
        );
        if (filas.isEmpty) continue;
        final alumnos = filas.map(ContratoAlumno.fromJson).toList();
        final crudos = <String, List<Map<String, dynamic>>>{};
        for (var i = 0; i < alumnos.length; i += 300) {
          final parte = alumnos.skip(i).take(300).map((a) => a.id).toList();
          final pagos = await db.rawQuery(
            'SELECT * FROM pagos_contrato_alumno WHERE contrato_alumno_id IN '
            '(${List.filled(parte.length, '?').join(',')}) '
            'ORDER BY fecha_pago',
            parte,
          );
          for (final p in pagos) {
            (crudos[p['contrato_alumno_id'] as String] ??= []).add(p);
          }
        }
        final extras = extrasPorAlumno(alumnos, pagosPorAlumno(alumnos, crudos));
        final avisos = <String, List<String>>{};
        for (final a in SalonMesas.avisos(alumnos, pagosPorContrato: crudos)) {
          (avisos[a.alumnoId] ??= []).add(a.detalle);
        }
        final conAvisos = avisos.keys.toSet();
        final t = totalesDeExtras(alumnos, extras);
        final c = contarPorFiltro(alumnos, extras, conAvisos);
        final activos = alumnos.where((a) => !a.esBajaTemporal).length;
        final conNumero = alumnos.where(SalonMesas.tieneNumeros).length;

        decir();
        decir('══ ${ev['encabezado_evento'] ?? ev['id']} ══');
        decir('  Alumnos: $activos activos'
            '${alumnos.length > activos ? ' (+${alumnos.length - activos} de baja)' : ''}'
            ' · con mesa ya asignada: $conNumero');
        decir('  Mesas cargadas: ${t.mesas} (${t.agregadas} agregadas) · con lo '
            'pagado hoy el sorteo daría: ${t.conLoPagado}');
        decir('  Sillas extra cargadas: ${t.sillas}');
        decir('  Mesas agregadas → pagadas ${c[FiltroExtras.mesaPagada]}, '
            'en cuotas ${c[FiltroExtras.mesaEnCuotas]}, '
            'sin pagar ${c[FiltroExtras.mesaSinPagar]}');
        decir('  Sillas → pagadas ${c[FiltroExtras.sillasPagadas]}, '
            'en cuotas ${c[FiltroExtras.sillasEnCuotas]}, '
            'sin pagar ${c[FiltroExtras.sillasSinPagar]}');
        decir('  Sin pago de la base: ${c[FiltroExtras.sinPagoBase]}');

        void lista(String titulo, FiltroExtras f, String Function(ContratoAlumno, ExtrasSegunPago) detalle) {
          final quienes = [
            for (final a in alumnos)
              if (cumpleFiltroExtras(a, extras[a.id], f,
                  tieneAvisos: conAvisos.contains(a.id)))
                a,
          ];
          if (quienes.isEmpty) return;
          decir('  $titulo (${quienes.length}):');
          for (final a in quienes) {
            decir('    · ${a.nombreAlumno} — ${detalle(a, extras[a.id]!)}');
          }
        }

        lista(
          'Mesa agregada SIN PAGAR (el sorteo le da solo la del contrato)',
          FiltroExtras.mesaSinPagar,
          (a, e) => '${e.mesas.cantidad} agregada(s), ${_plata(e.mesas.precio)}',
        );
        lista(
          'Sillas SIN PAGAR',
          FiltroExtras.sillasSinPagar,
          (a, e) => '${e.sillas.cantidad} silla(s), ${_plata(e.sillas.precio)}',
        );
        final revisar = [
          for (final a in alumnos)
            if (!a.esBajaTemporal && conAvisos.contains(a.id)) a,
        ];
        if (revisar.isNotEmpty) {
          totalRevisar += revisar.length;
          decir('  PARA REVISAR (${revisar.length}):');
          for (final a in revisar) {
            for (final d in avisos[a.id]!) {
              decir('    · ${a.nombreAlumno} — $d');
            }
          }
        }
      }
      decir();
      decir('Fiestas masivas: ${eventos.length} · para revisar en total: '
          '$totalRevisar');
    } finally {
      await db.close();
    }

    const salida = String.fromEnvironment('salida');
    if (salida.isNotEmpty) {
      final f = File('$salida${Platform.pathSeparator}mesas_y_sillas.txt')
        ..writeAsStringSync(out.toString());
      print('── Guardado en: ${f.path}');
    }
  });
}
