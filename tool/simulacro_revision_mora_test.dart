// Simulacro de la revisión de la mora de la 6.0.0 sobre una COPIA de la base
// del usuario (15-oct-2026). Corre lo mismo que va a correr la app sola al
// abrirse por primera vez con la versión nueva, y lista a cada alumno al que le
// cambia algo: la mora de hoy antes y después, el "ya usado", la ficha y la
// eximición.
//
// Nunca abre la base real: trabaja sobre una copia de la copia, en una carpeta
// temporal. La nube apunta a ningún lado.
//
//   flutter test tool/simulacro_revision_mora_test.dart
//     --dart-define=copia=<data.db copiada con VACUUM INTO>
//     --dart-define=salida=<carpeta>
//
// Comprueba además que ningún perdón cambió: los que tienen ajuste de ficha
// conservan su eximición tal cual.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');

class _Estado {
  final String nombre;
  final String institucion;
  final double mora;
  final double offset;
  final double tracked;
  final double ajuste;
  final DateTime? exenta;
  final bool reinicia;
  _Estado(this.nombre, this.institucion, this.mora, this.offset, this.tracked,
      this.ajuste, this.exenta, this.reinicia);

  String get eximicion => exenta == null
      ? 'sin'
      : '${exenta!.day.toString().padLeft(2, '0')}/'
            '${exenta!.month.toString().padLeft(2, '0')}'
            '${reinicia ? '' : ' permanente'}';
}

Future<Map<String, _Estado>> _foto(DateTime hoy) async {
  final db = await LocalDatabase.instance;
  final rows = await db.rawQuery('''
    SELECT a.*, coalesce(cl.nombre_completo, '?') AS institucion
    FROM contratos_alumnos a
    LEFT JOIN eventos e ON e.id = a.evento_id
    LEFT JOIN clientes cl ON cl.id = e.cliente_id''');
  final out = <String, _Estado>{};
  for (final r in rows) {
    final c = ContratoAlumno.fromJson(Map<String, dynamic>.from(r));
    final pagos = (await db.query(
      'pagos_contrato_alumno',
      where: 'contrato_alumno_id = ?',
      whereArgs: [c.id],
    )).map((p) => Map<String, dynamic>.from(p)).toList();
    final mora = MoraCuotaCalculator.moraPendienteOperativa(
      contrato: c,
      moraCobradaHistorial: MoraTrackedRecovery.moraCobradaDelHistorial(pagos),
      ahoraAr: hoy,
    );
    out[c.id] = _Estado(
      c.nombreAlumno,
      r['institucion'] as String,
      mora,
      c.moraCobradaOffset,
      c.moraPendienteTracked,
      c.moraTrackedAjuste,
      c.moraExentaHasta,
      c.moraExencionReinicia,
    );
  }
  return out;
}

String _p(double v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}\$$b';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('simulacro de la revisión de la mora sobre la copia', () async {
    expect(_copia, isNotEmpty, reason: 'Falta --dart-define=copia=...');
    final real = '${Platform.environment['USERPROFILE']}\\Documents\\'
        'Junior Eventos\\data.db';
    expect(File(_copia).absolute.path.toLowerCase(),
        isNot(File(real).absolute.path.toLowerCase()));

    final docs = Directory.systemTemp.createTempSync('simulacro_mora');
    final carpeta = Directory('${docs.path}${Platform.pathSeparator}Junior Eventos')
      ..createSync(recursive: true);
    File(_copia).copySync('${carpeta.path}${Platform.pathSeparator}data.db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );

    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day, 12);
    try {
      final db = await LocalDatabase.instance;
      final antes = await _foto(hoy);
      // 6.1.0: las fichas que no se explican cuota por cuota, antes y después.
      final sinExplicarAntes = await MoraTrackedRecovery.fichasSinExplicar(db);

      final reloj = Stopwatch()..start();
      final renglones = <String>[];
      final corregidos = await MoraTrackedRecovery.reconciliarTodos(
        db: db,
        encolarSync: true,
        ahoraAr: hoy,
        constancia: (r) async => renglones.addAll(r),
      );
      final eximiciones = await MoraTrackedRecovery.repararExencionDesdeHistorial(
        db: db,
        encolarSync: true,
      );
      reloj.stop();
      final despues = await _foto(hoy);
      final sinExplicarDespues =
          await MoraTrackedRecovery.fichasSinExplicar(db);
      final cola = (await db.rawQuery(
        "SELECT count(*) AS n FROM _sync_queue WHERE tabla = 'contratos_alumnos'",
      )).first['n'];

      final cambios = <String>[];
      var sumaAntes = 0.0, sumaDespues = 0.0, suben = 0, bajan = 0, igual = 0;
      final perdonesTocados = <String>[];
      final ordenados = antes.keys.toList()
        ..sort((a, b) {
          final x = antes[a]!, y = antes[b]!;
          final i = x.institucion.compareTo(y.institucion);
          return i != 0 ? i : x.nombre.compareTo(y.nombre);
        });
      for (final id in ordenados) {
        final a = antes[id]!, d = despues[id]!;
        final algo = (a.mora - d.mora).abs() > 0.01 ||
            (a.offset - d.offset).abs() > 0.01 ||
            (a.tracked - d.tracked).abs() > 0.01 ||
            a.eximicion != d.eximicion;
        if (!algo) continue;
        if (a.ajuste.abs() > 0.01 && a.eximicion != d.eximicion) {
          perdonesTocados.add(a.nombre);
        }
        sumaAntes += a.mora;
        sumaDespues += d.mora;
        if (d.mora > a.mora + 0.01) {
          suben++;
        } else if (d.mora < a.mora - 0.01) {
          bajan++;
        } else {
          igual++;
        }
        cambios.add(
          '${a.institucion.padRight(22)} ${a.nombre.padRight(32)} '
          'mora ${_p(a.mora).padLeft(9)} -> ${_p(d.mora).padLeft(9)} | '
          'ya usado ${_p(a.offset)} -> ${_p(d.offset)} | '
          'ficha ${_p(a.tracked)} -> ${_p(d.tracked)} | '
          'eximición ${a.eximicion} -> ${d.eximicion}',
        );
      }

      final b = StringBuffer()
        ..writeln('SIMULACRO DE LA REVISIÓN DE LA MORA (6.0.0) — '
            '${hoy.day}/${hoy.month}/${hoy.year}, sobre una copia de la base')
        ..writeln()
        ..writeln('Alumnos en la base: ${antes.length}')
        ..writeln('Corregidos por la revisión: $corregidos '
            '(más $eximiciones con la eximición reparada)')
        ..writeln('Con algún cambio: ${cambios.length} · la mora sube a $suben, '
            'baja a $bajan, queda igual a $igual')
        ..writeln('Mora de esos alumnos: ${_p(sumaAntes)} -> ${_p(sumaDespues)}')
        ..writeln('Alumnos que suben a la nube: $cola')
        ..writeln('Perdones (con ajuste de ficha) con la eximición cambiada: '
            '${perdonesTocados.isEmpty ? 'ninguno' : perdonesTocados.join(', ')}')
        ..writeln('Tiempo de la revisión: ${reloj.elapsedMilliseconds} ms')
        ..writeln()
        ..writeln('ALUMNO POR ALUMNO')
        ..writeAll(cambios.map((c) => '  $c\n'))
        ..writeln()
        ..writeln('LA CONSTANCIA QUE QUEDARÍA EN revision_mora.txt')
        ..writeAll(renglones.map((r) => '  $r\n'))
        ..writeln()
        ..writeln('FICHAS QUE NO SE EXPLICAN CUOTA POR CUOTA (6.1.0)')
        ..writeln('  antes de la revisión: ${sinExplicarAntes.length}')
        ..writeAll(sinExplicarAntes.map((r) => '    $r\n'))
        ..writeln('  después: ${sinExplicarDespues.length}')
        ..writeAll(sinExplicarDespues.map((r) => '    $r\n'));
      print(b.toString());
      if (_salida.isNotEmpty) {
        Directory(_salida).createSync(recursive: true);
        File('$_salida${Platform.pathSeparator}simulacro_revision_mora.txt')
            .writeAsStringSync(b.toString());
      }
      expect(perdonesTocados, isEmpty, reason: 'Un perdón no se toca.');
    } finally {
      await LocalDatabase.close();
      try {
        docs.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
