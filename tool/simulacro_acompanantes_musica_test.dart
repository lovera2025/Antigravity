// El simulacro del Excel del delegado con los datos de verdad: exporta, completa
// e importa las fiestas de alumnos de la base real, SOBRE UNA COPIA, y controla
// que lo único que cambia son los acompañantes y la música.
//
// La base real se abre SOLO LECTURA, y de ahí sale la copia con `VACUUM INTO`:
// una foto consistente aunque la app esté abierta. Todo lo demás pasa sobre la
// copia, en una carpeta temporal que se borra al terminar. No hay red: el
// cliente de la nube apunta a una dirección que no existe y nadie sincroniza.
//
// Qué hace, por cada institución (cada una es una fiesta):
//   1. exporta el Excel y controla que estén todos los alumnos activos, ninguno
//      de baja y ninguno de otra institución, y que salga cerrado;
//   2. lo completa como lo haría un delegado, con nombres y música inventados:
//      a propósito mete a uno con tres acompañantes y a otro con el nombre
//      cambiado;
//   3. lo importa en simulacro y controla el informe;
//   4. lo importa de verdad (en la copia) y compara la base entera contra la de
//      antes, tabla por tabla y columna por columna;
//   5. prueba meter ese Excel en otra institución: no tiene que entrar nada.
// Al final, la base real tiene que dar el mismo SHA-256 que al empezar.
//
//   flutter test tool/simulacro_acompanantes_musica_test.dart
//
// Opcional:
//   --dart-define=base=<ruta>     otra base (siempre solo lectura)
//   --dart-define=salida=<carpeta> deja ahí el informe y el Excel de la
//                                  institución más chica, como lo recibe el
//                                  delegado

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/services/planilla_delegado.dart';
import 'package:arguello_events/features/eventos/services/planilla_delegado_bloqueo.dart';
import 'package:arguello_events/features/eventos/widgets/acompanantes_musica_dialog.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

String _baseReal() {
  const elegida = String.fromEnvironment('base');
  if (elegida.isNotEmpty) return elegida;
  final perfil = Platform.environment['USERPROFILE'] ?? '';
  return '$perfil\\Documents\\Junior Eventos\\data.db';
}

class _SinConexion extends ConnectivityService {
  @override
  AppConnectivity get currentStatus => AppConnectivity.offline;
}

String _sha(String ruta) =>
    sha256.convert(File(ruta).readAsBytesSync()).toString();

/// Todas las filas de todas las tablas, por tabla y por id.
Future<Map<String, Map<String, Map<String, Object?>>>> _foto(Database db) async {
  final tablas = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  final foto = <String, Map<String, Map<String, Object?>>>{};
  for (final t in tablas) {
    final nombre = t['name'] as String;
    final filas = await db.rawQuery('SELECT rowid AS _rowid, * FROM "$nombre"');
    foto[nombre] = {
      for (final f in filas)
        '${f['id'] ?? f['_rowid']}': Map<String, Object?>.from(f)..remove('_rowid'),
    };
  }
  return foto;
}

const _cargables = {
  'nombres_acompanantes',
  'cantidad_acompanantes',
  'musica_elegida',
};

/// Lo que escribe el delegado en el renglón [i]: (acompañantes, música).
(String, String) _loQueEscribe(int i) => switch (i % 5) {
      0 => ('Mamá $i Inventada / Papá $i Inventado', 'Tema $i'),
      1 => ('Abuela $i Inventada', ''),
      2 => ('', 'Tema $i'),
      3 => ('', ''),
      _ => ('Tía $i Inventada; Tío $i Inventado', 'Tema $i'),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('simulacro: exportar e importar acompañantes y música (sobre copia)',
      () async {
    final real = _baseReal();
    if (!File(real).existsSync()) fail('No encuentro la base en $real');
    const salida = String.fromEnvironment('salida');
    final informe = StringBuffer();
    void decir([String linea = '']) {
      print(linea);
      informe.writeln(linea);
    }

    final shaAntes = _sha(real);
    final docs = await Directory.systemTemp.createTemp('simulacro_delegado_');
    Database? origen;
    try {
      // La copia, desde la real abierta solo lectura, donde la app la busca.
      final carpeta = Directory('${docs.path}${Platform.pathSeparator}Junior Eventos')
        ..createSync(recursive: true);
      final copia = '${carpeta.path}${Platform.pathSeparator}data.db';
      origen = await databaseFactoryFfi.openDatabase(
        real,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final versionReal = await origen.getVersion();
      await origen.execute("VACUUM INTO '${copia.replaceAll("'", "''")}'");
      await origen.close();
      origen = null;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => docs.path,
          );
      final db = await LocalDatabase.instance;
      expect(
        await LocalDatabase.dbPath,
        isNot(real),
        reason: 'la app tiene que estar mirando la copia, no la base real',
      );
      final repo = ContratosRepository(
        SupabaseClient('http://localhost:1', 'anon-de-test'),
        _SinConexion(),
      );

      decir('SIMULACRO: Excel de acompañantes y música');
      decir('Base real: $real (v$versionReal). Se trabajó sobre una copia.');
      decir('');

      // Las fiestas de alumnos: las que tienen contratos.
      final fiestas = await db.rawQuery(
        'SELECT evento_id, COUNT(*) AS n FROM contratos_alumnos '
        'GROUP BY evento_id ORDER BY n ASC',
      );
      expect(fiestas, isNotEmpty, reason: 'la base no tiene alumnos');
      await db.delete('_sync_queue');

      final exportados = <String, ({Uint8List bytes, String institucion})>{};
      var totalCargados = 0;
      var totalActivos = 0;

      for (final fiesta in fiestas) {
        final eventoId = fiesta['evento_id'] as String;
        final alumnos = await repo.getByEvento(eventoId);
        final activos = PlanillaDelegado.alumnosDeLaPlanilla(alumnos);
        final institucion = alumnos
                .map((a) => (a.institucion ?? '').trim())
                .firstWhere((i) => i.isNotEmpty, orElse: () => '') //
                .isNotEmpty
            ? alumnos
                .map((a) => (a.institucion ?? '').trim())
                .firstWhere((i) => i.isNotEmpty)
            : 'Fiesta ${eventoId.substring(0, 8)}';
        if (activos.isEmpty) continue;
        totalActivos += activos.length;

        // 1. Exportar.
        final planilla = exportarPlanillaDelegado(
          eventoId: eventoId,
          institucion: institucion,
          alumnos: alumnos,
        );
        expect(planilla.cerrada, isTrue, reason: '$institucion salió sin cerrar');
        final leido = PlanillaDelegado.leer(planilla.bytes);
        expect(leido.problema, isNull, reason: institucion);
        expect(leido.eventoId, eventoId, reason: institucion);
        expect(
          leido.renglones.map((r) => r.alumno).toList(),
          [for (final a in activos) PlanillaDelegado.nombreLimpio(a)],
          reason: '$institucion: no salieron los activos, o salieron de más',
        );
        final bajas = alumnos.where((a) => a.esBajaTemporal).length;
        expect(activos.length + bajas, alumnos.length);
        exportados[eventoId] = (bytes: planilla.bytes, institucion: institucion);

        // 2. Completar como un delegado.
        final excel = Excel.decodeBytes(planilla.bytes);
        final hoja = excel.tables.values.first;
        CellIndex en(int c, int f) =>
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: f);
        final primera = PlanillaDelegado.filaEncabezados + 1;
        // A propósito: el primero con tres, el segundo con el nombre cambiado.
        final conTres = activos.length > 1 ? activos[0] : null;
        final conOtroNombre = activos.length > 2 ? activos[1] : null;
        final esperados = <String, (String, String)>{};
        for (var i = 0; i < activos.length; i++) {
          final a = activos[i];
          var (acomp, musica) = _loQueEscribe(i);
          if (a.id == conTres?.id) acomp = 'Uno Inventado / Dos Inventado / Tres Inventado';
          if (a.id == conOtroNombre?.id) {
            hoja.cell(en(1, primera + i)).value =
                TextCellValue('NOMBRE CAMBIADO POR ERROR');
            acomp = 'Alguien Inventado';
          }
          hoja.cell(en(PlanillaDelegado.columnaAcompanantes, primera + i)).value =
              TextCellValue(acomp);
          hoja.cell(en(PlanillaDelegado.columnaMusica, primera + i)).value =
              TextCellValue(musica);
          if (a.id != conTres?.id && a.id != conOtroNombre?.id) {
            esperados[a.id] = (acomp, musica);
          }
        }
        final completado = Uint8List.fromList(excel.encode()!);

        // 3. Importar en simulacro.
        final r = PlanillaDelegado.comparar(
          lectura: PlanillaDelegado.leer(completado),
          alumnos: alumnos,
          eventoId: eventoId,
          institucion: institucion,
        );
        expect(r.rechazo, isNull, reason: institucion);
        final revisarEsperado = [conTres, conOtroNombre].whereType<ContratoAlumno>().length;
        expect(r.revisar, hasLength(revisarEsperado), reason: '$institucion: ${r.revisar}');
        final seCargan = esperados.entries
            .where((e) => e.value.$1.isNotEmpty || e.value.$2.isNotEmpty)
            .length;
        // Hoy nadie tiene nada cargado: todo lo completado es nuevo.
        final yaTenian = activos
            .where(
              (a) =>
                  PlanillaDelegado.limpios(a.nombresAcompanantes).isNotEmpty ||
                  (a.musicaElegida ?? '').trim().isNotEmpty,
            )
            .length;
        if (yaTenian == 0) {
          expect(r.cambios, hasLength(seCargan), reason: institucion);
          expect(r.vacios, esperados.length - seCargan, reason: institucion);
          expect(r.cambios.any((c) => c.pisaAlgo), isFalse);
        }
        for (final c in r.cambios) {
          expect(c.datos.keys.toSet().difference(_cargables), isEmpty);
          expect((c.acompanantes ?? const []).length, lessThanOrEqualTo(kMaxAcompanantes));
        }

        // 4. Importar de verdad, sobre la copia, y comparar la base entera.
        final antes = await _foto(db);
        await repo.cargarAcompanantesYMusica({
          for (final c in r.cambios) c.alumno.id: c.datos,
        });
        final despues = await _foto(db);

        final cargados = {for (final c in r.cambios) c.alumno.id: c};
        for (final tabla in antes.keys) {
          if (tabla == '_sync_queue') continue;
          expect(despues[tabla]!.keys.toSet(), antes[tabla]!.keys.toSet(),
              reason: '$institucion: cambiaron las filas de $tabla');
          for (final id in antes[tabla]!.keys) {
            final a = antes[tabla]![id]!;
            final d = despues[tabla]![id]!;
            for (final columna in a.keys) {
              final puedeCambiar = tabla == 'contratos_alumnos' &&
                  cargados.containsKey(id) &&
                  _cargables.contains(columna);
              if (puedeCambiar) continue;
              expect(d[columna], a[columna],
                  reason: '$institucion: cambió $tabla.$columna de $id');
            }
          }
        }
        // Lo cargado quedó como decía el Excel.
        for (final c in r.cambios) {
          final fila = despues['contratos_alumnos']![c.alumno.id]!;
          final (acomp, musica) = esperados[c.alumno.id]!;
          expect(
            (jsonDecode(fila['nombres_acompanantes'] as String? ?? '[]') as List)
                .cast<String>(),
            PlanillaDelegado.separarAcompanantes(acomp),
            reason: '$institucion: ${c.alumno.nombreAlumno}',
          );
          if (musica.isNotEmpty) expect(fila['musica_elegida'], musica);
          expect(
            fila['evento_id'],
            eventoId,
            reason: 'se cargó a un alumno de otra institución',
          );
        }
        // Lo que queda para subir: una entrada por alumno cargado, solo con eso.
        final cola = despues['_sync_queue']!.values
            .where((f) => cargados.containsKey(f['registro_id']))
            .toList();
        expect(cola, hasLength(r.cambios.length), reason: institucion);
        for (final f in cola) {
          expect(f['tabla'], 'contratos_alumnos');
          expect(f['operacion'], 'update');
          final payload = (jsonDecode(f['payload'] as String) as Map).keys.toSet()
            ..remove('id');
          expect(payload.difference(_cargables), isEmpty, reason: '$payload');
        }
        totalCargados += r.cambios.length;

        decir('${institucion.padRight(26)} ${'${activos.length}'.padLeft(4)} activos'
            '${bajas > 0 ? ' ($bajas de baja, no salen)' : ''}'
            ' · se cargan ${r.cambios.length} · vacíos ${r.vacios}'
            ' · revisar ${r.revisar.length}');
        for (final x in r.revisar) {
          decir('    revisar → ${x.motivo}');
        }
      }

      // 5. Una institución no pisa a otra.
      decir('');
      final ids = exportados.keys.toList();
      var cruces = 0;
      for (final origenId in ids) {
        for (final destinoId in ids) {
          if (origenId == destinoId) continue;
          final r = PlanillaDelegado.comparar(
            lectura: PlanillaDelegado.leer(exportados[origenId]!.bytes),
            alumnos: await repo.getByEvento(destinoId),
            eventoId: destinoId,
            institucion: exportados[destinoId]!.institucion,
          );
          expect(r.rechazo, isNotNull,
              reason: '${exportados[origenId]!.institucion} entró en '
                  '${exportados[destinoId]!.institucion}');
          expect(r.cambios, isEmpty);
          cruces++;
        }
      }
      decir('Cruces probados (el Excel de una en otra): $cruces. '
          'No entró ninguno.');
      decir('');
      decir('Instituciones: ${exportados.length} · alumnos activos: '
          '$totalActivos · cargados en la copia: $totalCargados.');
      decir('En toda la base de la copia cambiaron solo acompañantes y música '
          'de esos alumnos, y lo que quedó anotado para subir.');

      // La institución más chica, tal como la recibe el delegado.
      if (salida.isNotEmpty) {
        Directory(salida).createSync(recursive: true);
        final chica = exportados.values.first;
        final nombre = nombreArchivoPlanillaDelegado(chica.institucion);
        File('$salida${Platform.pathSeparator}$nombre')
            .writeAsBytesSync(chica.bytes);
        decir('');
        decir('Excel de muestra (como lo recibe el delegado): $nombre');
      }

      await LocalDatabase.close();
    } finally {
      await origen?.close();
      await LocalDatabase.close();
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    }

    final shaDespues = _sha(real);
    decir('');
    decir('Base real, antes:   $shaAntes');
    decir('Base real, después: $shaDespues');
    expect(shaDespues, shaAntes,
        reason: 'la base real cambió mientras corría la prueba (¿alguien '
            'cobró?): correla de nuevo con la app cerrada');
    decir('La base real quedó idéntica.');

    if (salida.isNotEmpty) {
      File('$salida${Platform.pathSeparator}simulacro_acompanantes_musica.txt')
          .writeAsStringSync(informe.toString());
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
