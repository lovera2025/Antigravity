// La venta de entradas en la base del equipo (`EntradasLocal`, v80): el precio
// de la fiesta, la caja, las ventas con su número, anular y "Pago verificado".
// Sobre una base temporal y sin red.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/entradas/datos/entradas_local.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _otraFiesta = 'e0000000-0000-4000-8000-000000000002';
const _f1 = 'a0000000-0000-4000-8000-000000000001';
const _f2 = 'a0000000-0000-4000-8000-000000000002';
const _familia = 'c0000000-0000-4000-8000-000000000001';

void main() {
  late Directory docs;
  late EntradasLocal entradas;
  late DateTime ahora;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    docs = Directory.systemTemp.createTempSync('entradas_repo');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );
    ahora = DateTime.utc(2026, 11, 20, 15);
    entradas = EntradasLocal(
      equipo: () async => 'pc-1',
      reloj: () => ahora = ahora.add(const Duration(seconds: 1)),
    );
  });

  tearDown(() async {
    await LocalDatabase.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  Future<List<Map<String, Object?>>> cola([String? tabla]) async {
    final db = await LocalDatabase.instance;
    return db.query(
      '_sync_queue',
      where: tabla == null ? "tabla LIKE 'entradas\\_%' ESCAPE '\\'" : 'tabla = ?',
      whereArgs: tabla == null ? null : [tabla],
    );
  }

  ConfigEntradas conPrecio({double valor = 10000}) =>
      ConfigEntradas.vacia(_fiesta, ahora: ahora).conPrecios(
        valorEntrada: valor,
        precioAnticipada: null,
        anticipadaHasta: null,
        descuentoLugaresPct: 50,
        recargoPct: 0,
        descuentoAMano: false,
      );

  Future<VentaEntradas> vender(
    CajaEntradas caja, {
    int sueltas = 2,
    String comprador = 'F2, COMPRADORA',
    String? numeros,
  }) =>
      entradas.vender(
        caja: caja,
        compradorNombre: comprador,
        renglones: [
          RenglonEntradas.suelta(
            nombre: 'Entrada general',
            precioLista: 10000,
            cantidad: sueltas,
          ),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 10000.0 * sueltas,
        numeros: numeros,
        quien: 'F1',
      );

  group('el precio de la fiesta', () {
    test('sin nada puesto, no hay config', () async {
      expect(await entradas.config(_fiesta), isNull);
    });

    test('se guarda con quién y desde dónde, y va a la cola', () async {
      final guardada = await entradas.guardarConfig(conPrecio(), quien: 'Jefe');
      expect(guardada.valorEntrada, 10000);
      expect(guardada.hechoPor, 'Jefe');
      expect(guardada.deviceId, 'pc-1');
      expect((await entradas.config(_fiesta))!.toMap(), guardada.toMap());
      expect((await entradas.config(_otraFiesta)), isNull);
      final enCola = (await cola('entradas_config')).single;
      expect(enCola['registro_id'], guardada.id);
    });

    test('guardar sin cambiar nada no escribe', () async {
      final primera = await entradas.guardarConfig(conPrecio(), quien: 'Jefe');
      final db = await LocalDatabase.instance;
      await db.delete('_sync_queue');

      final segunda = await entradas.guardarConfig(conPrecio(), quien: 'Otro');
      expect(segunda.toMap(), primera.toMap(), reason: 'ni quién ni cuándo cambian');
      expect(await cola(), isEmpty);
    });

    test('cambiar el precio reescribe la misma fila y conserva cuándo nació', () async {
      final primera = await entradas.guardarConfig(conPrecio(), quien: 'Jefe');
      final segunda =
          await entradas.guardarConfig(conPrecio(valor: 12000), quien: 'Jefe');
      expect(segunda.id, primera.id);
      expect(segunda.createdAt, primera.createdAt);
      expect(segunda.updatedAt, isNot(primera.updatedAt));
      final db = await LocalDatabase.instance;
      expect(await db.query('entradas_config'), hasLength(1));
    });
  });

  group('la caja', () {
    test('se abre con su cambio, en este equipo, y va a la cola', () async {
      final caja = await entradas.abrirCaja(
        eventoId: _fiesta,
        operadorId: _f1,
        operadorNombre: 'F1',
        cambioInicial: 5000,
      );
      expect(caja.abierta, isTrue);
      expect(caja.cambioInicial, 5000);
      expect(caja.deviceId, 'pc-1');
      expect((await cola('entradas_cajas')).single['registro_id'], caja.id);
    });

    test('tocar VENDER dos veces retoma la misma: no abre otra', () async {
      final una = await entradas.abrirCaja(eventoId: _fiesta, operadorId: _f1);
      final otra = await entradas.abrirCaja(eventoId: _fiesta, operadorId: _f1);
      expect(otra.id, una.id);
      expect(await entradas.cajas(_fiesta), hasLength(1));
      expect((await entradas.cajaAbierta(eventoId: _fiesta, operadorId: _f1))!.id, una.id);
    });

    test('cada operador tiene la suya, y la del jefe va sin operador', () async {
      final deF1 = await entradas.abrirCaja(eventoId: _fiesta, operadorId: _f1);
      final deF2 = await entradas.abrirCaja(eventoId: _fiesta, operadorId: _f2);
      final delJefe = await entradas.abrirCaja(eventoId: _fiesta, operadorNombre: 'Jefe');
      expect({deF1.id, deF2.id, delJefe.id}, hasLength(3));
      expect(delJefe.operadorId, isNull);
      expect((await entradas.cajaAbierta(eventoId: _fiesta))!.id, delJefe.id);
      expect(await entradas.cajaAbierta(eventoId: _otraFiesta, operadorId: _f1), isNull);
    });

    test('una caja abierta en otro equipo no es la de este', () async {
      final enOtro = EntradasLocal(
        equipo: () async => 'tablet-9',
        reloj: () => ahora,
      );
      await enOtro.abrirCaja(eventoId: _fiesta, operadorId: _f1);
      expect(await entradas.cajaAbierta(eventoId: _fiesta, operadorId: _f1), isNull,
          reason: 'una caja vive donde se abrió');
    });

    test('se cierra una sola vez: lo contado queda como se contó', () async {
      final caja = await entradas.abrirCaja(eventoId: _fiesta, operadorId: _f1);
      final cerrada = await entradas.cerrarCaja(
        caja,
        efectivoContado: 19500,
        diferencia: -500,
        nota: 'faltó un billete',
        quien: 'F1',
      );
      expect(cerrada.abierta, isFalse);
      expect(cerrada.efectivoContado, 19500);
      expect(cerrada.diferencia, -500);

      final deNuevo = await entradas.cerrarCaja(
        caja,
        efectivoContado: 99999,
        diferencia: 0,
        quien: 'Otro',
      );
      expect(deNuevo.efectivoContado, 19500, reason: 'no se corrige');
      expect(deNuevo.cerradaAt, cerrada.cerradaAt);
      expect(await entradas.cajaAbierta(eventoId: _fiesta, operadorId: _f1), isNull);
    });

    test('cerrada, solo se le puede agregar la nota', () async {
      final caja = await entradas.abrirCaja(eventoId: _fiesta, operadorId: _f1);
      expect((await entradas.anotarCierre(caja, nota: 'antes', quien: 'F1')).notaCierre, isNull,
          reason: 'abierta, no hay cierre que anotar');
      final cerrada = await entradas.cerrarCaja(
        caja,
        efectivoContado: 0,
        diferencia: 0,
        quien: 'F1',
      );
      final conNota = await entradas.anotarCierre(cerrada, nota: 'todo bien', quien: 'F1');
      expect(conNota.notaCierre, 'todo bien');
      expect(conNota.efectivoContado, cerrada.efectivoContado);
      expect(conNota.cerradaAt, cerrada.cerradaAt);
    });
  });

  group('las ventas', () {
    late CajaEntradas caja;

    setUp(() async {
      caja = await entradas.abrirCaja(
        eventoId: _fiesta,
        operadorId: _f1,
        operadorNombre: 'F1',
      );
    });

    test('dos seguidas llevan el 1 y el 2, y cada una va a la cola', () async {
      final una = await vender(caja);
      final otra = await vender(caja, sueltas: 1);
      expect([una.numero, otra.numero], [1, 2]);
      expect(una.cantidad, 2);
      expect(una.total, 20000);
      expect(una.hechoPor, 'F1');
      expect(una.deviceId, 'pc-1');
      expect(await cola('entradas_ventas'), hasLength(2));
      expect(await entradas.ventasSinSubir(), 2);
      expect([for (final v in await entradas.ventasDeLaCaja(caja.id)) v.numero], [1, 2]);
    });

    test('cada caja numera desde 1', () async {
      await vender(caja);
      final deF2 = await entradas.abrirCaja(eventoId: _fiesta, operadorId: _f2);
      expect((await vender(deF2)).numero, 1);
      expect(await entradas.ventas(_fiesta), hasLength(2));
    });

    test('lo que sube lleva exactamente lo que quedó en la base', () async {
      final venta = await entradas.vender(
        caja: caja,
        contratoAlumnoId: _familia,
        compradorNombre: '  F2,   COMPRADORA ',
        compradorDni: '30111222',
        renglones: [
          RenglonEntradas.lugar(
            nombre: 'Entrada de lugar adicional (50 %)',
            precioLista: 10000,
            descuentoPct: 50,
            cantidad: 8,
          ),
        ],
        medio: MedioBarra.transferencia,
        transferencia: 40000,
        numeros: '1043-1050',
        quien: 'F1',
      );
      expect(venta.compradorNombre, 'F2, COMPRADORA', reason: 'sin espacios de más');
      final db = await LocalDatabase.instance;
      final enLaBase = (await db.query('entradas_ventas')).single;
      final payload = jsonDecode(
        (await cola('entradas_ventas')).single['payload'] as String,
      ) as Map<String, dynamic>;
      expect(payload.keys.toSet(), enLaBase.keys.toSet());
      expect(payload['contrato_alumno_id'], _familia);
      expect(payload['numeros'], '1043-1050');
      expect(VentaEntradas.fromMap(enLaBase).cuantas(TipoRenglonEntradas.lugar), 8);
    });

    test('una venta que no cierra no se guarda', () async {
      await expectLater(
        entradas.vender(
          caja: caja,
          compradorNombre: '   ',
          renglones: [
            RenglonEntradas.suelta(nombre: 'Entrada general', precioLista: 10000, cantidad: 1),
          ],
          medio: MedioBarra.efectivo,
          efectivo: 10000,
          quien: 'F1',
        ),
        throwsArgumentError,
      );
      await expectLater(
        entradas.vender(
          caja: caja,
          compradorNombre: 'F2, COMPRADORA',
          renglones: [
            RenglonEntradas.suelta(nombre: 'Entrada general', precioLista: 10000, cantidad: 2),
          ],
          medio: MedioBarra.efectivo,
          efectivo: 15000, // no da el total
          quien: 'F1',
        ),
        throwsArgumentError,
      );
      expect(await entradas.ventas(_fiesta), isEmpty);
      expect(await cola('entradas_ventas'), isEmpty);
      // Y el número no se gastó.
      expect((await vender(caja)).numero, 1);
    });

    test('con la caja cerrada no se vende', () async {
      final cerrada = await entradas.cerrarCaja(
        caja,
        efectivoContado: 0,
        diferencia: 0,
        quien: 'F1',
      );
      await expectLater(vender(cerrada), throwsStateError);
      await expectLater(vender(caja), throwsStateError,
          reason: 'aunque la pantalla tenga la caja vieja en la mano');
    });

    test('una caja que no es de este equipo no vende acá', () async {
      final ajena = CajaEntradas.abrir(eventoId: _fiesta, ahora: ahora);
      await expectLater(vender(ajena), throwsStateError);
    });
  });

  group('anular y verificar', () {
    late VentaEntradas venta;

    setUp(() async {
      final caja = await entradas.abrirCaja(eventoId: _fiesta, operadorId: _f1);
      venta = await vender(caja, numeros: '1043-1044');
    });

    test('anular agrega una fila, con motivo; la venta no se toca', () async {
      final db = await LocalDatabase.instance;
      final antes = (await db.query('entradas_ventas')).single;
      final a = await entradas.anular(
        venta,
        motivo: 'se cargó dos veces',
        devueltas: true,
        quien: 'Jefe',
      );
      expect(a.ventaId, venta.id);
      expect(a.devueltas, isTrue);
      expect(a.hechoPor, 'Jefe');
      expect((await db.query('entradas_ventas')).single, antes);
      expect(await entradas.anulaciones(_fiesta), hasLength(1));
      expect(await entradas.anulacionesDeLaCaja(venta.cajaEntradasId), hasLength(1));
      expect((await cola('entradas_anulaciones')).single['registro_id'], a.id);
    });

    test('sin motivo no se anula', () async {
      await expectLater(
        entradas.anular(venta, motivo: '  ', devueltas: true, quien: 'Jefe'),
        throwsArgumentError,
      );
      expect(await entradas.anulaciones(_fiesta), isEmpty);
    });

    test('anular dos veces devuelve la que ya había', () async {
      final primera = await entradas.anular(
        venta,
        motivo: 'la primera',
        devueltas: false,
        quien: 'Jefe',
      );
      final segunda = await entradas.anular(
        venta,
        motivo: 'otra',
        devueltas: true,
        quien: 'Otro',
      );
      expect(segunda.toMap(), primera.toMap());
      expect(await entradas.anulaciones(_fiesta), hasLength(1));
    });

    test('"Pago verificado": una fila por venta, que se tilda y se destilda', () async {
      final tildada = await entradas.verificar(venta, verificado: true, quien: 'Jefe');
      expect(tildada.verificado, isTrue);
      expect(tildada.hechoPor, 'Jefe');
      final destildada = await entradas.verificar(venta, verificado: false, quien: 'Jefe');
      expect(destildada.id, tildada.id);
      expect(destildada.verificado, isFalse);
      expect(destildada.createdAt, tildada.createdAt, reason: 'es la misma fila');
      final todas = await entradas.verificaciones(_fiesta);
      expect(todas.single.verificado, isFalse);
      // La venta sigue como se vendió.
      expect((await entradas.ventas(_fiesta)).single.toMap(), venta.toMap());
    });
  });

  test('una base que todavía no migró se lee vacía, sin tirar', () async {
    final sinTablas = EntradasLocal(
      abrir: () async {
        final db = await LocalDatabase.instance;
        for (final t in EntradasLocal.tablas) {
          await db.execute('DROP TABLE IF EXISTS $t');
        }
        return db;
      },
      equipo: () async => 'pc-1',
    );
    expect(await sinTablas.config(_fiesta), isNull);
    expect(await sinTablas.cajas(_fiesta), isEmpty);
    expect(await sinTablas.ventas(_fiesta), isEmpty);
    expect(await sinTablas.anulaciones(_fiesta), isEmpty);
    expect(await sinTablas.verificaciones(_fiesta), isEmpty);
    expect(await sinTablas.cajaAbierta(eventoId: _fiesta), isNull);
  });
}
