// Re-encola las notas operativas de contrato que quedaron solo en esta PC.
//
//   dart run tool/reencolar_notas_sin_subir.dart            (dry-run, no escribe)
//   dart run tool/reencolar_notas_sin_subir.dart --aplicar
//
// Qué pasó. Auditado el 2026-09-04: `notas_operativas_contrato` tenía 49 filas
// locales contra 31 en la nube, y la cola `_sync_queue` estaba VACÍA. O sea que
// esas 18 no estaban esperando para subir: no iban a subir nunca. La app no las
// reportaba como pendientes porque, para ella, no había nada pendiente.
//
// No son basura. Son notas de plata sobre cuentas de alumnos —"le quedó 300 a
// favor", "ARREGLA ESTA CUENTA, SACALE LOS INTERESES", "dijo que dejaba los 900
// de mora para cuando venga a pagar"— y 13 de las 18 están sin resolver. En la
// PC del jefe no se ven.
//
// Por qué una lista fija y no "todas las que falten". Re-subir las 49 sería más
// simple pero puede pisar en la nube una nota que el jefe editó después en su
// PC: el sync sube con upsert y ganaría la copia vieja de acá. Estos 18 ids son
// exactamente los que no existían en la nube al auditar. Para recalcularlos:
//
//   local:  SELECT id FROM notas_operativas_contrato;
//   nube:   SELECT id FROM notas_operativas_contrato;   (SQL Editor de Supabase)
//
// y la diferencia son los que van acá.

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Notas presentes en SQLite y ausentes en Supabase al 2026-09-04.
const _idsSinSubir = <String>[
  'eb1b8a12-8b19-49cb-8d15-4e35ab8aa5f5', // 2026-05-13 · A FAVOR $50
  '12c991d2-9067-48e3-bafe-c07807992741', // 2026-05-21 · vendrá o avisará hoy a la tarde
  'dafc1e36-0bc8-4b10-98e1-a3669933e309', // 2026-06-10 · quedaron 50 pesos para la próxima cuota
  '1d3a2371-b391-4361-87fe-21bdc6bd0c9a', // 2026-07-14 · queda 50 pesos a favor nuestro
  'bb0e7c72-239c-43f1-bc90-059c11b36927', // 2026-07-17 · $26.900 gracias al adelanto del 23/06
  '86a33596-e3f9-4439-ae86-538557768209', // 2026-08-03 · dejaba los 900 de mora para cuando venga
  '5b362d2b-7233-4658-9feb-b3e6628f7fbe', // 2026-08-10 · arreglo de cuenta
  '91aeac5c-cda4-4ba3-b131-5e2c237a73ee', // 2026-08-15 · REVISAR
  'ee5bae9c-c746-4652-9f24-97b297f647a6', // 2026-08-15 · INCLUYE REVISION
  '4b1911a4-00cf-4cd9-95f9-3443745797d2', // 2026-08-15 · REVISAR
  '84123846-95d3-4c2c-9aa3-d849cf73fe8d', // 2026-08-15 · REVISAR
  '27ca3881-caba-48fb-9204-25d951ede07a', // 2026-08-15 · REVISAR
  '456dfddb-f027-4fb9-ba84-aadb2668120e', // 2026-08-15 · REVISAR
  'cc98fc5c-7f54-44b4-8425-44fbd6d478a9', // 2026-08-15 · REVISAR
  '338d769a-8346-4bd9-9b3a-b6c3e9a6e70c', // 2026-08-21 · nuevo monto que queda en $408.800
  '63b1c31b-75ed-4fd3-868d-5e74acfd3624', // 2026-08-21 · ARREGLA ESTA CUENTA, SACALE LOS INTERESES
  '65c651a3-a632-4339-b68e-c609583eadad', // 2026-08-24 · le quedó 300 a favor
  'c35ed6fa-6c5e-41fb-ae09-38dcc981f36c', // 2026-08-26 · ya abonó la mora, expone la alumna
];

String _resolveDbPath() {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'Junior Eventos${Platform.pathSeparator}data.db';
}

void main(List<String> args) {
  final aplicar = args.contains('--aplicar');
  final dbPath = _resolveDbPath();

  if (!File(dbPath).existsSync()) {
    stderr.writeln('No encontré la base en $dbPath');
    exitCode = 1;
    return;
  }
  if (aplicar) {
    stdout.writeln('⚠️  Cerrá Junior Eventos antes de aplicar.\n');
  }

  final db = sqlite3.open(dbPath);
  try {
    final ahora = DateTime.now().toUtc().toIso8601String();
    var encoladas = 0;
    var yaEnCola = 0;
    var noEstan = 0;

    for (final id in _idsSinSubir) {
      final filas = db.select(
        'SELECT * FROM notas_operativas_contrato WHERE id = ?',
        [id],
      );
      if (filas.isEmpty) {
        stdout.writeln('  – $id · ya no está en esta base, se omite');
        noEstan++;
        continue;
      }

      final enCola = db.select(
        "SELECT id FROM _sync_queue WHERE tabla = 'notas_operativas_contrato' "
        'AND registro_id = ?',
        [id],
      );
      if (enCola.isNotEmpty) {
        stdout.writeln('  – $id · ya estaba encolada, se omite');
        yaEnCola++;
        continue;
      }

      final fila = Map<String, Object?>.from(filas.first);
      final texto = (fila['texto'] as String? ?? '').trim();
      stdout.writeln(
        '  ${aplicar ? "+" : "·"} $id · '
        '${texto.length > 50 ? "${texto.substring(0, 50)}…" : texto}',
      );

      if (aplicar) {
        db.execute(
          'INSERT INTO _sync_queue (tabla, operacion, registro_id, payload, '
          'created_at, intentos) VALUES (?, ?, ?, ?, ?, 0)',
          [
            'notas_operativas_contrato',
            'insert',
            id,
            jsonEncode(fila),
            ahora,
          ],
        );
        encoladas++;
      }
    }

    stdout.writeln('');
    if (aplicar) {
      stdout.writeln('✅ $encoladas nota(s) encoladas para subir.');
      stdout.writeln(
        '   Abrí la app y tocá el ícono de nube → "Subir y bajar".',
      );
    } else {
      final aEncolar = _idsSinSubir.length - yaEnCola - noEstan;
      stdout.writeln('Dry-run: $aEncolar nota(s) se encolarían.');
      stdout.writeln('Volvé a correrlo con --aplicar para hacerlo.');
    }
  } finally {
    db.dispose();
  }
}
