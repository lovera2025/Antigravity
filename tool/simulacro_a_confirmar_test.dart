// Simulacro de la mesa adicional "a confirmar" (6.9.2) sobre una COPIA de la
// base del usuario: qué mesas saldrían hoy "a confirmar" en cada evento masivo.
//
// Sirve para mirar, antes de publicar, que la cuenta de los pagos no marque de
// más: una adicional que el contrato da por paga y los pagos no (o al revés)
// es justo lo que haría que el tótem dejara de encender una mesa que la
// familia pagó. Por cada fiesta dice cuántas hay, cuántas se podrían anular
// ($0 pagado) y **en cuántas el contrato y los pagos no dicen lo mismo**.
//
// Nunca abre la base real ni la nube. La lista lleva nombres y lo que pagó
// cada uno: va a `salida`, fuera de git.
//
//   python -I tool/copiar_base_solo_lectura.py <copia>
//   flutter test tool/simulacro_a_confirmar_test.dart
//     --dart-define=copia=<copia de data.db>
//     --dart-define=salida=<carpeta, fuera de git>

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/features/barra/cuentas/pesos.dart';
import 'package:arguello_events/features/eventos/services/adicional_a_confirmar.dart';
import 'package:arguello_events/features/eventos/services/edicion_de_alumno.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');

void main() {
  test('las mesas adicionales a confirmar, sobre las fiestas de verdad',
      () async {
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
    final conNombres = StringBuffer()
      ..writeln('Simulacro: las mesas adicionales "a confirmar" (18-nov-2026)')
      ..writeln('Sobre una copia de la base. No se guardó nada en ningún lado.')
      ..writeln('Son las mesas que, con esta versión, la puerta y el plano '
          'mostrarían "a confirmar".')
      ..writeln();

    final eventos = await db.rawQuery(
      'SELECT e.id AS id, c.nombre_completo AS nombre, e.fecha_evento AS fecha '
      'FROM eventos e LEFT JOIN clientes c ON c.id = e.cliente_id '
      "WHERE lower(e.modalidad) = 'masivo' ORDER BY e.fecha_evento",
    );
    var fiestas = 0;
    var total = 0;
    var anulables = 0;
    var sinMesa = 0;
    var distintas = 0;
    var noSeBajaria = 0;
    for (final (n, e) in eventos.indexed) {
      final id = e['id'] as String;
      final alumnos = [
        for (final r in await db.query(
          'contratos_alumnos',
          where: 'evento_id = ?',
          whereArgs: [id],
          orderBy: 'nombre_alumno COLLATE NOCASE ASC',
        ))
          ContratoAlumno.fromJson(Map<String, dynamic>.from(r)),
      ];
      final pagos = <String, List<Map<String, dynamic>>>{
        for (final a in alumnos) a.id: [],
      };
      final ids = [for (final a in alumnos) a.id];
      for (var i = 0; i < ids.length; i += 200) {
        final parte =
            ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
        final marcas = List.filled(parte.length, '?').join(',');
        for (final p in await db.rawQuery(
          'SELECT * FROM pagos_contrato_alumno WHERE contrato_alumno_id IN '
          '($marcas) ORDER BY fecha_pago ASC',
          parte,
        )) {
          pagos[p['contrato_alumno_id'] as String]!
              .add(Map<String, dynamic>.from(p));
        }
      }

      final sorteada = alumnos
          .any((a) => !a.esBajaTemporal && SalonMesas.tieneNumeros(a));
      final renglones = <String>[];
      var deLaFiesta = 0;
      var anulablesAca = 0;
      var sinMesaAca = 0;
      var distintasAca = 0;
      var conAdicional = 0;
      for (final a in alumnos) {
        if (a.esBajaTemporal) continue;
        if (SalonMesas.mesasExtra(a) > 0 && SalonMesas.tieneNumeros(a)) {
          conAdicional++;
        }
        final suyas = AdicionalesDeLaFamilia.aConfirmar(a, pagos[a.id]);
        if (suyas.isEmpty) continue;
        // Lo que dice la ficha: cuántas adicionales da por pagas.
        final segunLaFicha = MesasExtraUtils.estadoDesdeContrato(a)
            .where((m) => !m.liquidada)
            .length;
        final distinta = segunLaFicha != suyas.length;
        if (distinta) distintasAca++;
        for (final x in suyas) {
          deLaFiesta++;
          if (x.mesa == null) sinMesaAca++;
          var nota = '';
          if (x.sePuedeAnular && x.mesa != null) {
            anulablesAca++;
            final baja = BajaDeAdicional.de(a);
            if (!baja.sePuede) {
              noSeBajaria++;
              nota = ' · ANULAR diría: ${baja.problema}';
            }
          }
          renglones.add(
            '  ${a.nombreAlumno} · '
            '${x.mesa == null ? 'adicional sin mesa' : 'mesa ${x.mesa}'} · '
            'pagó ${pesos(x.pagado)} de ${pesos(x.precio)}'
            '${distinta ? ' · OJO: la ficha da $segunLaFicha sin pagar y los pagos ${suyas.length}' : ''}'
            '$nota',
          );
        }
      }
      if (!sorteada) continue;
      fiestas++;
      total += deLaFiesta;
      anulables += anulablesAca;
      sinMesa += sinMesaAca;
      distintas += distintasAca;
      final fecha = '${e['fecha'] ?? ''}';
      print('Fiesta ${n + 1}: $conAdicional familias con adicional y mesa · '
          '$deLaFiesta a confirmar ($anulablesAca sin nada pagado, '
          '$sinMesaAca sin mesa) · $distintasAca donde la ficha y los pagos no '
          'coinciden');
      conNombres
        ..writeln('${e['nombre'] ?? id}'
            '${fecha.length >= 10 ? ' (${fecha.substring(0, 10)})' : ''}: '
            '$deLaFiesta a confirmar, de $conAdicional familias con adicional')
        ..writeln(renglones.isEmpty ? '  (ninguna)' : renglones.join('\n'))
        ..writeln();
    }
    await db.close();

    print('── $fiestas fiestas masivas sorteadas · $total adicionales a '
        'confirmar ($anulables sin nada pagado, $sinMesa sin mesa)');
    print('── $distintas familias donde la ficha y los pagos no dicen lo mismo');
    print('── $noSeBajaria que ANULAR no dejaría bajar del contrato');
    if (_salida.isNotEmpty) {
      Directory(_salida).createSync(recursive: true);
      final f = File('$_salida${Platform.pathSeparator}simulacro_a_confirmar.txt')
        ..writeAsStringSync(conNombres.toString());
      print('── La lista, con nombres: ${f.path}');
    }
  });
}
