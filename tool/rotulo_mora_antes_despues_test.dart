// El rótulo de la mora y el recibo reimpreso, antes y después de la 6.8.1
// (`docs/SPEC_remanente_mora_por_concepto_2026-11-14.md`, sección 7.2, con su
// Anexo D y el recibo reimpreso entero), sobre una COPIA de la base.
//
// Es el MISMO archivo para las dos versiones: se corre en una carpeta con la
// 6.8.0 y en la de la 6.8.1, sobre la misma copia, y cada corrida deja lo que
// da en un JSON. `tool/comparar_rotulo_mora.py` los cruza y arma el informe.
// Por eso usa solo lo que ya existía en la 6.8.0.
//
// NUNCA abre la base real: trabaja sobre una copia de la copia, en una carpeta
// temporal. La nube no se toca (no se abre Supabase). Carga la mora congelada,
// como la app.
//
//   flutter test tool/rotulo_mora_antes_despues_test.dart
//     --dart-define=copia=<data.db copiada con VACUUM INTO>
//     --dart-define=salida=<carpeta fuera del repositorio>
//     --dart-define=version=6.8.0   (o 6.8.1)
//
// Deja <salida>/rotulo_mora_<version>.json, con nombres: no va a git.
//
// Por contrato:
//   - la ficha: de qué cuotas dice que es el remanente (`inferir`, lo que
//     queda), con su suma y lo que no se explica;
//   - cada fila de mora del Estado de cuenta: su título (`concepto_ficha`);
//   - cada cobro reimpreso entero (las líneas y el recuadro verde) y cada
//     renglón reimpreso solo, como lo mandaba REIMPRIMIR hasta la 6.8.0.

// ignore_for_file: avoid_print

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/cierre_caja/services/cobro_agrupado.dart';
import 'package:arguello_events/features/eventos/repositories/mora_congelada_repository.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';
import 'package:arguello_events/features/eventos/services/concepto_pago_display.dart';
import 'package:arguello_events/features/eventos/services/mora_congelada.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');
const _version = String.fromEnvironment('version', defaultValue: 'sin-version');

Object? _j(Object? v) {
  if (v == null || v is bool || v is String || v is int) return v;
  if (v is double) {
    final r = double.parse(v.toStringAsFixed(2));
    return r == 0 ? 0.0 : r;
  }
  if (v is num) return v;
  if (v is DateTime) return v.toIso8601String();
  if (v is Map) {
    final m = SplayTreeMap<String, Object?>();
    for (final e in v.entries) {
      m[e.key.toString()] = _j(e.value);
    }
    return m;
  }
  if (v is Iterable) return v.map(_j).toList();
  return v.toString();
}

bool _anulado(Map<String, dynamic> p) =>
    ((p['anulado'] as num?)?.toInt() ?? 0) != 0;

/// Los cobros de un contrato: las filas vivas, encadenadas con
/// `esDelMismoCobro` (lo mismo que "anular todo el cobro").
List<List<Map<String, dynamic>>> _cobros(List<Map<String, dynamic>> pagos) {
  final vivas = pagos.where((p) => !_anulado(p)).toList()
    ..sort((a, b) => (a['fecha_pago']?.toString() ?? '')
        .compareTo(b['fecha_pago']?.toString() ?? ''));
  final out = <List<Map<String, dynamic>>>[];
  final usadas = <int>{};
  for (var i = 0; i < vivas.length; i++) {
    if (usadas.contains(i)) continue;
    final grupo = [vivas[i]];
    usadas.add(i);
    var agrego = true;
    while (agrego) {
      agrego = false;
      for (var j = 0; j < vivas.length; j++) {
        if (usadas.contains(j)) continue;
        if (grupo.any((g) => esDelMismoCobro(g, vivas[j]))) {
          grupo.add(vivas[j]);
          usadas.add(j);
          agrego = true;
        }
      }
    }
    out.add(grupo);
  }
  return out;
}

Map<String, Object?> _linea(Map<String, dynamic> l) => {
      'concepto': l['concepto'],
      'monto': (l['monto'] as num?)?.toDouble() ?? 0,
      'mora': l['esMora'] == true,
      'cuota': l['numeroCuota'],
      'previa': l['cuotaPrevia'],
      'previas': l['cuotasPrevias'],
      'pleno': l['montoPleno'],
    };

Map<String, Object?> _fila(FilaMoraPdf f) => {
      'rotulo': f.rotulo,
      'monto': f.monto,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el rótulo de la mora y el recibo reimpreso sobre la copia', () async {
    expect(_copia, isNotEmpty, reason: 'Falta --dart-define=copia=...');
    expect(_salida, isNotEmpty, reason: 'Falta --dart-define=salida=...');
    final real = '${Platform.environment['USERPROFILE']}\\Documents\\'
        'Junior Eventos\\data.db';
    expect(File(_copia).absolute.path.toLowerCase(),
        isNot(File(real).absolute.path.toLowerCase()),
        reason: 'Nunca sobre la base real: solo sobre una copia.');

    final docs = Directory.systemTemp.createTempSync('rotulo_mora');
    final carpeta =
        Directory('${docs.path}${Platform.pathSeparator}Junior Eventos')
          ..createSync(recursive: true);
    File(_copia).copySync('${carpeta.path}${Platform.pathSeparator}data.db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );

    try {
      final db = await LocalDatabase.instance;
      await MoraCongeladaRepository.cargarRegistroEn(db);

      final filas = await db.rawQuery('''
        SELECT a.*, coalesce(cl.nombre_completo, '?') AS institucion
        FROM contratos_alumnos a
        LEFT JOIN eventos e ON e.id = a.evento_id
        LEFT JOIN clientes cl ON cl.id = e.cliente_id''');
      final todosPagos = await db.query('pagos_contrato_alumno');
      final porContrato = <String, List<Map<String, dynamic>>>{};
      for (final p in todosPagos) {
        final id = p['contrato_alumno_id'] as String?;
        if (id == null) continue;
        porContrato.putIfAbsent(id, () => []).add(Map<String, dynamic>.from(p));
      }

      final contratos = <Map<String, Object?>>[];
      var conPagos = 0;
      for (final r in filas) {
        final c = ContratoAlumno.fromJson(Map<String, dynamic>.from(r));
        final pagos = porContrato[c.id] ?? const <Map<String, dynamic>>[];
        if (pagos.isEmpty) continue;
        conPagos++;

        // La ficha.
        Object? ficha;
        if (c.moraPendienteTracked > 0.01) {
          final det = MoraTrackedOrigen.inferir(
            contratoBase: c,
            pagos: pagos,
            trackedMonto: c.moraPendienteTracked,
            recorte: MoraOrigenRecorte.loQueQueda,
          );
          ficha = {
            'tracked': c.moraPendienteTracked,
            'suma': det.fold<double>(0, (s, d) => s + d.montoAtribuido),
            'sin_explicar': MoraTrackedOrigen.sinExplicar(
              tracked: c.moraPendienteTracked,
              origen: det,
            ),
            'cuotas': [
              for (final d in det)
                {
                  'cuota': d.numeroCuota,
                  'mes': d.mesLabel,
                  'monto': d.montoAtribuido,
                  'dias': d.diasMora,
                  'debida': d.moraDebida,
                  'cobrada': d.moraCobrada,
                },
            ],
          };
        }

        // Las filas de mora del Estado de cuenta.
        final estado = <Map<String, Object?>>[];
        for (final p in ConceptoPagoDisplay.enriquecerPagosHistorial(c, pagos)) {
          if (p['concepto_ficha'] == null) continue;
          estado.add({
            'id': p['id'],
            'fecha': p['fecha_pago'],
            'concepto': p['concepto'],
            'monto': (p['monto'] as num?)?.toDouble() ?? 0,
            'titulo': p['concepto_ficha'],
          });
        }

        // Cada cobro, reimpreso entero; y cada renglón solo (REIMPRIMIR hasta
        // la 6.8.0).
        final cobros = <Map<String, Object?>>[];
        for (final cobro in _cobros(pagos)) {
          final lineas = ConceptoPagoDisplay.conceptosPdfDesdePagosLote(
            c,
            cobro,
            historialCompleto: pagos,
          );
          final renglones = <Map<String, Object?>>[];
          for (final p in cobro) {
            final esMora = ConceptoPagoDisplay.esMora(p);
            final solo = [
              {
                'concepto': p['concepto'],
                'monto': (p['monto'] as num?)?.toDouble() ?? 0,
                'esMora': esMora,
                'esCargoCanal': ConceptoPagoDisplay.esCargoCanal(p),
              },
            ];
            renglones.add({
              'id': p['id'],
              'mora': esMora,
              'verde': filasMoraCobradaPdf(solo).map(_fila).toList(),
            });
          }
          cobros.add({
            'ids': cobro.map((p) => p['id']).toList(),
            'fecha': cobro.first['fecha_pago'],
            'suma_filas': cobro.fold<double>(
              0,
              (s, p) => s + ((p['monto'] as num?)?.toDouble() ?? 0),
            ),
            'suma_lineas': lineas.fold<double>(
              0,
              (s, l) => s + ((l['monto'] as num?)?.toDouble() ?? 0),
            ),
            'lineas': lineas.map(_linea).toList(),
            'verde': filasMoraCobradaPdf(lineas).map(_fila).toList(),
            'renglones': renglones,
          });
        }

        contratos.add({
          'id': c.id,
          'alumno': c.nombreAlumno,
          'institucion': r['institucion'],
          'saldo': c.saldoDeudor,
          'ajuste': c.moraTrackedAjuste,
          'congelada': MoraCongelada.de(c.id).algoCongelado,
          'ficha': ficha,
          'estado': estado,
          'cobros': cobros,
        });
      }

      final out = File(
        '$_salida${Platform.pathSeparator}rotulo_mora_$_version.json',
      )..createSync(recursive: true);
      out.writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert(_j({
          'version': _version,
          'contratos_con_pagos': conPagos,
          'contratos': contratos,
        })),
      );
      print('rotulo_mora $_version: $conPagos contratos con pagos → ${out.path}');
    } finally {
      MoraCongelada.vaciar();
      await LocalDatabase.close();
      try {
        docs.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
