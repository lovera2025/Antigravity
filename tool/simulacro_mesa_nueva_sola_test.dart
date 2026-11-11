// Simulacro de la mesa nueva sola (6.5.1) sobre una COPIA de la base del usuario.
// Dice, fiesta por fiesta, a quién le daría una mesa el programa la primera vez
// que se abra con la versión nueva, y qué número: lo mismo que va a correr la app
// (`MesaNuevaSola.calcular`), con el plano y los pagos de la copia.
//
// Nunca abre la base real ni la nube: lee la copia en solo lectura y no guarda
// nada. La copia se saca aparte (por ejemplo, con el respaldo de SQLite en modo
// solo lectura) y se le pasa:
//
//   flutter test tool/simulacro_mesa_nueva_sola_test.dart
//     --dart-define=copia=<copia de data.db>
//     --dart-define=salida=<carpeta, fuera de git: lleva nombres>
//
// La salida lleva nombres de alumnos: va a `build/`, que no está en git.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/services/mesa_nueva_sola.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');

void main() {
  test('a quién le daría una mesa sola, fiesta por fiesta', () async {
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
    // Con la ruta completa: una relativa, la librería la busca en otra carpeta.
    final db = await databaseFactoryFfi.openDatabase(
      File(_copia).absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final b = StringBuffer()
      ..writeln('Simulacro de la mesa nueva sola (6.5.1)')
      ..writeln('Sobre una copia de la base. No se guardó nada.')
      ..writeln();
    var total = 0;
    try {
      final planos = await db.query('planos_evento');
      for (final fila in planos) {
        final plano = PlanoEvento.fromMap(Map<String, dynamic>.from(fila));
        final eventoId = plano.eventoId;
        final alumnos = [
          for (final r in await db.query(
            'contratos_alumnos',
            where: 'evento_id = ?',
            whereArgs: [eventoId],
            orderBy: 'nombre_alumno COLLATE NOCASE ASC',
          ))
            ContratoAlumno.fromJson(Map<String, dynamic>.from(r)),
        ];
        final pagos = <String, List<Map<String, dynamic>>>{};
        for (final a in alumnos) {
          pagos[a.id] = [
            for (final p in await db.query(
              'pagos_contrato_alumno',
              where: 'contrato_alumno_id = ?',
              whereArgs: [a.id],
            ))
              Map<String, dynamic>.from(p),
          ];
        }
        final registros = [
          for (final r in await db.query(
            'sorteos_mesas',
            where: 'evento_id = ?',
            whereArgs: [eventoId],
          ))
            SorteoMesasRegistro.fromMap(Map<String, dynamic>.from(r)),
        ];
        final institucion = alumnos
            .map((a) => a.institucion?.trim() ?? '')
            .firstWhere((s) => s.isNotEmpty, orElse: () => eventoId);
        final conMesa = alumnos
            .where((a) => MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa)
                .isNotEmpty)
            .length;
        final armado = plano.armadoONull;
        b.writeln('== $institucion ==');
        b.writeln('  ${alumnos.length} alumnos, $conMesa con mesa, '
            '${armado?.mesas.length ?? 0} mesas en el plano, '
            '${registros.length} renglones en el registro de sorteos '
            '(el último del jefe: '
            '${MesaNuevaSola.ultimoDelJefe(registros)?.toLocal() ?? 'ninguno'}).');
        CuentaMesaNueva? cuenta;
        try {
          cuenta = MesaNuevaSola.calcular(
            plano: plano,
            alumnos: alumnos,
            pagos: pagos,
            registros: registros,
          );
        } on StateError catch (e) {
          b.writeln('  LA CUENTA NO CERRÓ (no guardaría nada): ${e.message}');
          b.writeln();
          continue;
        }
        if (cuenta == null) {
          b.writeln('  Nada: a nadie le toca una mesa sola.');
          b.writeln();
          continue;
        }
        final dadas = cuenta.dadas;
        for (final a in alumnos) {
          final suyas = dadas[a.id];
          if (suyas == null || suyas.isEmpty) continue;
          total++;
          final antes = cuenta.antes[a.id] ?? const <int>[];
          final nuevas = cuenta.nuevas.porAlumno[a.id] ?? const <int>[];
          b.writeln('  ${a.nombreAlumno}: tiene '
              '${antes.isEmpty ? 'ninguna' : antes.join(', ')} -> recibe '
              '${suyas.join(', ')} '
              '(${suyas.every(nuevas.contains) ? 'mesa nueva al fondo' : 'mesa que ya tenía fijada'}).');
          // Dónde cae cada mesa nueva: al lado de cuál, y si entra en el
          // hormigón.
          final salon = cuenta.nuevas.armado;
          for (final n in nuevas) {
            final m = salon.mesa(n)!;
            final vecinas = [
              for (final o in salon.mesasDeHoja(m.hoja))
                if (o.numero != n) o,
            ]..sort((x, y) => m.distanciaA(x).compareTo(m.distanciaA(y)));
            final borde = salon.hoja(m.hoja)?.contorno;
            final masAlFondo = salon
                .mesasDeHoja(m.hoja)
                .every((o) => o.y <= m.y + salon.radio);
            b.writeln('    la $n queda al lado de la '
                '${vecinas.isEmpty ? '?' : vecinas.first.numero} '
                '(a ${vecinas.isEmpty ? '?' : salon.aMetros(m.distanciaA(vecinas.first)).toStringAsFixed(2)} m), '
                '${masAlFondo ? 'en la última fila' : 'no en la última fila'}, '
                '${borde == null || borde.contieneCirculo(m.x, m.y, salon.radio) ? 'adentro del hormigón' : 'FUERA DEL HORMIGÓN'}.');
          }
        }
        if (cuenta.repetidos.isNotEmpty) {
          b.writeln('  Con un número repetido que se arregla: '
              '${cuenta.repetidos.length} familia(s).');
        }
        b.writeln();
      }
    } finally {
      await db.close();
    }
    b.writeln('Total: $total familia(s) recibirían una mesa sola.');
    print(b);
    if (_salida.isNotEmpty) {
      final carpeta = Directory(_salida)..createSync(recursive: true);
      File('${carpeta.path}/simulacro_mesa_nueva_sola.txt')
          .writeAsStringSync(b.toString());
    }
  });
}
