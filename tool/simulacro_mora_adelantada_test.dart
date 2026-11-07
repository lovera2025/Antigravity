// Simulacro del arreglo de la mora adelantada (6.3.2, 6-nov-2026) sobre una
// COPIA de la base del usuario. Ver docs/PLAN_MORA_ADELANTADA_2026-11-06.md.
//
// Para cada alumno que la revisión de la mora va a tocar al abrir la app,
// repasa su historial dos veces: con la regla de antes (copiada abajo, tal cual
// estaba en `MoraCuotaCalculator.postCobroTrackedOffset` en el commit 37c0215)
// y con la de ahora. Así se ve a quién le cambia la mora por este arreglo, y no
// los desvíos viejos de cada ficha.
//
//   Grupo A: la mora baja. Se le estaba pidiendo mora que ya había pagado por
//            adelantado (el caso de LOPEZ, MORENA AILEN).
//   Grupo B: la mora sube. Se le estaba descontando de una cuota mora que había
//            pagado sobre otra ya cerrada. Subirle la deuda a una familia lo
//            decide el jefe: esta lista se le muestra antes de instalar.
//   offset:  cambia el "ya usado", la ficha o la eximición, pero no la mora de
//            hoy. Informativo.
//
// Después corre la revisión de verdad (la que corre la app al abrir) sobre la
// misma copia y comprueba dos cosas: que deja a cada alumno exactamente como
// dice la regla nueva, y que ningún perdón cambió de eximición.
//
// Nunca abre la base real: trabaja sobre una copia de la copia, en una carpeta
// temporal. La nube apunta a ningún lado. Carga la mora congelada de la copia,
// como hace la app antes de revisar.
//
//   flutter test tool/simulacro_mora_adelantada_test.dart
//     --dart-define=copia=<data.db copiada con VACUUM INTO>
//     --dart-define=salida=<carpeta>
//
// Deja en <salida> simulacro_mora_adelantada.txt (el resumen y las listas) y
// simulacro_mora_adelantada.csv (una fila por alumno con algún cambio, con ";"
// para abrirlo en el Excel en español).
//
// Con --dart-define=detalle=cambios (o una lista de ids de contrato separados
// por coma) agrega, para esos alumnos, el repaso cobro por cobro con las dos
// reglas: qué mora había, qué se cobró, qué cuotas se cerraron y cómo quedaron
// la ficha y el "ya usado". Es para poder explicar cada cambio antes de instalar.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/eventos/repositories/mora_congelada_repository.dart';
import 'package:arguello_events/features/eventos/services/mora_congelada.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');
const _detalle = String.fromEnvironment('detalle');

bool _conDetalle(String id) =>
    _detalle == 'cambios' || _detalle.split(',').map((s) => s.trim()).contains(id);

String _cuotas(List<MoraCuotaDetalle> d) => d.isEmpty
    ? '—'
    : d.map((x) => 'C${x.numeroCuota} ${_p(x.interesBruto)}').join(', ');

/// La cuenta [base], anotando en [out] cada cobro que repasa.
CuentaPostCobro _conRastro(CuentaPostCobro base, StringBuffer out) {
  return ({
    required double moraPendienteTrackedActual,
    required double moraCobradaOffsetActual,
    required double moraEsteCobro,
    required int cuotasBaseLiquidadasEnCobro,
    required int cuotasBasePagadasPostCobro,
    required List<MoraCuotaDetalle> moraDesglosePreCobro,
    required List<MoraCuotaDetalle> moraDesgloseNetoPreCobro,
    required double moraDesgloseNetoTotal,
    required double saldoDeudorPost,
    required DateTime? fechaCobroAr,
    required DateTime? exencionActual,
    required bool reiniciaActual,
    double? moraCobradaHistorialPreCobro,
  }) {
    final r = base(
      moraPendienteTrackedActual: moraPendienteTrackedActual,
      moraCobradaOffsetActual: moraCobradaOffsetActual,
      moraEsteCobro: moraEsteCobro,
      cuotasBaseLiquidadasEnCobro: cuotasBaseLiquidadasEnCobro,
      cuotasBasePagadasPostCobro: cuotasBasePagadasPostCobro,
      moraDesglosePreCobro: moraDesglosePreCobro,
      moraDesgloseNetoPreCobro: moraDesgloseNetoPreCobro,
      moraDesgloseNetoTotal: moraDesgloseNetoTotal,
      saldoDeudorPost: saldoDeudorPost,
      fechaCobroAr: fechaCobroAr,
      exencionActual: exencionActual,
      reiniciaActual: reiniciaActual,
      moraCobradaHistorialPreCobro: moraCobradaHistorialPreCobro,
    );
    final f = fechaCobroAr;
    final dia = f == null
        ? '??/??'
        : '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}';
    final pre = cuotasBasePagadasPostCobro - cuotasBaseLiquidadasEnCobro;
    out
      ..writeln('      $dia · cuotas pagas $pre -> $cuotasBasePagadasPostCobro'
          ' · mora cobrada ${_p(moraEsteCobro)}'
          ' · cobrada antes ${_p(moraCobradaHistorialPreCobro ?? 0)}')
      ..writeln('            mora del calendario (bruta): ${_cuotas(moraDesglosePreCobro)}')
      ..writeln('            menos lo ya pagado (neta):   ${_cuotas(moraDesgloseNetoPreCobro)}')
      ..writeln('            ficha ${_p(moraPendienteTrackedActual)} -> ${_p(r.tracked)}'
          ' · ya usado ${_p(moraCobradaOffsetActual)} -> ${_p(r.offset)}'
          ' · eximición ${_eximicion(exencionActual, reiniciaActual)}'
          ' -> ${_eximicion(r.exentaHasta, r.reinicia)}');
    return r;
  };
}

/// La regla de antes del arreglo, copiada tal cual de
/// `MoraCuotaCalculator.postCobroTrackedOffset` (commit 37c0215). Lo único que
/// cambia respecto de la de hoy es la rama de las cuotas liquidadas: acá el
/// offset se queda con toda la mora cobrada.
EstadoMoraPostCobro _postCobroViejo({
  required double moraPendienteTrackedActual,
  required double moraCobradaOffsetActual,
  required double moraEsteCobro,
  required int cuotasBaseLiquidadasEnCobro,
  required int cuotasBasePagadasPostCobro,
  required List<MoraCuotaDetalle> moraDesglosePreCobro,
  required List<MoraCuotaDetalle> moraDesgloseNetoPreCobro,
  required double moraDesgloseNetoTotal,
  required double saldoDeudorPost,
  required DateTime? fechaCobroAr,
  required DateTime? exencionActual,
  required bool reiniciaActual,
  double? moraCobradaHistorialPreCobro,
}) {
  final remanente = moraPendienteTrackedActual.clamp(0.0, double.infinity);
  var tracked = remanente;
  var offset = moraCobradaOffsetActual;

  if (cuotasBaseLiquidadasEnCobro > 0) {
    final cuotasPreCobro =
        cuotasBasePagadasPostCobro - cuotasBaseLiquidadasEnCobro;
    final moraLiquidadasNeto = moraDesgloseNetoPreCobro
        .where(
          (d) =>
              d.numeroCuota > cuotasPreCobro &&
              d.numeroCuota <= cuotasBasePagadasPostCobro,
        )
        .fold<double>(0, (s, d) => s + d.interesBruto);
    final remanenteCarry = cuotasPreCobro > 0 ? remanente : 0.0;
    tracked = (remanenteCarry + moraLiquidadasNeto - moraEsteCobro)
        .clamp(0.0, double.infinity);
    if (moraEsteCobro > 0.01) {
      offset = moraCobradaOffsetActual + moraEsteCobro;
    }
  } else if (moraEsteCobro > 0.01) {
    final moraHaciaTracked = math.min(moraEsteCobro, remanente);
    final moraHaciaDesglose = moraEsteCobro - moraHaciaTracked;
    tracked = (remanente - moraHaciaTracked).clamp(0.0, double.infinity);
    if (moraHaciaDesglose > 0.01 &&
        moraHaciaDesglose >= moraDesgloseNetoTotal - 0.01) {
      offset = offset + moraHaciaDesglose;
    }
    if (moraHaciaTracked > 0.01) {
      offset = offset + moraHaciaTracked;
    }
  }

  var exentaHasta = exencionActual;
  var reinicia = reiniciaActual;
  if (moraEsteCobro > 0.01 && fechaCobroAr != null && saldoDeudorPost > 0.01) {
    final moraPendientePreCobro = moraDesgloseNetoTotal + remanente;
    if (moraEsteCobro >= moraPendientePreCobro - 0.01) {
      exentaHasta = MoraCuotaCalculator.calcularFechaExencion(fechaCobroAr);
      reinicia = cuotasBaseLiquidadasEnCobro > 0;
      final historialPre = moraCobradaHistorialPreCobro;
      if (historialPre != null) {
        final todoCobrado = historialPre + moraEsteCobro;
        if (todoCobrado > offset + 0.01) offset = todoCobrado;
      }
    }
  }

  return EstadoMoraPostCobro(
    tracked: double.parse(tracked.toStringAsFixed(2)),
    offset: double.parse(offset.toStringAsFixed(2)),
    exentaHasta: exentaHasta,
    reinicia: reinicia,
  );
}

/// Cómo queda un alumno después de la revisión, con una regla.
class _Resultado {
  final double tracked;
  final double offset;
  final DateTime? exenta;
  final bool reinicia;
  final double mora;
  _Resultado(this.tracked, this.offset, this.exenta, this.reinicia, this.mora);

  String get eximicion => _eximicion(exenta, reinicia);
}

String _eximicion(DateTime? d, bool reinicia) => d == null
    ? 'sin'
    : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}'
        '${reinicia ? '' : ' permanente'}';

/// Lo mismo que hace `MoraTrackedRecovery.reconciliarTodos` con un alumno,
/// pero con la regla que se le pase, y sin escribir nada.
_Resultado _revisar(
  ContratoAlumno c,
  List<Map<String, dynamic>> pagos,
  CuentaPostCobro cuenta,
  DateTime hoy,
) {
  final objetivo = MoraTrackedRecovery.objetivoDesdeHistorial(
    contrato: c,
    pagos: pagos,
    cuenta: cuenta,
  );
  final tracked = MoraTrackedRecovery.trackedEfectivo(
    objetivo: objetivo.tracked,
    ajuste: c.moraTrackedAjuste,
  );
  var hasta = c.moraExentaHasta;
  var reinicia = c.moraExencionReinicia;
  final r = MoraTrackedRecovery.resolverExencion(
    contrato: c,
    pagos: pagos,
    cuenta: cuenta,
  );
  if (r.escribir) {
    hasta = r.hasta;
    reinicia = r.reinicia;
  }
  final despues = c.copyWith(
    moraPendienteTracked: tracked,
    moraCobradaOffset: objetivo.offset,
    moraExentaHasta: hasta,
    moraExencionReinicia: reinicia,
  );
  final mora = MoraCuotaCalculator.moraPendienteOperativa(
    contrato: despues,
    moraCobradaHistorial: MoraTrackedRecovery.moraCobradaDelHistorial(pagos),
    ahoraAr: hoy,
  );
  return _Resultado(tracked, objetivo.offset, hasta, reinicia, mora);
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

String _csv(String s) =>
    s.contains(';') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('simulacro de la mora adelantada sobre la copia', () async {
    expect(_copia, isNotEmpty, reason: 'Falta --dart-define=copia=...');
    final real = '${Platform.environment['USERPROFILE']}\\Documents\\'
        'Junior Eventos\\data.db';
    expect(File(_copia).absolute.path.toLowerCase(),
        isNot(File(real).absolute.path.toLowerCase()),
        reason: 'Nunca sobre la base real: solo sobre una copia.');

    final docs = Directory.systemTemp.createTempSync('simulacro_adelantada');
    final carpeta =
        Directory('${docs.path}${Platform.pathSeparator}Junior Eventos')
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
      // Como la app antes de revisar: sin esto, los congelados darían otra mora.
      await MoraCongeladaRepository.cargarRegistroEn(db);

      final filas = await db.rawQuery('''
        SELECT a.*, coalesce(cl.nombre_completo, '?') AS institucion
        FROM contratos_alumnos a
        LEFT JOIN eventos e ON e.id = a.evento_id
        LEFT JOIN clientes cl ON cl.id = e.cliente_id''');

      final csv = StringBuffer()
        ..writeln([
          'institucion',
          'alumno',
          'contrato_id',
          'cuotas_pagadas',
          'saldo',
          'mora_que_muestra_hoy',
          'offset_viejo',
          'offset_nuevo',
          'ficha_vieja',
          'ficha_nueva',
          'eximicion_vieja',
          'eximicion_nueva',
          'mora_hoy_regla_vieja',
          'mora_hoy_regla_nueva',
          'diferencia',
          'grupo',
          'congelada',
          'ajuste_ficha',
        ].join(';'));

      final grupoA = <String>[], grupoB = <String>[], soloOffset = <String>[];
      var sumaA = 0.0, sumaB = 0.0;
      final rotos = <String>[];
      final rastros = StringBuffer();
      final nuevos = <String, _Resultado>{};
      final perdonesAntes = <String, String>{};
      var revisados = 0;

      final ordenadas = [...filas]..sort((a, b) {
          final i = (a['institucion'] as String)
              .compareTo(b['institucion'] as String);
          return i != 0
              ? i
              : (a['nombre_alumno'] as String? ?? '')
                  .compareTo(b['nombre_alumno'] as String? ?? '');
        });

      for (final r in ordenadas) {
        final c = ContratoAlumno.fromJson(Map<String, dynamic>.from(r));
        if (c.moraTrackedAjuste.abs() > 0.01) {
          perdonesAntes[c.id] = _eximicion(c.moraExentaHasta, c.moraExencionReinicia);
        }
        // Los mismos que toca la revisión de la app.
        if (c.saldoDeudor <= 0.01) continue;
        final pagos = (await db.query(
          'pagos_contrato_alumno',
          where: 'contrato_alumno_id = ?',
          whereArgs: [c.id],
        ))
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
        if (!MoraTrackedRecovery.necesitaReconciliar(c, pagos)) continue;
        revisados++;

        final viejo = _revisar(c, pagos, _postCobroViejo, hoy);
        final nuevo = _revisar(
            c, pagos, MoraCuotaCalculator.postCobroTrackedOffset, hoy);
        nuevos[c.id] = nuevo;

        final cambiaMora = (nuevo.mora - viejo.mora).abs() > 0.01;
        final cambiaAlgo = cambiaMora ||
            (nuevo.offset - viejo.offset).abs() > 0.01 ||
            (nuevo.tracked - viejo.tracked).abs() > 0.01 ||
            nuevo.eximicion != viejo.eximicion;
        if (!cambiaAlgo) continue;

        // Sin ninguna línea de mora en su historia las dos reglas tienen que
        // dar lo mismo: si no, la copia de la regla vieja está mal.
        if (!MoraTrackedRecovery.tieneMoraEnHistorial(pagos)) {
          rotos.add(c.nombreAlumno);
        }

        final muestraHoy = MoraCuotaCalculator.moraPendienteOperativa(
          contrato: c,
          moraCobradaHistorial: MoraTrackedRecovery.moraCobradaDelHistorial(pagos),
          ahoraAr: hoy,
        );
        final dif = nuevo.mora - viejo.mora;
        final grupo = !cambiaMora ? 'offset' : (dif < 0 ? 'A' : 'B');
        final institucion = r['institucion'] as String;
        if (_conDetalle(c.id)) {
          rastros.writeln('  ${c.nombreAlumno} ($institucion) · grupo $grupo · '
              'mora de hoy ${_p(viejo.mora)} -> ${_p(nuevo.mora)}');
          for (final (nombre, cuenta) in <(String, CuentaPostCobro)>[
            ('regla de antes', _postCobroViejo),
            ('regla nueva', MoraCuotaCalculator.postCobroTrackedOffset),
          ]) {
            rastros.writeln('    $nombre:');
            MoraTrackedRecovery.objetivoDesdeHistorial(
              contrato: c,
              pagos: pagos,
              cuenta: _conRastro(cuenta, rastros),
            );
          }
          rastros.writeln();
        }
        final renglon = '${institucion.padRight(24)} ${c.nombreAlumno.padRight(34)} '
            'mora ${_p(viejo.mora).padLeft(9)} -> ${_p(nuevo.mora).padLeft(9)} '
            '(${dif > 0 ? '+' : ''}${_p(dif)}) | '
            'ya usado ${_p(viejo.offset)} -> ${_p(nuevo.offset)} | '
            'ficha ${_p(viejo.tracked)} -> ${_p(nuevo.tracked)} | '
            'eximición ${viejo.eximicion} -> ${nuevo.eximicion}';
        switch (grupo) {
          case 'A':
            grupoA.add(renglon);
            sumaA += dif;
          case 'B':
            grupoB.add(renglon);
            sumaB += dif;
          default:
            soloOffset.add(renglon);
        }
        csv.writeln([
          _csv(institucion),
          _csv(c.nombreAlumno),
          c.id,
          c.cuotasPagadas,
          c.saldoDeudor.toStringAsFixed(0),
          muestraHoy.toStringAsFixed(0),
          viejo.offset.toStringAsFixed(0),
          nuevo.offset.toStringAsFixed(0),
          viejo.tracked.toStringAsFixed(0),
          nuevo.tracked.toStringAsFixed(0),
          viejo.eximicion,
          nuevo.eximicion,
          viejo.mora.toStringAsFixed(0),
          nuevo.mora.toStringAsFixed(0),
          dif.toStringAsFixed(0),
          grupo,
          MoraCongelada.de(c.id).algoCongelado ? 'sí' : 'no',
          c.moraTrackedAjuste.toStringAsFixed(0),
        ].join(';'));
      }

      // La revisión de verdad, la que corre la app al abrir, sobre la copia.
      final reloj = Stopwatch()..start();
      final corregidos = await MoraTrackedRecovery.reconciliarTodos(
        db: db,
        encolarSync: true,
        ahoraAr: hoy,
      );
      final eximiciones = await MoraTrackedRecovery.repararExencionDesdeHistorial(
        db: db,
        encolarSync: true,
      );
      reloj.stop();

      // Que deje a cada uno como dice la regla nueva.
      final distintos = <String>[];
      final perdonesTocados = <String>[];
      for (final r in await db.query('contratos_alumnos')) {
        final c = ContratoAlumno.fromJson(Map<String, dynamic>.from(r));
        final esperado = nuevos[c.id];
        if (esperado != null &&
            ((c.moraCobradaOffset - esperado.offset).abs() > 0.01 ||
                (c.moraPendienteTracked - esperado.tracked).abs() > 0.01)) {
          distintos.add('${c.nombreAlumno}: ya usado ${_p(c.moraCobradaOffset)} '
              '(esperado ${_p(esperado.offset)}), ficha ${_p(c.moraPendienteTracked)} '
              '(esperado ${_p(esperado.tracked)})');
        }
        final antes = perdonesAntes[c.id];
        if (antes != null &&
            antes != _eximicion(c.moraExentaHasta, c.moraExencionReinicia)) {
          perdonesTocados.add(c.nombreAlumno);
        }
      }

      final b = StringBuffer()
        ..writeln('SIMULACRO DE LA MORA ADELANTADA (6.3.2) — '
            '${hoy.day}/${hoy.month}/${hoy.year}, sobre una copia de la base')
        ..writeln()
        ..writeln('Alumnos en la base: ${filas.length}')
        ..writeln('Los que revisa la app al abrir (con saldo y con mora o cuotas '
            'en su historia): $revisados')
        ..writeln('Con mora congelada: '
            '${filas.where((r) => MoraCongelada.de(r['id'] as String).algoCongelado).length}')
        ..writeln()
        ..writeln('Grupo A, la mora BAJA (se le pedía mora ya pagada): '
            '${grupoA.length} alumnos, ${_p(sumaA)} en total')
        ..writeln('Grupo B, la mora SUBE (se le descontaba de más): '
            '${grupoB.length} alumnos, +${_p(sumaB)} en total')
        ..writeln('Cambia el "ya usado", la ficha o la eximición, pero no la mora '
            'de hoy: ${soloOffset.length}')
        ..writeln()
        ..writeln('La revisión de verdad sobre la copia: $corregidos corregidos '
            '(más $eximiciones con la eximición reparada), en '
            '${reloj.elapsedMilliseconds} ms')
        ..writeln('Que no quedaron como dice la regla nueva: '
            '${distintos.isEmpty ? 'ninguno' : distintos.length}')
        ..writeln('Perdones (con ajuste de ficha) con la eximición cambiada: '
            '${perdonesTocados.isEmpty ? 'ninguno' : perdonesTocados.join(', ')}')
        ..writeln('Sin mora en su historia y con un cambio (la copia de la regla '
            'vieja estaría mal): ${rotos.isEmpty ? 'ninguno' : rotos.join(', ')}')
        ..writeln()
        ..writeln('GRUPO B — LA MORA SUBE (decide el jefe antes de instalar)')
        ..writeAll(grupoB.map((r) => '  $r\n'))
        ..writeln()
        ..writeln('GRUPO A — LA MORA BAJA')
        ..writeAll(grupoA.map((r) => '  $r\n'))
        ..writeln()
        ..writeln('SOLO CAMBIA EL "YA USADO", LA FICHA O LA EXIMICIÓN')
        ..writeAll(soloOffset.map((r) => '  $r\n'))
        ..writeln()
        ..writeln('NO QUEDARON COMO DICE LA REGLA NUEVA')
        ..writeAll(distintos.map((r) => '  $r\n'));
      if (rastros.isNotEmpty) {
        b
          ..writeln()
          ..writeln('COBRO POR COBRO, CON LAS DOS REGLAS')
          ..write(rastros);
      }
      print(b.toString());
      if (_salida.isNotEmpty) {
        Directory(_salida).createSync(recursive: true);
        File('$_salida${Platform.pathSeparator}simulacro_mora_adelantada.txt')
            .writeAsStringSync(b.toString());
        // Con BOM: el Excel en español lo abre con los acentos bien.
        File('$_salida${Platform.pathSeparator}simulacro_mora_adelantada.csv')
            .writeAsStringSync('﻿$csv');
      }

      expect(rotos, isEmpty,
          reason: 'Sin mora en la historia las dos reglas dan lo mismo.');
      expect(distintos, isEmpty,
          reason: 'La revisión de la app tiene que dejar lo de la regla nueva.');
      expect(perdonesTocados, isEmpty, reason: 'Un perdón no se toca.');
    } finally {
      MoraCongelada.vaciar();
      await LocalDatabase.close();
      try {
        docs.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
