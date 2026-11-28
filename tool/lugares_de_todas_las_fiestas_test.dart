// Cómo está cada fiesta masiva sorteada con "lo que la familia tenía al sorteo"
// (27-nov-2026), con el código del programa (`LugaresAlSorteo.vigente`) sobre
// una COPIA de la base: si tiene la foto anotada, y qué familias tienen HOY más
// mesas o sillas que en la foto (eso es lo que paga sin descuento).
//
// No abre la base real ni la nube y no escribe en ninguna base. La salida lleva
// nombres: va a `salida`, fuera de git.
//
//   python -I tool/copiar_base_solo_lectura.py <copia>
//   flutter test tool/lugares_de_todas_las_fiestas_test.dart
//     --dart-define=copia=<copia de data.db> --dart-define=salida=<carpeta>

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/features/eventos/services/agregaron_despues.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');

void main() {
  test('la foto de los lugares de cada fiesta sorteada', () async {
    if (_copia.isEmpty || _salida.isEmpty) {
      print('Faltan --dart-define=copia=... y salida=...: no se corre.');
      return;
    }
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(_copia, options: OpenDatabaseOptions(readOnly: true));
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
      if (sorteo == null) continue;
      final foto = LugaresAlSorteo.vigente(registros);
      final alumnos = [
        for (final r in await db.query('contratos_alumnos', where: 'evento_id = ?', whereArgs: [id]))
          ContratoAlumno.fromJson(Map<String, dynamic>.from(r)),
      ]..sort((a, b) => a.nombreAlumno.compareTo(b.nombreAlumno));
      final conAlgoHoy =
          alumnos.where((a) => LugaresCargados.de(a).tieneAdicionales).length;
      // La misma cuenta que el aviso de VENDER (`AgregaronDespues`), acá con
      // las bajas también, marcadas: VENDER no las lista (no se les vende).
      final conMas = [
        for (final f in AgregaronDespues.de(foto: foto, alumnos: alumnos).familias)
          {
            'alumno': f.id,
            'nombre': f.alumno.nombreAlumno.trim(),
            'baja': f.alumno.esBajaTemporal,
            'mesas_hoy': f.alumno.numeroMesa,
            'al_sorteo': (foto.de(f.id) ?? LugaresCargados.soloElContrato).texto,
            'hoy': LugaresCargados.de(f.alumno).texto,
            'mesas_de_mas': f.mesas,
            'sillas_de_mas': f.sillas,
            'entradas_sin_descuento': f.entradas,
          },
      ];
      fiestas.add({
        'evento': id,
        'nombre': '${e['nombre'] ?? id}',
        'fecha': '${e['fecha'] ?? ''}',
        'sorteo_id': sorteo.id,
        'sorteo_el': sorteo.createdAt.toUtc().toIso8601String(),
        'estado': foto.estado.name,
        'alumnos': alumnos.length,
        'con_algo_hoy': conAlgoHoy,
        'pagan_sin_descuento': conMas,
      });
      print('${e['nombre']}: ${foto.estado.name}, ${alumnos.length} alumnos, $conAlgoHoy con mesa adicional o '
          'sillas, ${conMas.length} con algo agregado después');
    }
    await db.close();
    final archivo = File('$_salida/lugares_de_todas.json')..createSync(recursive: true);
    archivo.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(fiestas));
    print('${fiestas.length} fiestas -> ${archivo.path}');
  });
}
