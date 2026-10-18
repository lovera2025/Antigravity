// La revisión automática de la mora (MoraTrackedRecovery.reconciliarTodos).
//
// El 15-oct-2026, comparando la PC del usuario con la nube, aparecieron 21
// alumnos a los que la mora ya pagada se les descontaba otra vez de la de los
// meses siguientes: cobraba de menos. VERON, DALMA pagó en agosto la mora de
// julio ($31.900) y la PC le mostraba $1.100 en vez de $33.000 por agosto y
// septiembre. Tres causas, una por grupo de tests:
//
//   1. La revisión corregía el "ya usado" (offset) en la PC pero no lo subía:
//      solo subía la ficha. Con las columnas recién llegadas a la nube (28-ago),
//      la nube quedó en 0 y la bajada lo volvía a pisar.
//   2. Mora pagada en dos veces: una parte un día (sin completar cuota) y el
//      resto otro día con la cuota. El offset sumaba solo lo del segundo día, y
//      lo del primero se volvía a descontar (MOLINA, CARLOS LAUTARO).
//   3. Anular un cobro dejaba la eximición que ese cobro había dado
//      (MONTENEGRO, FRANCISCO NAHUEL).
//
// Y una que apareció con los datos de esa noche: la revisión le borraba la
// ficha a quien ya había terminado de pagar (ALTAMIRANO, CELESTE ABIGAIL).
//
// Los datos son los de esos alumnos, con nombres de prueba. Corre contra una
// base SQLite temporal: nunca toca la de producción.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';
import 'package:arguello_events/features/eventos/services/revision_mora_constancia.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

String uid(String nombre) {
  final base = nombre.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final r = base.padRight(32, '0').substring(0, 32);
  return '${r.substring(0, 8)}-${r.substring(8, 12)}-${r.substring(12, 16)}'
      '-${r.substring(16, 20)}-${r.substring(20, 32)}';
}

/// El 15/10/2026 al mediodía (hora de Argentina): el día del hallazgo.
final _hoy = DateTime(2026, 10, 15, 12);

Map<String, Object?> _pago(
  String alumno,
  int n,
  String fecha,
  String concepto,
  double monto, {
  bool anulado = false,
}) => {
  // El número adelante: [uid] recorta a 32 letras, y "pago 1" y "pago 10"
  // al final del nombre salían iguales.
  'id': uid('${n.toString().padLeft(3, '0')} pago $alumno'),
  'contrato_alumno_id': uid(alumno),
  'fecha_pago': fecha,
  'created_at': fecha,
  'updated_at': fecha,
  'concepto': concepto,
  'monto': monto,
  'monto_gross': concepto.startsWith('Cargo canal') ? 0 : monto,
  'medio_pago': 'Efectivo',
  'anulado': anulado ? 1 : 0,
};

/// VERON, DALMA: 3 cuotas de $55.000 pagadas, la 4 en parte, y el 24/08 la
/// mora de julio. Eximida al 31/08, permanente; el "ya usado" quedó en 0.
Future<void> _sembrarVeron(String alumno, {double ajuste = 0}) async {
  final db = await LocalDatabase.instance;
  await db.insert('contratos_alumnos', {
    'id': uid(alumno),
    'evento_id': uid('evento'),
    'nombre_alumno': alumno,
    'monto_total_pactado': 565000,
    'saldo_deudor': 376900,
    'cuotas_pagadas': 3,
    'total_cuotas': 9,
    'dia_vencimiento_mensual': 10,
    'mesa_extra_precio': 70000,
    'mesa_extra_cuotas': 7,
    'mesa_extra_cantidad': 1,
    'created_at': '2026-03-30T19:49:48.809216+00:00',
    'mora_pendiente_tracked': 0,
    'mora_cobrada_offset': 0,
    'mora_exenta_hasta': '2026-08-31',
    'mora_exencion_reinicia': 0,
    'mora_tracked_ajuste': ajuste,
  });
  for (final p in [
    _pago(alumno, 1, '2026-04-27T19:35:38.216249+00:00', 'Cuota Base (1/9)', 55000),
    _pago(alumno, 2, '2026-05-26T16:55:02.124250+00:00', 'Cuota Base (2/9)', 55000),
    _pago(alumno, 3, '2026-08-03T12:46:12.998786+00:00', 'Cuota Base (3/9)', 55000),
    _pago(alumno, 4, '2026-08-24T17:37:29.526592+00:00',
        'Entrega parcial — Cuota Base (4/9)', 23100),
    _pago(alumno, 5, '2026-08-24T17:37:29.533550+00:00',
        'Interés mora cuota 4 (vto Jul 2026) + mora pendiente cuota 3', 31900),
  ]) {
    await db.insert('pagos_contrato_alumno', p);
  }
}

/// MOLINA, CARLOS LAUTARO: mora pagada en dos veces. $29.400 el 22/09 sin
/// completar la cuota 3, y $52.850 el 13/10 con la cuota. El "ya usado" quedó
/// en $71.400 ($18.550 de junio + $52.850): le faltan los $29.400 del 22/09.
Future<void> _sembrarMolina(String alumno) async {
  final db = await LocalDatabase.instance;
  await db.insert('contratos_alumnos', {
    'id': uid(alumno),
    'evento_id': uid('evento'),
    'nombre_alumno': alumno,
    'monto_total_pactado': 315000,
    'saldo_deudor': 187250,
    'cuotas_pagadas': 3,
    'total_cuotas': 9,
    'dia_vencimiento_mensual': 10,
    'created_at': '2026-03-30T03:00:00+00:00',
    'mora_pendiente_tracked': 0,
    'mora_cobrada_offset': 71400,
    'mora_exenta_hasta': '2026-10-31',
    'mora_exencion_reinicia': 1,
    'mora_tracked_ajuste': 0,
  });
  for (final p in [
    _pago(alumno, 1, '2026-06-11T13:09:38.568218+00:00', '2 Cuotas (Cuota Base)', 70000),
    _pago(alumno, 2, '2026-06-11T13:09:38.595623+00:00',
        'Interés mora cuotas 1, 2 (Abr, May)', 18550),
    _pago(alumno, 3, '2026-09-22T12:31:25.354095+00:00',
        'Entrega parcial — Cuota Base (3/9)', 10600),
    _pago(alumno, 4, '2026-09-22T12:31:25.361089+00:00',
        'Interés mora cuota 3 (vto Jun 2026)', 29400),
    _pago(alumno, 5, '2026-10-13T13:39:00.147433+00:00',
        'Cuota Base (3/9) — Completada', 24400),
    _pago(alumno, 6, '2026-10-13T13:39:00.154427+00:00',
        'Entrega parcial — Cuota Base (4/9)', 22750),
    _pago(alumno, 7, '2026-10-13T13:39:00.157427+00:00',
        'Interés mora cuotas 3, 4, 5, 6 (vto Jun, Jul, Ago, Sep)', 52850),
  ]) {
    await db.insert('pagos_contrato_alumno', p);
  }
}

/// MONTENEGRO, FRANCISCO NAHUEL: el cobro del 19/09 con la mora ($39.300) se
/// anuló (dos veces cargado, las dos anuladas), pero la eximición al 30/09 que
/// ese cobro había dado quedó.
Future<void> _sembrarMontenegro(String alumno, {double ajuste = 0}) async {
  final db = await LocalDatabase.instance;
  await db.insert('contratos_alumnos', {
    'id': uid(alumno),
    'evento_id': uid('evento'),
    'nombre_alumno': alumno,
    'monto_total_pactado': 340000,
    'saldo_deudor': 180235,
    'cuotas_pagadas': 5,
    'total_cuotas': 9,
    'dia_vencimiento_mensual': 10,
    'mesa_extra_precio': 70000,
    'mesa_extra_cuotas': 5,
    'mesa_extra_pagado': 9765,
    'mesa_extra_cantidad': 1,
    'created_at': '2026-03-30T03:00:00+00:00',
    'mora_pendiente_tracked': 39300,
    'mora_cobrada_offset': 39300,
    'mora_exenta_hasta': '2026-09-30',
    'mora_exencion_reinicia': 1,
    'mora_tracked_ajuste': ajuste,
  });
  const f1 = '2026-09-19T13:36:00+00:00';
  const f2 = '2026-09-19T13:36:52+00:00';
  const moraTexto = 'Interés mora cuotas 4, 5 + mora pendiente cuotas 2 y 3';
  for (final p in [
    _pago(alumno, 1, '2026-04-29T22:36:57.681614+00:00', 'Cuota Base (1/9)', 30000),
    _pago(alumno, 2, '2026-07-16T14:31:23.010332+00:00', 'Cuota Base (2/9)', 30000),
    _pago(alumno, 3, '2026-07-16T14:31:23.054621+00:00', 'Cuota Base (3/9)', 30000),
    _pago(alumno, 4, '2026-07-16T14:31:23.075393+00:00',
        'Cargo canal / operador (ref. MP u otro)', 2000),
    _pago(alumno, 5, f1, 'Mesa Extra (1/5)', 9765),
    _pago(alumno, 6, f1, 'Cargo canal / operador (ref. MP u otro)', 3000),
    _pago(alumno, 7, f1, 'Cuota Base (4/9)', 30000),
    _pago(alumno, 8, f1, 'Cuota Base (5/9)', 30000),
    _pago(alumno, 9, f1, 'Cuota Base (4/9)', 30000, anulado: true),
    _pago(alumno, 10, f1, moraTexto, 39300, anulado: true),
    _pago(alumno, 11, f1, 'Cargo canal / operador (ref. MP u otro)', 3465,
        anulado: true),
    _pago(alumno, 12, f2, 'Cuota Base (4/9)', 30000, anulado: true),
    _pago(alumno, 13, f2, moraTexto, 39300, anulado: true),
    _pago(alumno, 14, f2, 'Cargo canal / operador (ref. MP u otro)', 3465,
        anulado: true),
  ]) {
    await db.insert('pagos_contrato_alumno', p);
  }
}

/// MONTENEGRO, GISEL: eximida al 31/07, permanente (el cobro del 24/07 no
/// completó cuota). El 21/08 completó la 3 y saldó la mora: esa vuelve a contar.
Future<void> _sembrarGisel(String a) async {
    final db = await LocalDatabase.instance;
    await db.insert('contratos_alumnos', {
      'id': uid(a),
      'evento_id': uid('evento'),
      'nombre_alumno': a,
      'monto_total_pactado': 315000,
      'saldo_deudor': 191550,
      'cuotas_pagadas': 3,
      'total_cuotas': 9,
      'dia_vencimiento_mensual': 10,
      'created_at': '2026-03-30T03:00:00+00:00',
      'mora_pendiente_tracked': 0,
      'mora_cobrada_offset': 10500,
      'mora_exenta_hasta': '2026-07-31',
      'mora_exencion_reinicia': 0,
      'mora_tracked_ajuste': 0,
    });
    for (final p in [
      _pago(a, 1, '2026-05-05T14:08:00+00:00', 'Cuota Base (1/9)', 35000),
      _pago(a, 2, '2026-05-05T14:08:01+00:00',
          'Interés mora cuota 1 (vto Abr 2026)', 1750),
      _pago(a, 3, '2026-06-01T20:25:00+00:00', 'Cuota Base (2/9)', 35000),
      _pago(a, 4, '2026-06-01T20:25:01+00:00',
          'Interés mora cuota 2 (vto May 2026)', 350),
      _pago(a, 5, '2026-06-01T20:25:02+00:00',
          'Cargo canal / operador (ref. MP u otro)', 1500),
      _pago(a, 6, '2026-07-24T20:22:00+00:00', 'Cuota Base (3/9)', 35000,
          anulado: true),
      _pago(a, 7, '2026-07-24T20:22:01+00:00',
          'Cargo canal / operador (ref. MP u otro)', 1850, anulado: true),
      _pago(a, 8, '2026-07-24T21:53:00+00:00',
          'Entrega parcial — Cuota Base (3/9)', 26950),
      _pago(a, 9, '2026-07-24T21:53:01+00:00',
          'Interés mora cuota 3 (vto Jun 2026)', 8400),
      _pago(a, 10, '2026-07-24T21:53:02+00:00',
          'Cargo canal / operador (ref. MP u otro)', 1500),
      _pago(a, 11, '2026-08-21T21:34:00+00:00',
          'Cuota Base (3/9) — Completada', 8050),
      _pago(a, 12, '2026-08-21T21:34:01+00:00',
          'Entrega parcial — Cuota Base (4/9)', 18450),
      _pago(a, 13, '2026-08-21T21:34:02+00:00',
          'Interés mora cuota 4 (vto Jul 2026)', 7350),
      _pago(a, 14, '2026-08-21T21:34:03+00:00',
          'Cargo canal / operador (ref. MP u otro)', 3000),
    ]) {
      await db.insert('pagos_contrato_alumno', p);
    }
}

/// ALTAMIRANO, CELESTE ABIGAIL: cuota única. Se acordó un precio de $407.000 y
/// el 15/10 lo pagó entero, sin la mora: el cobro dejó $683.760 en la ficha
/// (168 días desde el 30/04, al 1 % por día) para que el jefe los perdone como
/// liquidación. Con [perdonada], el jefe ya la perdonó: la ficha en 0.
Future<void> _sembrarAltamirano(String a, {bool perdonada = false}) async {
  final db = await LocalDatabase.instance;
  await db.insert('contratos_alumnos', {
    'id': uid(a),
    'evento_id': uid('evento'),
    'nombre_alumno': a,
    'monto_total_pactado': 407000,
    'saldo_deudor': 0,
    'cuotas_pagadas': 1,
    'total_cuotas': 1,
    'dia_vencimiento_mensual': 10,
    'created_at': '2026-03-30T03:00:00+00:00',
    'mora_pendiente_tracked': perdonada ? 0 : 683760,
    'mora_cobrada_offset': 0,
    'mora_exencion_reinicia': 1,
    'mora_tracked_ajuste': 0,
  });
  await db.insert(
    'pagos_contrato_alumno',
    _pago(a, 1, '2026-10-15T21:47:00+00:00', 'Cuota Base (1/1)', 407000),
  );
}

Future<ContratoAlumno> _contrato(String alumno) async {
  final db = await LocalDatabase.instance;
  final rows = await db.query(
    'contratos_alumnos',
    where: 'id = ?',
    whereArgs: [uid(alumno)],
  );
  return ContratoAlumno.fromJson(rows.first);
}

Future<List<Map<String, dynamic>>> _pagos(String alumno) async {
  final db = await LocalDatabase.instance;
  return (await db.query(
    'pagos_contrato_alumno',
    where: 'contrato_alumno_id = ?',
    whereArgs: [uid(alumno)],
  )).map((r) => Map<String, dynamic>.from(r)).toList();
}

Future<double> _moraDe(String alumno, {DateTime? el}) async {
  final c = await _contrato(alumno);
  final pagos = await _pagos(alumno);
  return MoraCuotaCalculator.moraPendienteOperativa(
    contrato: c,
    moraCobradaHistorial: MoraTrackedRecovery.moraCobradaDelHistorial(pagos),
    ahoraAr: el ?? _hoy,
  );
}

Future<Map<String, dynamic>?> _colaDe(String alumno) async {
  final db = await LocalDatabase.instance;
  final rows = await db.query(
    '_sync_queue',
    where: 'tabla = ? AND registro_id = ?',
    whereArgs: ['contratos_alumnos', uid(alumno)],
  );
  if (rows.isEmpty) return null;
  return jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
}

Future<int> _revisar({
  bool encolar = true,
  List<String>? constancia,
}) async {
  final db = await LocalDatabase.instance;
  return MoraTrackedRecovery.reconciliarTodos(
    db: db,
    encolarSync: encolar,
    ahoraAr: _hoy,
    constancia: constancia == null
        ? null
        : (r) async => constancia.addAll(r),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('revision_mora');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );
  });

  tearDown(() async {
    await LocalDatabase.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  group('1. la revisión sube lo que corrige', () {
    test('VERON: la mora de julio ya pagada deja de tapar la de agosto y '
        'septiembre: \$1.100 pasa a \$33.000', () async {
      const a = 'PRUEBA VERON';
      await _sembrarVeron(a);
      expect(await _moraDe(a), closeTo(1100, 0.01));

      final renglones = <String>[];
      expect(await _revisar(constancia: renglones), 1);

      final c = await _contrato(a);
      expect(c.moraCobradaOffset, closeTo(31900, 0.01));
      // La eximición del cobro de agosto queda como estaba.
      expect(c.moraExentaHasta, DateTime(2026, 8, 31));
      expect(c.moraExencionReinicia, isFalse);
      expect(await _moraDe(a), closeTo(33000, 0.01));

      // Y sube: el "ya usado" y la eximición, que era la única copia.
      final cola = await _colaDe(a);
      expect(cola, isNotNull, reason: 'Sin subir, la nube lo vuelve a pisar.');
      expect(cola!['mora_cobrada_offset'], closeTo(31900, 0.01));
      expect(cola['mora_exenta_hasta'], '2026-08-31');
      expect(cola['mora_exencion_reinicia'], 0);

      expect(renglones, hasLength(1));
      expect(renglones.single, contains('PRUEBA VERON'));
      expect(renglones.single, contains(r'mora $1100 -> $33000'));
    });

    test('corrida dos veces, la segunda no toca nada', () async {
      const a = 'PRUEBA VERON';
      await _sembrarVeron(a);
      expect(await _revisar(), 1);
      final db = await LocalDatabase.instance;
      await db.delete('_sync_queue');
      expect(await _revisar(), 0);
      expect(await _colaDe(a), isNull);
    });

    test('sin encolarSync corrige la PC y no sube nada (como antes)', () async {
      const a = 'PRUEBA VERON';
      await _sembrarVeron(a);
      expect(await _revisar(encolar: false), 1);
      expect((await _contrato(a)).moraCobradaOffset, closeTo(31900, 0.01));
      expect(await _colaDe(a), isNull);
    });
  });

  group('2. mora pagada en dos veces', () {
    test('la regla: al saldar toda la mora, el "ya usado" cubre todo lo '
        'cobrado, también lo de un cobro anterior que no entró', () {
      final desglose = [
        MoraCuotaDetalle(
          numeroCuota: 3,
          vencimiento: DateTime(2026, 6, 30),
          diasMora: 105,
          interesBruto: 52850,
          mesLabel: 'Jun 2026',
        ),
      ];
      EstadoMoraPostCobro post({double? historial}) =>
          MoraCuotaCalculator.postCobroTrackedOffset(
            moraPendienteTrackedActual: 0,
            moraCobradaOffsetActual: 18550,
            moraEsteCobro: 52850,
            cuotasBaseLiquidadasEnCobro: 1,
            cuotasBasePagadasPostCobro: 3,
            moraDesglosePreCobro: desglose,
            moraDesgloseNetoPreCobro: desglose,
            moraDesgloseNetoTotal: 52850,
            saldoDeudorPost: 187250,
            fechaCobroAr: DateTime(2026, 10, 13, 10, 39),
            exencionActual: null,
            reiniciaActual: true,
            moraCobradaHistorialPreCobro: historial,
          );
      // Sin el historial, como antes: solo suma lo de este cobro.
      expect(post().offset, closeTo(71400, 0.01));
      // Con el historial ($18.550 + $29.400), cubre todo lo cobrado.
      final p = post(historial: 47950);
      expect(p.offset, closeTo(100800, 0.01));
      expect(p.exentaHasta, DateTime(2026, 10, 31));
    });

    test('si el cobro no salda toda la mora, el "ya usado" no cambia', () {
      final desglose = [
        MoraCuotaDetalle(
          numeroCuota: 3,
          vencimiento: DateTime(2026, 6, 30),
          diasMora: 84,
          interesBruto: 50000,
          mesLabel: 'Jun 2026',
        ),
      ];
      final p = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 0,
        moraCobradaOffsetActual: 18550,
        moraEsteCobro: 29400,
        cuotasBaseLiquidadasEnCobro: 0,
        cuotasBasePagadasPostCobro: 2,
        moraDesglosePreCobro: desglose,
        moraDesgloseNetoPreCobro: desglose,
        moraDesgloseNetoTotal: 50000,
        saldoDeudorPost: 236250,
        fechaCobroAr: DateTime(2026, 9, 22, 9, 31),
        exencionActual: null,
        reiniciaActual: true,
        moraCobradaHistorialPreCobro: 18550,
      );
      expect(p.offset, closeTo(18550, 0.01));
      expect(p.exentaHasta, isNull);
    });

    test('MOLINA: la revisión deja el "ya usado" en todo lo cobrado, y los '
        '\$29.400 del 22/09 dejan de tapar la mora de noviembre', () async {
      const a = 'PRUEBA MOLINA';
      await _sembrarMolina(a);
      final noviembre = DateTime(2026, 11, 20, 12);
      final antes = await _moraDe(a, el: noviembre);

      expect(await _revisar(), 1);
      final c = await _contrato(a);
      expect(c.moraCobradaOffset, closeTo(100800, 0.01));
      expect(c.moraExentaHasta, DateTime(2026, 10, 31));
      final despues = await _moraDe(a, el: noviembre);
      expect(despues, greaterThan(antes));
      expect(despues - antes, lessThanOrEqualTo(29400 + 0.01));
      expect((await _colaDe(a))!['mora_cobrada_offset'], closeTo(100800, 0.01));
    });
  });

  group('3. la eximición de un cobro anulado', () {
    test('MONTENEGRO: la revisión le saca la eximición que había dejado el '
        'cobro anulado, y lo sube', () async {
      const a = 'PRUEBA MONTENEGRO';
      await _sembrarMontenegro(a);
      final c0 = await _contrato(a);
      expect(
        MoraTrackedRecovery.exencionDeCobroAnulado(
          contrato: c0,
          pagos: await _pagos(a),
        ),
        isNotNull,
      );

      expect(await _revisar(), 1);
      final c = await _contrato(a);
      expect(c.moraExentaHasta, isNull);
      expect(c.moraExencionReinicia, isTrue);
      // Sin mora cobrada vigente, el "ya usado" vuelve a 0.
      expect(c.moraCobradaOffset, closeTo(0, 0.01));
      final cola = (await _colaDe(a))!;
      expect(cola.containsKey('mora_exenta_hasta'), isTrue);
      expect(cola['mora_exenta_hasta'], isNull);
    });

    test('un perdón no se toca: con ajuste de ficha, la eximición queda',
        () async {
      const a = 'PRUEBA MONTENEGRO PERDONADO';
      await _sembrarMontenegro(a, ajuste: -1200);
      final c0 = await _contrato(a);
      expect(
        MoraTrackedRecovery.exencionDeCobroAnulado(
          contrato: c0,
          pagos: await _pagos(a),
        ),
        isNull,
      );
      await _revisar();
      final c = await _contrato(a);
      expect(c.moraExentaHasta, DateTime(2026, 9, 30));
    });

    test('un perdón sin ajuste tampoco: si ningún cobro da esa eximición, '
        'queda como está', () async {
      const a = 'PRUEBA PERDON';
      final db = await LocalDatabase.instance;
      await db.insert('contratos_alumnos', {
        'id': uid(a),
        'evento_id': uid('evento'),
        'nombre_alumno': a,
        'monto_total_pactado': 270000,
        'saldo_deudor': 210000,
        'cuotas_pagadas': 2,
        'total_cuotas': 9,
        'dia_vencimiento_mensual': 10,
        'created_at': '2026-03-30T03:00:00+00:00',
        'mora_pendiente_tracked': 0,
        'mora_cobrada_offset': 0,
        'mora_exenta_hasta': '2026-10-31',
        'mora_exencion_reinicia': 0,
        'mora_tracked_ajuste': 0,
      });
      for (final p in [
        _pago(a, 1, '2026-04-20T22:09:00+00:00', 'Cuota Base (1/9)', 30000),
        _pago(a, 2, '2026-06-20T22:09:00+00:00', 'Cuota Base (2/9)', 30000),
        _pago(a, 3, '2026-06-20T22:09:01+00:00', 'Cuota Base (3/9)', 30000,
            anulado: true),
      ]) {
        await db.insert('pagos_contrato_alumno', p);
      }
      await _revisar();
      final c = await _contrato(a);
      expect(c.moraExentaHasta, DateTime(2026, 10, 31));
      expect(c.moraExencionReinicia, isFalse);
    });
  });

  group('4. una eximición vieja no le pasa su "permanente" a una nueva', () {
    test('MONTENEGRO, GISEL: la del 24/07 era permanente (no completó cuota); '
        'la del 21/08 completó la 3 y vuelve a contar: queda esa', () async {
      const a = 'PRUEBA GISEL';
      await _sembrarGisel(a);

      await _revisar();
      final c = await _contrato(a);
      expect(c.moraExentaHasta, DateTime(2026, 8, 31));
      expect(c.moraExencionReinicia, isTrue,
          reason: 'La del 21/08 completó una cuota: vuelve a contar.');
      expect((await _colaDe(a))!['mora_exencion_reinicia'], 1);
    });
    test('la reparación de eximiciones usa la misma regla y sube', () async {
      const a = 'PRUEBA GISEL';
      await _sembrarGisel(a);
      const b = 'PRUEBA MONTENEGRO';
      await _sembrarMontenegro(b);
      final db = await LocalDatabase.instance;
      final n = await MoraTrackedRecovery.repararExencionDesdeHistorial(
        db: db,
        encolarSync: true,
      );
      expect(n, 2);
      final c = await _contrato(a);
      expect(c.moraExentaHasta, DateTime(2026, 8, 31));
      expect(c.moraExencionReinicia, isTrue);
      expect((await _colaDe(a))!['mora_exencion_reinicia'], 1);
      expect((await _contrato(b)).moraExentaHasta, isNull);
      expect((await _colaDe(b))!['mora_exenta_hasta'], isNull);
    });
  });

  group('6. al reincorporar una baja, se revisa en el momento (6.1.0)', () {
    // ESPINOZA, DENIS AIMARA: pagó las cuotas 1, 2 y 3 antes de que vencieran
    // (31/03, 13/05 y 10/06). La 6.0.0 le rehízo la ficha contando la mora
    // hasta el día de su baja (05/09) también para esos pagos: 128, 97 y 67
    // días, $87.600 que nunca existieron.
    Future<void> sembrarDenis(String alumno) async {
      final db = await LocalDatabase.instance;
      await db.insert('contratos_alumnos', {
        'id': uid(alumno),
        'evento_id': uid('evento'),
        'nombre_alumno': alumno,
        'monto_total_pactado': 340000,
        'saldo_deudor': 250000,
        'cuotas_pagadas': 3,
        'total_cuotas': 9,
        'dia_vencimiento_mensual': 10,
        'mesa_extra_precio': 70000,
        'mesa_extra_cuotas': 7,
        'mesa_extra_cantidad': 1,
        'created_at': '2026-03-30T03:00:00+00:00',
        'mora_pendiente_tracked': 87600,
        'mora_cobrada_offset': 0,
        'mora_exencion_reinicia': 1,
        'mora_tracked_ajuste': 0,
        'mora_fecha_referencia': '2026-09-05',
      });
      for (final p in [
        _pago(alumno, 1, '2026-03-31T20:16:25.182781+00:00',
            'Abono Cuota Base', 30000),
        _pago(alumno, 2, '2026-05-13T20:02:30.414950+00:00',
            'Cuota Base (2/9)', 30000),
        _pago(alumno, 3, '2026-06-10T20:16:26.961114+00:00',
            'Cuota Base (3/9)', 30000),
      ]) {
        await db.insert('pagos_contrato_alumno', p);
      }
    }

    test('DENIS: la ficha de \$87.600 queda en 0 y sube; nadie más se toca',
        () async {
      const denis = 'PRUEBA ESPINOZA DENIS';
      const veron = 'PRUEBA VERON';
      await sembrarDenis(denis);
      await _sembrarVeron(veron);

      final db = await LocalDatabase.instance;
      final renglones = <String>[];
      final corregidos = await MoraTrackedRecovery.reconciliarTodos(
        db: db,
        encolarSync: true,
        ahoraAr: _hoy,
        soloContratos: {uid(denis)},
        constancia: (r) async => renglones.addAll(r),
      );

      expect(corregidos, 1);
      final c = await _contrato(denis);
      expect(c.moraPendienteTracked, closeTo(0, 0.01));
      // Le queda la mora de las cuotas 4, 5 y 6, que no pagó, al 15/10:
      // 76, 45 y 15 días de $300.
      expect(await _moraDe(denis), closeTo(40800, 0.01));
      expect((await _colaDe(denis))!['mora_pendiente_tracked'], 0);
      expect(renglones.single, contains('de ficha \$87600 -> \$0'));

      // VERON también necesita la revisión, pero no se la pidieron.
      expect((await _contrato(veron)).moraCobradaOffset, closeTo(0, 0.01));
      expect(await _colaDe(veron), isNull);
    });

    test('la ficha de DENIS no se explica cuota por cuota hasta que se revisa',
        () async {
      const denis = 'PRUEBA ESPINOZA DENIS';
      const veron = 'PRUEBA VERON';
      await sembrarDenis(denis);
      await _sembrarVeron(veron);
      final db = await LocalDatabase.instance;

      expect(await MoraTrackedRecovery.fichasSinExplicar(db), [
        '$denis: mora en la ficha \$87600, sin explicar \$87600',
      ]);

      await MoraTrackedRecovery.reconciliarTodos(
        db: db,
        ahoraAr: _hoy,
        soloContratos: {uid(denis)},
      );
      expect(await MoraTrackedRecovery.fichasSinExplicar(db), isEmpty);
    });
  });

  group('7. cuánto de una ficha queda sin explicar (6.1.0)', () {
    MoraPendientePreviaDetalle de(int cuota, double monto) =>
        MoraPendientePreviaDetalle(
          numeroCuota: cuota,
          mesLabel: 'Abr 2026',
          montoAtribuido: monto,
        );

    test('explicada entera: 0', () {
      expect(
        MoraTrackedOrigen.sinExplicar(
          tracked: 39900,
          origen: [de(1, 24600), de(2, 15300)],
        ),
        0,
      );
    });

    test('sin origen: toda', () {
      expect(
        MoraTrackedOrigen.sinExplicar(tracked: 87600, origen: const []),
        87600,
      );
    });

    test('el renglón genérico (cuota 0) no explica nada', () {
      expect(
        MoraTrackedOrigen.sinExplicar(tracked: 5000, origen: [de(0, 5000)]),
        5000,
      );
    });

    test('en parte: lo que falta; un peso de redondeo no cuenta', () {
      expect(
        MoraTrackedOrigen.sinExplicar(tracked: 10000, origen: [de(3, 7000)]),
        3000,
      );
      expect(
        MoraTrackedOrigen.sinExplicar(tracked: 10000, origen: [de(3, 9999.5)]),
        0,
      );
      expect(MoraTrackedOrigen.sinExplicar(tracked: 0, origen: const []), 0);
    });
  });

  group('quien ya terminó de pagar no se revisa', () {
    test('ALTAMIRANO: la mora que dejó el cobro queda en la ficha hasta que el '
        'jefe la perdone', () async {
      const a = 'PRUEBA ALTAMIRANO';
      await _sembrarAltamirano(a);
      expect(await _moraDe(a), closeTo(683760, 0.01));

      expect(await _revisar(), 0);
      expect((await _contrato(a)).moraPendienteTracked, closeTo(683760, 0.01));
      expect(await _moraDe(a), closeTo(683760, 0.01));
      expect(await _colaDe(a), isNull, reason: 'No se sube nada: no cambió.');
    });

    test('ALTAMIRANO perdonada por el jefe: queda en 0 y no se revive',
        () async {
      const a = 'PRUEBA ALTAMIRANO PERDONADA';
      await _sembrarAltamirano(a, perdonada: true);
      expect(await _revisar(), 0);
      expect(await _moraDe(a), closeTo(0, 0.01));
      expect(await _colaDe(a), isNull);
    });

    test('con saldo, la misma revisión sigue corrigiendo', () async {
      const a = 'PRUEBA ALTAMIRANO';
      await _sembrarAltamirano(a);
      const b = 'PRUEBA VERON';
      await _sembrarVeron(b);
      expect(await _revisar(), 1);
      expect((await _contrato(b)).moraCobradaOffset, closeTo(31900, 0.01));
      expect((await _contrato(a)).moraPendienteTracked, closeTo(683760, 0.01));
    });
  });

  group('5. que corra sola', () {
    String leer(String ruta) => File(ruta).readAsStringSync();

    test('la sincronización corre la revisión sola, una vez por sesión, y '
        'cada vez que se baja todo', () {
      final s = leer('lib/core/services/sync_engine.dart');
      final pullOperativo = s.substring(
        s.indexOf('Future<bool> pullOperationalUpdates('),
        s.indexOf('Future<RemoteProbeInfo>', s.indexOf('Future<bool> pullOperationalUpdates(')),
      );
      expect(pullOperativo, contains('_moraRevisadaEnEstaSesion'));
      expect(pullOperativo, contains('await revisarMora()'));
      final pullCompleto = s.substring(s.indexOf('Future<void> _pullFromCloud('));
      expect(
        pullCompleto.substring(0, pullCompleto.indexOf('_tablasConFalloPull.isNotEmpty')),
        contains('await revisarMora()'),
      );
      final revisar = s.substring(
        s.indexOf('Future<void> revisarMora('),
        s.indexOf('Future<bool> pullOperationalUpdates('),
      );
      // Cada una de las dos revisiones, por separado, tiene que subir.
      String llamada(String nombre) {
        final i = revisar.indexOf(nombre);
        expect(i, greaterThanOrEqualTo(0), reason: 'falta $nombre');
        return revisar.substring(i, revisar.indexOf(');', i));
      }

      expect(llamada('MoraTrackedRecovery.reconciliarTodos('),
          contains('encolarSync: true'));
      expect(llamada('MoraTrackedRecovery.reconciliarTodos('),
          contains('RevisionMoraConstancia.anotar'));
      // La de un alumno solo (al reincorporar una baja) revisa solo a ese.
      expect(llamada('MoraTrackedRecovery.reconciliarTodos('),
          contains('soloContratos: soloContratos'));
      // Y la de todos anota las fichas que no se explican cuota por cuota.
      expect(revisar, contains('MoraTrackedRecovery.fichasSinExplicar(db)'));
      expect(revisar,
          contains('queHizo: MoraTrackedRecovery.queHizoFichasSinExplicar'));
      expect(llamada('MoraTrackedRecovery.repararExencionDesdeHistorial('),
          contains('encolarSync: true'));
    });

    test('anular un cobro deshace la eximición que había dado', () {
      final s = leer('lib/features/mi_empresa/repositories/finanzas_repository.dart');
      final anular = s.substring(s.indexOf('Future<Set<String>> anularPagosConMotivo('));
      expect(anular, contains('MoraTrackedRecovery.exencionDeCobroAnulado('));
    });

    test('el cobro le pasa a la cuenta todo lo cobrado antes', () {
      for (final ruta in [
        'lib/features/eventos/services/cobro_mora_resolver.dart',
        'lib/features/eventos/services/mora_tracked_recovery.dart',
        'lib/features/eventos/services/mora_tracked_origen.dart',
      ]) {
        final s = leer(ruta);
        final llamadas = 'MoraCuotaCalculator.postCobroTrackedOffset('.allMatches(s).length;
        final conHistorial = 'moraCobradaHistorialPreCobro:'.allMatches(s).length;
        expect(conHistorial, llamadas, reason: '$ruta: cada cuenta del cobro necesita el historial');
      }
    });
  });

  test('la constancia: la fecha y un renglón por alumno', () {
    final t = RevisionMoraConstancia.textoDe(
      ['PRUEBA VERON: mora \$1100 -> \$33000'],
      DateTime(2026, 10, 16, 9, 5),
    );
    expect(t, startsWith('16/10/2026 09:05 · la revisión automática de la mora '
        'corrigió 1 alumno(s):'));
    expect(t, contains('  PRUEBA VERON: mora \$1100 -> \$33000'));
  });
}
