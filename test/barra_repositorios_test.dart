import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/barra/datos/barra_local.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

/// Los datos de la barra en el equipo: lo que se guarda, lo que se encola para subir,
/// el número del ticket, que una venta nunca se toca, y que nada se borra. Sobre una
/// base en memoria: no sale nada de la PC.
const _evento = 'e0000000-0000-4000-8000-000000000001';
const _otraFiesta = 'e0000000-0000-4000-8000-000000000002';
const _marta = 'a0000000-0000-4000-8000-000000000001';
const _juan = 'a0000000-0000-4000-8000-000000000002';

void main() {
  sqfliteFfiInit();
  late Database db;
  late DateTime reloj;
  late String equipo;
  late BarraLocal barra;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE _sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tabla TEXT NOT NULL,
        operacion TEXT NOT NULL,
        registro_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        intentos INTEGER DEFAULT 0,
        ultimo_error TEXT
      )
    ''');
    await LocalDatabase.crearTablasV77(db);
    await LocalDatabase.crearTablasV78(db);
    reloj = DateTime.utc(2026, 12, 4, 22);
    equipo = 'tablet-1';
    barra = BarraLocal(
      abrir: () async => db,
      equipo: () async => equipo,
      reloj: () => reloj,
    );
  });

  tearDown(() => db.close());

  Future<List<Map<String, Object?>>> encolado(String tabla) =>
      db.query('_sync_queue', where: 'tabla = ?', whereArgs: [tabla]);

  RenglonVenta renglon(String nombre, double precio, int cantidad) => RenglonVenta(
        productoId: UuidUtils.generate(),
        nombre: nombre,
        precio: precio,
        cantidad: cantidad,
      );

  Future<CajaBarra> abrirLaDeMarta({int numero = 2}) => barra.abrirCaja(
        eventoId: _evento,
        operadorId: _marta,
        operadorNombre: 'Marta',
        numeroCaja: numero,
        cambioInicial: 20000,
      );

  Future<VentaBarra> venderUnaCerveza(CajaBarra caja) => barra.vender(
        caja: caja,
        renglones: [renglon('Cerveza lata', 3500, 2)],
        medio: MedioBarra.efectivo,
        efectivo: 7000,
        recibe: 10000,
        quien: 'Marta',
      );

  // La central de la barra (red del salón): lo que llega de otra caja se guarda sin la
  // cola de subida, porque lo sube la caja que lo hizo.
  group('lo que llega de otra caja por la red del salón', () {
    Future<VentaBarra> ventaDeOtraCaja() async {
      final otra = BarraLocal(
        abrir: () async => db,
        equipo: () async => 'tablet-2',
        reloj: () => reloj,
      );
      final caja = await otra.abrirCaja(
        eventoId: _evento,
        operadorId: _juan,
        operadorNombre: 'Juan',
        numeroCaja: 3,
      );
      final venta = await venderUnaCerveza(caja);
      // Como si la hubiera hecho otro equipo: acá no queda nada de ella.
      await db.delete('barra_ventas');
      await db.delete('barra_cajas');
      await db.delete('_sync_queue');
      return venta;
    }

    test('se guarda sin encolarla, y la misma dos veces no cambia nada', () async {
      final venta = await ventaDeOtraCaja();
      expect(await barra.guardarDeOtroEquipo('barra_ventas', venta.toMap()), isTrue);
      expect((await db.query('barra_ventas')).single['id'], venta.id);
      expect(await encolado('barra_ventas'), isEmpty, reason: 'la sube la caja que la hizo');
      expect(await barra.guardarDeOtroEquipo('barra_ventas', venta.toMap()), isFalse);
      expect((await barra.pendientesDeLaBarra()).vacio, isTrue);
    });

    test('lo que esta caja tiene sin subir no lo pisa lo que llega', () async {
      final caja = await abrirLaDeMarta();
      final cerrada = await barra.cerrarCaja(caja, efectivoContado: 0, diferencia: 0, quien: 'Marta');
      final vieja = Map<String, Object?>.from(caja.toMap())
        ..['updated_at'] = DateTime.utc(2027).toIso8601String();
      expect(await barra.guardarDeOtroEquipo('barra_cajas', vieja), isFalse);
      expect(CajaBarra.fromMap((await db.query('barra_cajas')).single).abierta, isFalse);
      expect(cerrada.abierta, isFalse);
    });

    test('una columna que esta versión no conoce se deja afuera, y otras tablas no se tocan', () async {
      final venta = await ventaDeOtraCaja();
      final conDeMas = Map<String, Object?>.from(venta.toMap())..['columna_nueva'] = 'x';
      expect(await barra.guardarDeOtroEquipo('barra_ventas', conDeMas), isTrue);
      expect((await db.query('barra_ventas')).single.containsKey('columna_nueva'), isFalse);
      expect(await barra.guardarDeOtroEquipo('barra_precios', venta.toMap()), isFalse,
          reason: 'los precios van por la nube');
    });

    test('cuenta todo lo que espera subir, no solo las ventas', () async {
      final caja = await abrirLaDeMarta();
      await venderUnaCerveza(caja);
      await venderUnaCerveza(caja);
      final p = await barra.pendientesDeLaBarra();
      expect(p.ventas, 2);
      expect(p.otros, 1, reason: 'la caja abierta');
    });

    test('todo lo de la fiesta, de todas las cajas, para el que se conecta', () async {
      final caja = await abrirLaDeMarta();
      await venderUnaCerveza(caja);
      final todo = await barra.filasDeLaFiesta(_evento);
      expect(todo['barra_cajas'], hasLength(1));
      expect(todo['barra_ventas'], hasLength(1));
      expect((await barra.filasDeLaFiesta(_otraFiesta))['barra_ventas'], isEmpty);
    });
  });

  group('el catálogo', () {
    test('guardar un producto lo deja en la base, sellado y encolado', () async {
      final p = await barra.guardarProducto(
        ProductoBarra.nuevo(nombre: '  Fernet con coca ', categoria: 'Tragos', ahora: reloj),
        quien: 'Jefe',
      );
      expect(p.nombre, 'Fernet con coca');
      expect(p.hechoPor, 'Jefe');
      expect(p.deviceId, 'tablet-1');
      final fila = (await db.query('barra_productos')).single;
      expect(ProductoBarra.fromMap(fila).toMap(), p.toMap());
      final cola = (await encolado('barra_productos')).single;
      expect(cola['operacion'], 'insert');
      expect(jsonDecode(cola['payload'] as String)['nombre'], 'Fernet con coca');
    });

    test('guardarlo de nuevo no le cambia cuándo nació', () async {
      final p = await barra.guardarProducto(
        ProductoBarra.nuevo(nombre: 'Agua', ahora: reloj),
        quien: 'Jefe',
      );
      reloj = reloj.add(const Duration(days: 3));
      final otra = await barra.guardarProducto(p.conCambios(nombre: 'Agua mineral'), quien: 'Jefe');
      expect(otra.createdAt, p.createdAt);
      expect(otra.updatedAt, isNot(p.updatedAt));
      expect((await db.query('barra_productos')).single['nombre'], 'Agua mineral');
    });

    test('dar de baja no lo borra: sale de la lista y queda con conBajas', () async {
      final agua = await barra.guardarProducto(ProductoBarra.nuevo(nombre: 'Agua', ahora: reloj), quien: 'J');
      await barra.guardarProducto(ProductoBarra.nuevo(nombre: 'Cerveza', ahora: reloj), quien: 'J');
      await barra.guardarProducto(agua.conCambios(activo: false), quien: 'J');
      expect([for (final p in await barra.productos()) p.nombre], ['Cerveza']);
      expect([for (final p in await barra.productos(conBajas: true)) p.nombre], ['Agua', 'Cerveza']);
      expect(await db.query('barra_productos'), hasLength(2));
    });

    test('se ordenan por orden y después por nombre', () async {
      for (final (n, o) in [('Vino', 1), ('agua', 0), ('Cerveza', 0)]) {
        await barra.guardarProducto(ProductoBarra.nuevo(nombre: n, orden: o, ahora: reloj), quien: 'J');
      }
      expect([for (final p in await barra.productos()) p.nombre], ['agua', 'Cerveza', 'Vino']);
    });

    test('un producto sin nombre no se arma', () {
      expect(() => ProductoBarra.nuevo(nombre: '  ', ahora: reloj), throwsArgumentError);
    });
  });

  group('los precios de cada fiesta', () {
    test('un producto en una fiesta es una sola fila, con id fijo: guardarlo dos veces la pisa', () async {
      const prod = 'b0000000-0000-4000-8000-000000000001';
      await barra.guardarPrecio(
        PrecioBarra.para(eventoId: _evento, productoId: prod, precio: 3500, ahora: reloj),
        quien: 'Jefe',
      );
      await barra.guardarPrecio(
        PrecioBarra.para(eventoId: _evento, productoId: prod, precio: 4000, stockInicial: 240, avisoStock: 24, ahora: reloj),
        quien: 'Jefe en la otra PC',
      );
      final filas = await db.query('barra_precios');
      expect(filas, hasLength(1));
      expect(filas.single['id'], UuidUtils.barraPrecioId(_evento, prod));
      final precio = PrecioBarra.fromMap(filas.single);
      expect(precio.precio, 4000);
      expect(precio.stockInicial, 240);
      expect(precio.controlaStock, isTrue);
      expect(await encolado('barra_precios'), hasLength(1), reason: 'la cola tiene una entrada por fila');
    });

    test('cada fiesta tiene sus precios, y los sacados no se ofrecen', () async {
      const a = 'b0000000-0000-4000-8000-000000000001';
      const b = 'b0000000-0000-4000-8000-000000000002';
      await barra.guardarPrecio(PrecioBarra.para(eventoId: _evento, productoId: a, precio: 1, ahora: reloj), quien: 'J');
      await barra.guardarPrecio(PrecioBarra.para(eventoId: _evento, productoId: b, precio: 2, activo: false, ahora: reloj), quien: 'J');
      await barra.guardarPrecio(PrecioBarra.para(eventoId: _otraFiesta, productoId: a, precio: 9, ahora: reloj), quien: 'J');
      expect([for (final p in await barra.precios(_evento)) p.productoId], [a]);
      expect(await barra.precios(_evento, conBajas: true), hasLength(2));
      expect((await barra.precios(_otraFiesta)).single.precio, 9);
    });

    test('sacarle el stock lo deja sin control', () {
      final p = PrecioBarra.para(eventoId: _evento, productoId: 'x', precio: 1, stockInicial: 10, avisoStock: 2, ahora: reloj);
      final sin = p.conCambios(sinStock: true);
      expect(sin.stockInicial, isNull);
      expect(sin.avisoStock, isNull);
      expect(sin.controlaStock, isFalse);
    });

    test('un precio o un stock negativos no se arman', () {
      expect(() => PrecioBarra.para(eventoId: _evento, productoId: 'x', precio: -1, ahora: reloj), throwsArgumentError);
      expect(() => PrecioBarra.para(eventoId: _evento, productoId: 'x', precio: 1, stockInicial: -3, ahora: reloj), throwsArgumentError);
    });
  });

  group('el recargo de cada fiesta', () {
    test('sin guardar, no hay', () async {
      expect(await barra.recargo(_evento), isNull);
    });

    test('una fila por fiesta, con id fijo: guardarlo de nuevo la pisa y no le cambia cuándo nació',
        () async {
      final primero = await barra.guardarRecargo(
        RecargoBarra.para(eventoId: _evento, pct: 5, ahora: reloj),
        quien: 'Jefe',
      );
      reloj = reloj.add(const Duration(hours: 2));
      final segundo = await barra.guardarRecargo(
        RecargoBarra.para(eventoId: _evento, pct: 10, ahora: reloj),
        quien: 'Jefe en la otra PC',
      );
      final filas = await db.query('barra_recargos');
      expect(filas, hasLength(1));
      expect(filas.single['id'], UuidUtils.barraRecargoId(_evento));
      expect(segundo.createdAt, primero.createdAt);
      expect((await barra.recargo(_evento))!.pct, 10);
      expect((await barra.recargo(_evento))!.hechoPor, 'Jefe en la otra PC');
      expect(await barra.recargo(_otraFiesta), isNull);
      final cola = await encolado('barra_recargos');
      expect(cola, hasLength(1), reason: 'la cola tiene una entrada por fila');
      expect(jsonDecode(cola.single['payload'] as String)['recargo_pct'], 10);
    });

    test('en 0 arranca apagado; negativo o de más de 100 no se arma', () {
      expect(RecargoBarra.para(eventoId: _evento, pct: 0, ahora: reloj).prendido, isFalse);
      expect(RecargoBarra.para(eventoId: _evento, pct: 5, ahora: reloj).prendido, isTrue);
      expect(() => RecargoBarra.para(eventoId: _evento, pct: -1, ahora: reloj), throwsArgumentError);
      expect(() => RecargoBarra.para(eventoId: _evento, pct: 101, ahora: reloj), throwsArgumentError);
    });
  });

  group('la caja', () {
    test('abrirla la guarda con quién la abrió y en qué equipo, y la encola', () async {
      final caja = await abrirLaDeMarta();
      expect(caja.abierta, isTrue);
      expect(caja.operadorNombre, 'Marta');
      expect(caja.deviceId, 'tablet-1');
      expect(caja.cambioInicial, 20000);
      expect((await encolado('barra_cajas')).single['registro_id'], caja.id);
    });

    test('tocar dos veces abrir no abre dos cajas', () async {
      final una = await abrirLaDeMarta();
      final otra = await abrirLaDeMarta(numero: 3);
      expect(otra.id, una.id);
      expect(await db.query('barra_cajas'), hasLength(1));
    });

    test('la caja abierta es la de esta persona, en esta fiesta y en este equipo', () async {
      final caja = await abrirLaDeMarta();
      expect((await barra.cajaAbierta(eventoId: _evento, operadorId: _marta))!.id, caja.id);
      expect(await barra.cajaAbierta(eventoId: _evento, operadorId: _juan), isNull);
      expect(await barra.cajaAbierta(eventoId: _otraFiesta, operadorId: _marta), isNull);
      equipo = 'tablet-2';
      expect(await barra.cajaAbierta(eventoId: _evento, operadorId: _marta), isNull,
          reason: 'una caja vive en el equipo que la abrió');
    });

    test('cerrarla escribe lo contado y la diferencia, y no se corrige nada', () async {
      final caja = await abrirLaDeMarta();
      reloj = reloj.add(const Duration(hours: 5));
      final cerrada = await barra.cerrarCaja(
        caja,
        efectivoContado: 56500,
        diferencia: -500,
        nota: 'faltó un billete',
        quien: 'Marta',
      );
      expect(cerrada.abierta, isFalse);
      final enLaBase = CajaBarra.fromMap((await db.query('barra_cajas')).single);
      expect(enLaBase.efectivoContado, 56500);
      expect(enLaBase.diferencia, -500);
      expect(enLaBase.notaCierre, 'faltó un billete');
      expect(enLaBase.cerradaAt, '2026-12-05T03:00:00.000Z');
      expect(enLaBase.abiertaAt, '2026-12-04T22:00:00.000Z');
      expect(jsonDecode((await encolado('barra_cajas')).single['payload'] as String)['diferencia'], -500);

      final otraVez = await barra.cerrarCaja(caja, efectivoContado: 1, diferencia: 0, quien: 'Marta');
      expect(otraVez.efectivoContado, 56500, reason: 'una caja cerrada no se vuelve a cerrar');
      expect(await barra.cajaAbierta(eventoId: _evento, operadorId: _marta), isNull);
    });

    test('después de cerrar se puede poner la nota, y nada más: lo contado queda', () async {
      final caja = await abrirLaDeMarta();
      final cerrada = await barra.cerrarCaja(caja, efectivoContado: 19500, diferencia: -500, quien: 'Marta');
      reloj = reloj.add(const Duration(minutes: 3));
      final anotada = await barra.anotarCierre(cerrada, nota: ' faltó un billete de 500 ', quien: 'Marta');
      expect(anotada.notaCierre, 'faltó un billete de 500');
      final enLaBase = CajaBarra.fromMap((await db.query('barra_cajas')).single);
      expect(enLaBase.notaCierre, 'faltó un billete de 500');
      expect(enLaBase.efectivoContado, 19500);
      expect(enLaBase.diferencia, -500);
      expect(enLaBase.cerradaAt, cerrada.cerradaAt);
      expect(enLaBase.deviceId, 'tablet-1');
      expect(enLaBase.updatedAt, '2026-12-04T22:03:00.000Z');
      expect(
        jsonDecode((await encolado('barra_cajas')).single['payload'] as String)['nota_cierre'],
        'faltó un billete de 500',
      );
      expect((await barra.anotarCierre(anotada, nota: '', quien: 'Marta')).notaCierre, isNull,
          reason: 'vacía la saca');
    });

    test('sobre una caja abierta, la nota no hace nada', () async {
      final caja = await abrirLaDeMarta();
      final igual = await barra.anotarCierre(caja, nota: 'algo', quien: 'Marta');
      expect(igual.abierta, isTrue);
      expect(igual.notaCierre, isNull);
      expect(CajaBarra.fromMap((await db.query('barra_cajas')).single).notaCierre, isNull);
    });

    test('un número de caja o un cambio inválidos no la abren', () {
      expect(() => CajaBarra.abrir(eventoId: _evento, numeroCaja: 0, ahora: reloj), throwsArgumentError);
      expect(() => CajaBarra.abrir(eventoId: _evento, numeroCaja: 1, cambioInicial: -1, ahora: reloj), throwsArgumentError);
    });

    test('el cambio se pone después de abrir, y sube; una caja cerrada queda como se cerró', () async {
      final caja = await barra.abrirCaja(
        eventoId: _evento,
        operadorId: _marta,
        operadorNombre: 'Marta',
        numeroCaja: 2,
      );
      expect(caja.cambioInicial, 0, reason: 'abrir no lo pregunta');
      final conCambio = await barra.ponerCambio(caja, 15000, quien: 'Marta');
      expect(conCambio.cambioInicial, 15000);
      expect(CajaBarra.fromMap((await db.query('barra_cajas')).single).cambioInicial, 15000);
      expect(jsonDecode((await encolado('barra_cajas')).single['payload'] as String)['cambio_inicial'], 15000);
      await barra.cerrarCaja(conCambio, efectivoContado: 15000, diferencia: 0, quien: 'Marta');
      expect((await barra.ponerCambio(conCambio, 1, quien: 'Marta')).cambioInicial, 15000);
      expect(() => caja.conCambio(-1), throwsArgumentError);
    });

    test('las cajas abiertas de la fiesta, de cualquiera: para avisar un número repetido', () async {
      await abrirLaDeMarta();
      final deJuan = await barra.abrirCaja(
        eventoId: _evento,
        operadorId: _juan,
        operadorNombre: 'Juan',
        numeroCaja: 4,
      );
      await barra.abrirCaja(eventoId: _otraFiesta, operadorId: _juan, operadorNombre: 'Juan', numeroCaja: 1);
      expect([for (final c in await barra.cajasAbiertas(_evento)) c.numeroCaja], [2, 4]);
      await barra.cerrarCaja(deJuan, efectivoContado: 0, diferencia: 0, quien: 'Juan');
      expect([for (final c in await barra.cajasAbiertas(_evento)) c.numeroCaja], [2]);
    });
  });

  test('las fiestas con algún precio activo, en este equipo', () async {
    const prod = 'b0000000-0000-4000-8000-000000000001';
    await barra.guardarPrecio(
      PrecioBarra.para(eventoId: _evento, productoId: prod, precio: 1, ahora: reloj),
      quien: 'Jefe',
    );
    await barra.guardarPrecio(
      PrecioBarra.para(eventoId: _otraFiesta, productoId: prod, precio: 1, activo: false, ahora: reloj),
      quien: 'Jefe',
    );
    expect(await barra.fiestasConPrecio(), {_evento});
  });

  group('las ventas', () {
    test('dos ventas seguidas dan 1 y 2, y cada caja cuenta la suya', () async {
      final marta = await abrirLaDeMarta();
      final juan = await barra.abrirCaja(
        eventoId: _evento, operadorId: _juan, operadorNombre: 'Juan', numeroCaja: 3,
      );
      expect((await venderUnaCerveza(marta)).numero, 1);
      expect((await venderUnaCerveza(marta)).numero, 2);
      expect((await venderUnaCerveza(juan)).numero, 1);
      expect([for (final v in await barra.ventasDeLaCaja(marta.id)) v.numero], [1, 2]);
    });

    test('vendiendo a la vez tampoco se repite el número', () async {
      final caja = await abrirLaDeMarta();
      final ventas = await Future.wait([for (var i = 0; i < 8; i++) venderUnaCerveza(caja)]);
      expect({for (final v in ventas) v.numero}, {1, 2, 3, 4, 5, 6, 7, 8});
    });

    test('la venta se guarda como se vendió, con el nombre y el precio del momento', () async {
      final caja = await abrirLaDeMarta();
      final v = await barra.vender(
        caja: caja,
        renglones: [renglon('Cerveza lata', 3500, 2), renglon('Agua', 1500, 1)],
        medio: MedioBarra.mixto,
        efectivo: 5000,
        transferencia: 3675,
        recibe: 5000,
        recargo: 175,
        recargoPct: 5,
        quien: 'Marta',
      );
      final leida = VentaBarra.fromMap((await db.query('barra_ventas')).single);
      expect(leida.renglones, v.renglones);
      expect(leida.total, 8500);
      expect(leida.medio, MedioBarra.mixto);
      expect(leida.vuelto, 0);
      expect(leida.transferencia, 3675, reason: 'lo transferido, con el recargo');
      expect(leida.recargo, 175);
      expect(leida.recargoPct, 5);
      expect(leida.cobrado, 8675);
      expect(leida.hechoPor, 'Marta');
      expect(leida.eventoId, _evento);
      expect((await encolado('barra_ventas')).single['registro_id'], v.id);
    });

    test('en efectivo, el vuelto es lo que sobra de lo recibido', () async {
      final v = await venderUnaCerveza(await abrirLaDeMarta());
      expect(v.total, 7000);
      expect(v.recibe, 10000);
      expect(v.vuelto, 3000);
    });

    test('con la caja cerrada no se vende', () async {
      final caja = await abrirLaDeMarta();
      await barra.cerrarCaja(caja, efectivoContado: 20000, diferencia: 0, quien: 'Marta');
      expect(() => venderUnaCerveza(caja), throwsStateError);
      expect(await db.query('barra_ventas'), isEmpty);
    });

    group('una venta que no cierra no se arma', () {
      VentaBarra armar({
        List<RenglonVenta>? renglones,
        MedioBarra medio = MedioBarra.efectivo,
        double efectivo = 7000,
        double transferencia = 0,
        double? recibe,
        double recargo = 0,
      }) =>
          VentaBarra.nueva(
            cajaBarraId: 'c',
            eventoId: _evento,
            numero: 1,
            renglones: renglones ?? [renglon('Cerveza', 3500, 2)],
            medio: medio,
            efectivo: efectivo,
            transferencia: transferencia,
            recibe: recibe,
            recargo: recargo,
            ahora: reloj,
          );

      test('sin renglones, o con una cantidad en cero', () {
        expect(() => armar(renglones: []), throwsArgumentError);
        expect(() => armar(renglones: [renglon('Agua', 1000, 0)]), throwsArgumentError);
      });

      test('si lo cobrado no da el total', () {
        expect(() => armar(efectivo: 6000), throwsArgumentError);
        expect(() => armar(medio: MedioBarra.mixto, efectivo: 5000, transferencia: 1000),
            throwsArgumentError);
      });

      test('una transferencia se arma sin comprobante: quien cobra la ve en el posnet', () {
        expect(armar(medio: MedioBarra.transferencia, efectivo: 0, transferencia: 7000).total, 7000);
      });

      test('el recargo: va con transferencia, y lo cobrado da el total más el recargo', () {
        final v = armar(medio: MedioBarra.transferencia, efectivo: 0, transferencia: 7350, recargo: 350);
        expect(v.total, 7000);
        expect(v.cobrado, 7350);
        expect(() => armar(recargo: 350, efectivo: 7350), throwsArgumentError,
            reason: 'en efectivo no hay recargo');
        expect(() => armar(medio: MedioBarra.transferencia, efectivo: 0, transferencia: 7000, recargo: 350),
            throwsArgumentError, reason: 'lo transferido no trae el recargo');
        expect(() => armar(medio: MedioBarra.transferencia, efectivo: 0, transferencia: 6650, recargo: -350),
            throwsArgumentError);
      });

      test('un mixto con una sola parte, o un medio que no corresponde', () {
        expect(() => armar(medio: MedioBarra.mixto, efectivo: 7000, transferencia: 0), throwsArgumentError);
        expect(() => armar(medio: MedioBarra.efectivo, efectivo: 3500, transferencia: 3500),
            throwsArgumentError);
        expect(() => armar(medio: MedioBarra.otro), throwsArgumentError);
      });

      test('si recibe menos que el efectivo', () {
        expect(() => armar(recibe: 5000), throwsArgumentError);
      });

      test('los centavos no la traban: 3 x 1.333,33 da 3.999,99', () {
        final v = armar(renglones: [renglon('Algo', 1333.33, 3)], efectivo: 3999.99);
        expect(v.total, 3999.99);
      });
    });

    test('cuántas ventas esperan subir: las de la cola', () async {
      final caja = await abrirLaDeMarta();
      expect(await barra.ventasSinSubir(), 0);
      final a = await venderUnaCerveza(caja);
      await venderUnaCerveza(caja);
      expect(await barra.ventasSinSubir(), 2);
      await db.delete('_sync_queue', where: 'registro_id = ?', whereArgs: [a.id]);
      expect(await barra.ventasSinSubir(), 1);
    });

    test('unos renglones ilegibles no frenan la lista: la venta queda con sus montos', () {
      final v = VentaBarra.fromMap({
        'id': 'v',
        'caja_barra_id': 'c',
        'evento_id': _evento,
        'numero': 4,
        'renglones': '{roto',
        'total': '7000',
        'medio': 'tarjeta',
        'efectivo': 7000,
        'created_at': '',
        'updated_at': '',
      });
      expect(v.renglones, isEmpty);
      expect(v.total, 7000);
      expect(v.medio, MedioBarra.otro, reason: 'un medio de una versión más nueva');
    });
  });

  group('anular', () {
    test('anular agrega una fila y no toca la venta', () async {
      final venta = await venderUnaCerveza(await abrirLaDeMarta());
      final ventaAntes = (await db.query('barra_ventas')).single;
      reloj = reloj.add(const Duration(minutes: 10));
      final a = await barra.anular(venta, motivo: 'se cobró dos veces', quien: 'Jefe');
      expect(a.id, UuidUtils.barraAnulacionId(venta.id));
      expect(a.ventaId, venta.id);
      expect(a.cajaBarraId, venta.cajaBarraId);
      expect(a.eventoId, _evento);
      expect((await db.query('barra_ventas')).single, ventaAntes, reason: 'la venta no se toca');
      expect((await encolado('barra_anulaciones')).single['registro_id'], a.id);
      expect([for (final x in await barra.anulaciones(_evento)) x.ventaId], [venta.id]);
      expect(await barra.anulacionesDeLaCaja(venta.cajaBarraId), hasLength(1));
    });

    test('anular dos veces la misma venta deja una sola anulación, la primera', () async {
      final venta = await venderUnaCerveza(await abrirLaDeMarta());
      await barra.anular(venta, motivo: 'primera', quien: 'Jefe');
      final otra = await barra.anular(venta, motivo: 'segunda', quien: 'Jefe');
      expect(otra.motivo, 'primera');
      expect(await db.query('barra_anulaciones'), hasLength(1));
    });

    test('sin motivo no se anula', () async {
      final venta = await venderUnaCerveza(await abrirLaDeMarta());
      expect(() => barra.anular(venta, motivo: '  ', quien: 'Jefe'), throwsArgumentError);
      expect(await db.query('barra_anulaciones'), isEmpty);
    });

    test('la cajera también anula, desde su caja: la misma fila, con quién y el equipo', () async {
      final venta = await venderUnaCerveza(await abrirLaDeMarta());
      final BarraDeLaCaja caja = barra;
      final a = await caja.anular(venta, motivo: 'se equivocó de bebida', quien: 'Marta');
      expect(a.id, UuidUtils.barraAnulacionId(venta.id));
      expect(a.hechoPor, 'Marta');
      expect(a.deviceId, 'tablet-1');
      expect((await encolado('barra_anulaciones')).single['registro_id'], a.id);
      expect(await caja.anulacionesDeLaCaja(venta.cajaBarraId), hasLength(1));
    });
  });

  group('los vales que salieron', () {
    test('cada papel se anota y se encola, con el equipo; la venta no se toca', () async {
      final venta = await venderUnaCerveza(await abrirLaDeMarta());
      final ventaAntes = (await db.query('barra_ventas')).single;
      final anotado = await barra.anotarVale(ValeBarra.salio(
        venta: venta,
        bebidas: const [BebidaDelVale(2, 'Cerveza lata')],
        porSeparado: false,
        hechoPor: 'Marta',
        ahora: reloj,
      ));
      expect(anotado.deviceId, 'tablet-1');
      expect(anotado.ventaId, venta.id);
      expect(anotado.cajaBarraId, venta.cajaBarraId);
      expect(anotado.eventoId, _evento);
      expect(anotado.copiaNumero, 0);
      final leido = ValeBarra.fromMap((await db.query('barra_vales')).single);
      expect(leido.bebidas, const [BebidaDelVale(2, 'Cerveza lata')]);
      expect(leido.porSeparado, isFalse);
      expect(leido.numeroVale, isNull);
      expect(leido.deviceId, 'tablet-1');
      expect((await encolado('barra_vales')).single['registro_id'], anotado.id);
      expect((await db.query('barra_ventas')).single, ventaAntes, reason: 'la venta no se toca');
    });

    test('la copia es otra fila: el original queda como salió', () async {
      final venta = await venderUnaCerveza(await abrirLaDeMarta());
      await barra.anotarVale(ValeBarra.salio(
        venta: venta,
        bebidas: const [BebidaDelVale(1, 'Cerveza lata')],
        porSeparado: true,
        numeroVale: 1,
        ahora: reloj,
      ));
      reloj = reloj.add(const Duration(minutes: 5));
      await barra.anotarVale(ValeBarra.salio(
        venta: venta,
        bebidas: const [BebidaDelVale(1, 'Cerveza lata')],
        porSeparado: true,
        numeroVale: 1,
        copiaNumero: 1,
        motivo: 'se le mojó',
        hechoPor: 'Marta',
        ahora: reloj,
      ));
      final vales = await barra.valesDeLaCaja(venta.cajaBarraId);
      expect([for (final v in vales) v.copiaNumero], [0, 1]);
      expect(vales.last.motivo, 'se le mojó');
      expect(vales.first.motivo, isNull);
      expect(await barra.vales(_evento), hasLength(2));
      expect(await barra.vales(_otraFiesta), isEmpty);
    });

    test('un vale que no cierra no se arma', () async {
      final venta = await venderUnaCerveza(await abrirLaDeMarta());
      ValeBarra armar({
        List<BebidaDelVale> bebidas = const [BebidaDelVale(1, 'Agua')],
        int? numeroVale,
        int copiaNumero = 0,
        String? motivo,
      }) =>
          ValeBarra.salio(
            venta: venta,
            bebidas: bebidas,
            porSeparado: false,
            numeroVale: numeroVale,
            copiaNumero: copiaNumero,
            motivo: motivo,
            ahora: reloj,
          );
      expect(() => armar(bebidas: const []), throwsArgumentError);
      expect(() => armar(bebidas: const [BebidaDelVale(0, 'Agua')]), throwsArgumentError);
      expect(() => armar(numeroVale: 0), throwsArgumentError);
      expect(() => armar(copiaNumero: 1), throwsArgumentError, reason: 'una copia lleva motivo');
      expect(() => armar(copiaNumero: 1, motivo: '  '), throwsArgumentError);
      expect(armar(motivo: 'no va').motivo, isNull, reason: 'el original no lleva motivo');
      expect(armar(copiaNumero: 2, motivo: ' perdió el papel ').motivo, 'perdió el papel');
    });

    test('unas bebidas ilegibles no frenan la lista', () {
      final v = ValeBarra.fromMap({
        'id': 'x',
        'venta_id': 'v',
        'caja_barra_id': 'c',
        'evento_id': _evento,
        'bebidas': '{roto',
        'por_separado': 1,
        'copia_numero': '1',
        'created_at': '',
        'updated_at': '',
      });
      expect(v.bebidas, isEmpty);
      expect(v.porSeparado, isTrue);
      expect(v.copiaNumero, 1);
      expect(v.esCopia, isTrue);
    });
  });

  test('lo de la fiesta: todas las cajas y todas las ventas, también las de otro equipo', () async {
    final marta = await abrirLaDeMarta();
    await venderUnaCerveza(marta);
    equipo = 'tablet-2';
    final juan = await barra.abrirCaja(eventoId: _evento, operadorId: _juan, operadorNombre: 'Juan', numeroCaja: 3);
    await venderUnaCerveza(juan);
    expect([for (final c in await barra.cajas(_evento)) c.numeroCaja], [2, 3]);
    expect(await barra.ventas(_evento), hasLength(2));
    expect(await barra.ventas(_otraFiesta), isEmpty);
  });

  test('una base sin las tablas (que no migró) no tira al leer', () async {
    final tmp = await Directory.systemTemp.createTemp('barra_sin_tablas_');
    final sinTablas = await databaseFactoryFfi.openDatabase('${tmp.path}${Platform.pathSeparator}data.db');
    final vieja = BarraLocal(abrir: () async => sinTablas, equipo: () async => 'x');
    expect(await vieja.productos(), isEmpty);
    expect(await vieja.precios(_evento), isEmpty);
    expect(await vieja.cajas(_evento), isEmpty);
    expect(await vieja.ventas(_evento), isEmpty);
    expect(await vieja.anulaciones(_evento), isEmpty);
    expect(await vieja.vales(_evento), isEmpty);
    expect(await vieja.cajaAbierta(eventoId: _evento, operadorId: _marta), isNull);
    await sinTablas.close();
    await tmp.delete(recursive: true);
  });
}
