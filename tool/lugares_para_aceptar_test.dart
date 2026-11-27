// Lo que quedaría anotado al aceptar la lista de lugares de cada fiesta sorteada
// sin anotar (27-nov-2026), calculado **con el código del programa**
// (`LugaresAlSorteo.enDuda` y `alAceptar`) sobre una COPIA de la base.
//
// Sirve para preparar, fuera del programa, lo mismo que haría el jefe en
// ENTRADAS -> PRECIOS -> REVISAR LA LISTA tildando a quienes agregaron después
// del sorteo. No abre la base real ni la nube, y no escribe en ninguna base:
// deja un JSON en `salida` (lleva nombres: fuera de git).
//
//   python -I tool/copiar_base_solo_lectura.py <copia>
//   flutter test tool/lugares_para_aceptar_test.dart
//     --dart-define=copia=<copia de data.db>
//     --dart-define=salida=<carpeta, fuera de git>
//     [--dart-define=tildar=<json: {"<evento>": ["<clave>", ...]}>]
//
// Sin `tildar` usa lo que el programa trae tildado solo.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sillas_reparto.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');
const _tildar = String.fromEnvironment('tildar');

void main() {
  test('lo que quedaría anotado al aceptar cada lista', () async {
    if (_copia.isEmpty || _salida.isEmpty) {
      print('Faltan --dart-define=copia=... y salida=...: no se corre.');
      return;
    }
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      _copia,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final tildarDe = _tildar.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(File(_tildar).readAsStringSync()) as Map<String, dynamic>;
    final fiestas = <Map<String, dynamic>>[];
    final eventos = await db.rawQuery(
      'SELECT e.id AS id, c.nombre_completo AS nombre, e.fecha_evento AS fecha '
      'FROM eventos e LEFT JOIN clientes c ON c.id = e.cliente_id '
      "WHERE lower(e.modalidad) = 'masivo' ORDER BY e.fecha_evento",
    );
    for (final e in eventos) {
      final id = e['id'] as String;
      final registros = [
        for (final r in await db.query('sorteos_mesas',
            where: 'evento_id = ?', whereArgs: [id], orderBy: 'created_at ASC, id ASC'))
          SorteoMesasRegistro.fromMap(Map<String, dynamic>.from(r)),
      ];
      final sorteo = LugaresAlSorteo.primerDelJefe(registros);
      if (sorteo == null || sorteo.lugares != null) continue;
      final alumnos = [
        for (final r in await db.query('contratos_alumnos', where: 'evento_id = ?', whereArgs: [id]))
          ContratoAlumno.fromJson(Map<String, dynamic>.from(r)),
      ];
      final pagos = <String, List<Map<String, dynamic>>>{};
      final repartos = <String, SillasReparto>{};
      final ids = [for (final a in alumnos) a.id];
      for (var i = 0; i < ids.length; i += 200) {
        final parte = ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
        final marcas = List.filled(parte.length, '?').join(',');
        for (final p in await db.rawQuery(
            'SELECT * FROM pagos_contrato_alumno WHERE contrato_alumno_id IN ($marcas)', parte)) {
          pagos.putIfAbsent(p['contrato_alumno_id'] as String, () => []).add(Map<String, dynamic>.from(p));
        }
        for (final r in await db.rawQuery(
            'SELECT * FROM sillas_reparto WHERE contrato_alumno_id IN ($marcas)', parte)) {
          repartos[r['contrato_alumno_id'] as String] = SillasReparto.fromMap(Map<String, dynamic>.from(r));
        }
      }
      final enDuda = LugaresAlSorteo.enDuda(
        registros: registros,
        alumnos: alumnos,
        pagos: pagos,
        repartos: repartos,
      );
      final pedidas = tildarDe[id];
      final pagaEntera = pedidas is List
          ? {for (final c in pedidas) '$c'}
          : {for (final d in enDuda) if (d.despues) d.clave};
      final desconocidas = pagaEntera.difference({for (final d in enDuda) d.clave});
      expect(desconocidas, isEmpty, reason: 'claves que la lista de $id no tiene');
      final lugares = LugaresAlSorteo.alAceptar(alumnos: alumnos, enDuda: enDuda, pagaEntera: pagaEntera);
      // Sin tildar nada: lo que tiene hoy cada familia (para ver qué cambia).
      final sinTildar = LugaresAlSorteo.alAceptar(alumnos: alumnos, enDuda: enDuda, pagaEntera: const {});
      fiestas.add({
        'evento': id,
        'nombre': '${e['nombre'] ?? id}',
        'sorteo_id': sorteo.id,
        'sorteo_el': sorteo.createdAt.toUtc().toIso8601String(),
        'alumnos': alumnos.length,
        'en_duda': [
          for (final d in enDuda)
            {
              'clave': d.clave,
              'alumno': d.alumnoId,
              'nombre': d.nombre,
              'que': d.esMesa ? 'mesa' : 'sillas',
              'cantidad': d.cantidad,
              'el_programa_lo_tilda': d.despues,
              'tildado': pagaEntera.contains(d.clave),
              'huellas': d.huellas,
            },
        ],
        'lugares': lugares,
        'lugares_sin_tildar': sinTildar,
      });
      print('${e['nombre']}: ${enDuda.length} en duda, ${pagaEntera.length} tildados, '
          '${lugares.length} familias con algo al sorteo');
    }
    await db.close();
    final archivo = File('$_salida/lugares_para_aceptar.json')..createSync(recursive: true);
    archivo.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(fiestas));
    print('${fiestas.length} fiestas -> ${archivo.path}');
  });
}
