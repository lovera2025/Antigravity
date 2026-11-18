// Simulacro de "el descuento es para lo que la familia tenía al sorteo"
// (regla del usuario, 17-nov-2026) sobre una COPIA de la base del usuario.
//
// Por cada fiesta masiva ya sorteada dice a quién le propone "agregó después
// del sorteo" (tildado) y a quién deja "para revisar", con su porqué: es la
// lista que el jefe va a ver en PRECIOS. Y comprueba:
//   • que **sin nada aceptado las entradas de todos dan igual que hoy**;
//   • que al aceptar "como viene" solo cambian las familias tildadas;
//   • que guardar lo aceptado (`completarLugaresEn`, sobre otra copia) le
//     agrega los lugares al renglón del sorteo y **no cambia nada más** de la
//     base: ni otra tabla, ni otro renglón, ni otra columna de ese renglón.
//
// Nunca abre la base real ni la nube. La lista lleva nombres y qué pagó cada
// uno: va a `salida`, fuera de git.
//
//   python -I tool/copiar_base_solo_lectura.py <copia>
//   flutter test tool/simulacro_lugares_al_sorteo_test.dart
//     --dart-define=copia=<copia de data.db>
//     --dart-define=salida=<carpeta, fuera de git>

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/features/eventos/repositories/sorteos_mesas_repository.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sillas_reparto.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');

class _Fiesta {
  final String id;
  final String nombre;
  final List<ContratoAlumno> alumnos;
  final List<SorteoMesasRegistro> registros;
  final Map<String, List<Map<String, dynamic>>> pagos;
  final Map<String, SillasReparto> repartos;

  _Fiesta(this.id, this.nombre, this.alumnos, this.registros, this.pagos,
      this.repartos);
}

Future<List<_Fiesta>> _leer(Database db) async {
  final fiestas = <_Fiesta>[];
  final eventos = await db.rawQuery(
    'SELECT e.id AS id, c.nombre_completo AS nombre, e.fecha_evento AS fecha '
    'FROM eventos e LEFT JOIN clientes c ON c.id = e.cliente_id '
    "WHERE lower(e.modalidad) = 'masivo' ORDER BY e.fecha_evento",
  );
  for (final e in eventos) {
    final id = e['id'] as String;
    final alumnos = [
      for (final r in await db.query(
        'contratos_alumnos',
        where: 'evento_id = ?',
        whereArgs: [id],
      ))
        ContratoAlumno.fromJson(Map<String, dynamic>.from(r)),
    ];
    final registros = [
      for (final r in await db.query(
        'sorteos_mesas',
        where: 'evento_id = ?',
        whereArgs: [id],
        orderBy: 'created_at ASC, id ASC',
      ))
        SorteoMesasRegistro.fromMap(Map<String, dynamic>.from(r)),
    ];
    final pagos = <String, List<Map<String, dynamic>>>{};
    final repartos = <String, SillasReparto>{};
    final ids = [for (final a in alumnos) a.id];
    for (var i = 0; i < ids.length; i += 200) {
      final parte = ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
      final marcas = List.filled(parte.length, '?').join(',');
      for (final p in await db.rawQuery(
        'SELECT * FROM pagos_contrato_alumno WHERE contrato_alumno_id IN ($marcas)',
        parte,
      )) {
        pagos
            .putIfAbsent(p['contrato_alumno_id'] as String, () => [])
            .add(Map<String, dynamic>.from(p));
      }
      for (final r in await db.rawQuery(
        'SELECT * FROM sillas_reparto WHERE contrato_alumno_id IN ($marcas)',
        parte,
      )) {
        repartos[r['contrato_alumno_id'] as String] =
            SillasReparto.fromMap(Map<String, dynamic>.from(r));
      }
    }
    final fecha = '${e['fecha'] ?? ''}';
    fiestas.add(_Fiesta(
      id,
      '${e['nombre'] ?? id}${fecha.length >= 10 ? ' (${fecha.substring(0, 10)})' : ''}',
      alumnos,
      registros,
      pagos,
      repartos,
    ));
  }
  return fiestas;
}

/// Todas las filas de todas las tablas, como texto: para comparar dos bases.
Future<Map<String, List<String>>> _todo(Database db) async {
  final tablas = [
    for (final r in await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      r['name'] as String,
  ];
  return {
    for (final t in tablas)
      t: [for (final r in await db.query(t)) jsonEncode(r)]..sort(),
  };
}

void main() {
  test('los lugares al sorteo, sobre las fiestas de verdad', () async {
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
      ..writeln('Simulacro: los lugares agregados después del sorteo (17-nov-2026)')
      ..writeln('Sobre una copia de la base. No se guardó nada en la base de verdad.')
      ..writeln('Es la lista que vas a ver en ENTRADAS → PRECIOS → REVISAR LA '
          'LISTA de cada fiesta ya sorteada.')
      ..writeln();
    final resumen = StringBuffer();
    final aAceptar = <String, ({String registroId, Map<String, String> lugares})>{};
    late final List<_Fiesta> fiestas;
    try {
      fiestas = await _leer(db);
    } finally {
      await db.close();
    }

    var sorteadas = 0;
    for (final f in fiestas) {
      final foto = LugaresAlSorteo.vigente(f.registros);
      final conAlgo = [
        for (final a in f.alumnos)
          if (LugaresCargados.de(a).tieneAdicionales) a,
      ];
      final hoy = {
        for (final a in f.alumnos) a.id: RetiroEntradas.entradasDe(a),
      };
      final aComprarHoy =
          hoy.values.fold<int>(0, (s, e) => s + e.conDescuento);

      // Sin nada aceptado (o sin sorteo), todo sigue como hoy.
      if (foto.estado != EstadoDeLosLugares.anotados) {
        for (final a in f.alumnos) {
          final e = RetiroEntradas.entradasDe(a, foto: foto);
          expect(e.conDescuento, hoy[a.id]!.conDescuento,
              reason: '${f.nombre}: cambió una cuenta sin aceptar nada');
          expect(e.sinDescuento, 0, reason: f.nombre);
          expect(e.generales, hoy[a.id]!.generales, reason: f.nombre);
        }
      }

      final estado = switch (foto.estado) {
        EstadoDeLosLugares.sinSorteo => 'sin sortear',
        EstadoDeLosLugares.sinAnotar => 'SORTEADA, falta revisar',
        EstadoDeLosLugares.anotados => 'sorteada, con los lugares anotados',
      };
      resumen.writeln('${f.nombre}: $estado · ${f.alumnos.length} alumnos · '
          '${conAlgo.length} con mesa adicional o sillas · '
          '$aComprarHoy entradas con descuento hoy');
      if (foto.estado != EstadoDeLosLugares.sinAnotar) continue;
      sorteadas++;

      final enDuda = LugaresAlSorteo.enDuda(
        registros: f.registros,
        alumnos: f.alumnos,
        pagos: f.pagos,
        repartos: f.repartos,
      );
      final tildadas = [for (final d in enDuda) if (d.despues) d];
      final paraRevisar = [for (final d in enDuda) if (!d.despues) d];
      final bajas = {
        for (final a in f.alumnos)
          if (a.esBajaTemporal) a.id,
      };
      String linea(LugarEnDuda d) =>
          '  · ${d.nombre}${bajas.contains(d.alumnoId) ? ' (de baja)' : ''} — '
          '${d.queEs} (${d.entradas} ${d.entradas == 1 ? 'entrada' : 'entradas'})\n'
          '${d.huellas.map((h) => '      $h').join('\n')}';

      conNombres
        ..writeln('══ ${f.nombre}')
        ..writeln('El sorteo fue el ${ArTime.formatFechaHora(foto.sorteoEl!)}. '
            '${f.alumnos.length} alumnos, ${conAlgo.length} con mesa adicional '
            'o sillas extra.')
        ..writeln()
        ..writeln('SE AGREGARON DESPUÉS DEL SORTEO (vienen tildados: pagan la '
            'entrada entera): ${tildadas.length}')
        ..writeln(tildadas.isEmpty ? '  (ninguno)' : tildadas.map(linea).join('\n'))
        ..writeln()
        ..writeln('PARA REVISAR (sin tildar: quedan con descuento salvo que '
            'vos los tildes): ${paraRevisar.length}')
        ..writeln(
            paraRevisar.isEmpty ? '  (ninguno)' : paraRevisar.map(linea).join('\n'))
        ..writeln();

      // Aceptar "como viene".
      final pagaEntera = {for (final d in tildadas) d.clave};
      final lugares = LugaresAlSorteo.alAceptar(
        alumnos: f.alumnos,
        enDuda: enDuda,
        pagaEntera: pagaEntera,
      );
      final aceptada = FotoDeLosLugares.anotada({
        for (final e in lugares.entries)
          e.key: LugaresCargados.deTexto(e.value)!,
      });
      final tocadas = {for (final d in tildadas) d.alumnoId};
      var conDescuento = 0, sinDescuento = 0;
      for (final a in f.alumnos) {
        final e = RetiroEntradas.entradasDe(a, foto: aceptada);
        conDescuento += e.conDescuento;
        sinDescuento += e.sinDescuento;
        expect(e.conDescuento + e.sinDescuento, hoy[a.id]!.aComprar,
            reason: '${f.nombre}: no se parte entero');
        expect(e.generales, hoy[a.id]!.generales, reason: f.nombre);
        if (!tocadas.contains(a.id)) {
          expect(e.sinDescuento, 0,
              reason: '${f.nombre}: una familia sin tildar perdió el descuento');
          expect(e.conDescuento, hoy[a.id]!.conDescuento, reason: f.nombre);
        }
      }
      final sorteo = LugaresAlSorteo.primerDelJefe(f.registros)!;
      aAceptar[f.id] = (registroId: sorteo.id, lugares: lugares);
      final cuenta = 'Aceptando la lista como viene: $conDescuento entradas con '
          'descuento y $sinDescuento sin descuento (hoy, $aComprarHoy con descuento).';
      conNombres
        ..writeln(cuenta)
        ..writeln();
      resumen
        ..writeln('    tildadas ${tildadas.length} · para revisar '
            '${paraRevisar.length}')
        ..writeln('    $cuenta');
    }

    // Guardar lo aceptado, sobre OTRA copia: solo cambia el renglón del sorteo.
    final otra = File(
      '${Directory.systemTemp.createTempSync('lugares_al_sorteo').path}'
      '${Platform.pathSeparator}copia_para_guardar.db',
    );
    File(_copia).copySync(otra.path);
    final dbOtra = await databaseFactoryFfi.openDatabase(otra.path);
    try {
      final antes = await _todo(dbOtra);
      for (final e in aAceptar.entries) {
        final bien = await dbOtra.transaction(
          (txn) => SorteosMesasRepository.completarLugaresEn(
            txn,
            e.value.registroId,
            e.value.lugares,
          ),
        );
        expect(bien, isTrue, reason: 'no se guardó en ${e.key}');
      }
      final despues = await _todo(dbOtra);
      expect(despues.keys.toList(), antes.keys.toList());
      final renglones = {for (final e in aAceptar.values) e.registroId};
      for (final tabla in antes.keys) {
        if (tabla == 'sorteos_mesas' || tabla == '_sync_queue') continue;
        expect(despues[tabla], antes[tabla], reason: 'cambió la tabla $tabla');
      }
      // El registro: los mismos renglones; solo cambian los aceptados, y de
      // ellos solo el texto (con la clave agregada) y la fecha de la fila.
      final a = {
        for (final r in antes['sorteos_mesas']!)
          (jsonDecode(r) as Map)['id'] as String: jsonDecode(r) as Map,
      };
      final d = {
        for (final r in despues['sorteos_mesas']!)
          (jsonDecode(r) as Map)['id'] as String: jsonDecode(r) as Map,
      };
      expect(d.keys.toSet(), a.keys.toSet());
      for (final id in a.keys) {
        if (!renglones.contains(id)) {
          expect(d[id], a[id], reason: 'cambió un renglón que no se aceptó');
          continue;
        }
        for (final c in a[id]!.keys) {
          if (c == 'resultado' || c == 'updated_at') continue;
          expect(d[id]![c], a[id]![c], reason: 'cambió $c del renglón');
        }
        final textoAntes = jsonDecode(a[id]!['resultado'] as String) as Map;
        final textoDespues = jsonDecode(d[id]!['resultado'] as String) as Map;
        expect(textoDespues.containsKey('_lugares'), isTrue);
        textoDespues.remove('_lugares');
        expect(textoDespues, textoAntes,
            reason: 'cambió algo de lo que el renglón dice del sorteo');
      }
      expect(
        despues['_sync_queue']!.length - antes['_sync_queue']!.length,
        lessThanOrEqualTo(renglones.length),
      );
      // Y con eso guardado, cada fiesta queda con los lugares anotados y sin
      // nada para revisar.
      for (final f in await _leer(dbOtra)) {
        if (!aAceptar.containsKey(f.id)) continue;
        expect(LugaresAlSorteo.vigente(f.registros).estado,
            EstadoDeLosLugares.anotados,
            reason: f.nombre);
        expect(
          LugaresAlSorteo.enDuda(
            registros: f.registros,
            alumnos: f.alumnos,
            pagos: f.pagos,
            repartos: f.repartos,
          ),
          isEmpty,
        );
      }
      resumen
        ..writeln()
        ..writeln('Guardar lo aceptado (sobre otra copia): ${renglones.length} '
            'renglones del registro con los lugares agregados; ninguna otra '
            'tabla, renglón ni columna cambió.');
    } finally {
      await dbOtra.close();
      otra.parent.deleteSync(recursive: true);
    }

    conNombres
      ..writeln('── Resumen')
      ..write(resumen);
    print(resumen);
    print('Fiestas masivas: ${fiestas.length}; sorteadas sin revisar: $sorteadas.');
    if (_salida.isNotEmpty) {
      Directory(_salida).createSync(recursive: true);
      final archivo = File(
        '$_salida${Platform.pathSeparator}simulacro_lugares_al_sorteo.txt',
      )..writeAsStringSync(conNombres.toString());
      print('── La lista, con nombres: ${archivo.path}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
