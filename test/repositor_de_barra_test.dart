// El repositor de barra (28-nov-2026, para la Técnica del 4-dic): el permiso (Barra con
// un 3), lo que le toca, y el stock por barra en la base del equipo
// (`barra_stock_barras` y `barra_stock_movimientos`, v83), con su segunda llave.
//
// La cuenta (`StockPorBarra`) tiene sus pruebas en `test/stock_por_barra_test.dart`; lo
// que acepta la central de cada rol, en `test/central_barra_permisos_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/filas_de_la_red.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/stock_por_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_local.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/services/entrada_de_operador.dart';
import 'package:arguello_events/features/caja_sesiones/services/pin_de_operador.dart';

import 'helpers/barra_en_memoria.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _nico = 'a0000000-0000-4000-8000-000000000009';
const _speed = 'p0000000-0000-4000-8000-000000000001';
final _ahora = DateTime.utc(2026, 12, 5, 1, 30);

PermisosEfectivos _conBarra(int nivel) => PermisosOperador.fromMap({
      'id': 'x',
      'operador_id': _nico,
      'cobros': 0,
      'entradas': 0,
      'barra': nivel,
      'created_at': 'a',
      'updated_at': 'a',
    }).permisos;

MovimientoDeStock _reposicion(int cantidad, {String barra = 'Barra 1', String? quien}) => MovimientoDeStock.reposicion(
      eventoId: _fiesta,
      productoId: _speed,
      barra: barra,
      cantidad: cantidad,
      hechoPor: quien,
      ahora: _ahora,
    );

StockEnLaBarra _reparto(int arranque, {String barra = 'Barra 1', int? aviso}) => StockEnLaBarra.para(
      eventoId: _fiesta,
      productoId: _speed,
      barra: barra,
      arranque: arranque,
      aviso: aviso,
      ahora: _ahora,
    );

void main() {
  group('el permiso: Barra con un 3', () {
    test('un 3 en la columna de la barra es repositor: entra por BARRA y no es cajera ni encargada', () {
      final p = _conBarra(3);
      expect(p.repositorBarra, isTrue);
      expect(p.barra, isFalse);
      expect(p.encargadaBarra, isFalse);
      expect(p.tiene(PermisoOperador.barra), isTrue, reason: 'entra por la puerta de la barra');
      expect(p.tiene(PermisoOperador.repositorBarra), isTrue);
      expect(p.tiene(PermisoOperador.encargadaBarra), isFalse);
      expect(p.lista, [PermisoOperador.barra]);
      expect(p.ninguno, isFalse);
      expect(p.nivelBarra, 3);
    });

    test('vuelve igual a la base: el 3 no se pierde al guardar', () {
      final fila = PermisosOperador.para(
        operadorId: _nico,
        permisos: const PermisosEfectivos(repositorBarra: true),
        ahora: _ahora,
      );
      expect(fila.toMap()['barra'], 3);
      expect(PermisosOperador.fromMap(fila.toMap()).permisos, fila.permisos);
    });

    test('la cajera (1) y la encargada (2) siguen como estaban', () {
      expect((_conBarra(1).barra, _conBarra(1).encargadaBarra, _conBarra(1).repositorBarra), (true, false, false));
      expect((_conBarra(2).barra, _conBarra(2).encargadaBarra, _conBarra(2).repositorBarra), (true, true, false));
      expect(_conBarra(0).tiene(PermisoOperador.barra), isFalse);
      expect(_conBarra(1).nivelBarra, 1);
      expect(_conBarra(2).nivelBarra, 2);
    });

    test('no es lo mismo que una cajera: guardar el cambio lo anota', () {
      expect(_conBarra(3), isNot(_conBarra(1)));
      expect(_conBarra(3), isNot(_conBarra(2)));
      final cambios = CambioDePermiso.entre(
        operadorId: _nico,
        antes: _conBarra(1),
        despues: _conBarra(3),
        ahora: _ahora,
      );
      expect([for (final c in cambios) (c.permiso, c.dado)], [(PermisoOperador.repositorBarra, true)]);
      final deCero = CambioDePermiso.entre(
        operadorId: _nico,
        antes: const PermisosEfectivos(),
        despues: _conBarra(3),
        ahora: _ahora,
      );
      expect({for (final c in deCero) c.permiso.clave}, {'barra', 'repositor_barra'});
    });

    test('en OPERADORES se lee "Repositor de barra"', () {
      expect(textoDePermisos(_conBarra(3)), 'Repositor de barra');
      expect(nombreDePermiso(PermisoOperador.repositorBarra), 'Repositor de barra');
    });

    test('con su PIN entra derecho a la barra; desde el navegador, no', () {
      expect(OpcionesDeEntrada.de(_conBarra(3)).directo, PermisoOperador.barra);
      final web = OpcionesDeEntrada.de(_conBarra(3), enLaWeb: true);
      expect(web.directo, isNull);
      expect(web.aviso, isNotNull);
    });

    test('la regla lo toma por repositor, y es lo primero que mira', () {
      expect(ReglasDeLaBarra.dePermisos(_conBarra(3)), RolEnLaBarra.repositor);
      expect(ReglasDeLaBarra.dePermisos(_conBarra(1)), RolEnLaBarra.cajera);
      expect(ReglasDeLaBarra.dePermisos(_conBarra(2)), RolEnLaBarra.encargada);
      expect(ReglasDeLaBarra.dePermisos(_conBarra(0)), isNull);
      // Aunque una fila rara trajera las dos cosas, es repositor: solo el stock.
      expect(
        ReglasDeLaBarra.dePermisos(const PermisosEfectivos(barra: true, encargadaBarra: true, repositorBarra: true)),
        RolEnLaBarra.repositor,
      );
    });

    test('lo que le toca: solo el stock', () {
      const r = RolEnLaBarra.repositor;
      expect(ReglasDeLaBarra.mueveElStock(r), isTrue);
      for (final (que, puede) in [
        ('abrir caja y vender', ReglasDeLaBarra.abreCajaYVende(r)),
        ('anular', ReglasDeLaBarra.anula(r)),
        ('la plata de las cajas', ReglasDeLaBarra.manejaLaPlataDeLasCajas(r)),
        ('ver la plata', ReglasDeLaBarra.veLaPlataDeTodas(r)),
        ('dar el OK', ReglasDeLaBarra.daElOk(r)),
        ('repartir el stock', ReglasDeLaBarra.reparteElStock(r)),
        ('cambiar el catálogo', ReglasDeLaBarra.cambiaCatalogoYPrecios(r)),
        ('ver el catálogo y los precios', ReglasDeLaBarra.veCatalogoYPrecios(r)),
        ('el precio de lista y la ganancia', ReglasDeLaBarra.veElCostoYLaGanancia(r)),
        ('cerrar sin pedir', ReglasDeLaBarra.cierraSinPedir(r)),
      ]) {
        expect(puede, isFalse, reason: que);
      }
      // La cajera y la encargada no mueven el stock; el jefe sí.
      expect(ReglasDeLaBarra.mueveElStock(RolEnLaBarra.cajera), isFalse);
      expect(ReglasDeLaBarra.mueveElStock(RolEnLaBarra.encargada), isFalse);
      expect(ReglasDeLaBarra.mueveElStock(RolEnLaBarra.jefe), isTrue);
    });
  });

  group('el stock por barra en la base del equipo (BarraLocal, SQLite de verdad)', () {
    sqfliteFfiInit();
    late Database db;
    var equipo = 'celu-de-nico';
    late BarraLocal barra;

    Future<List<Map<String, Object?>>> cola(String tabla) =>
        db.query('_sync_queue', where: 'tabla = ?', whereArgs: [tabla]);

    setUp(() async {
      equipo = 'celu-de-nico';
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
      await LocalDatabase.crearTablasV79(db);
      await LocalDatabase.crearTablasV83(db);
      await LocalDatabase.crearTablasV84(db);
      barra = BarraLocal(abrir: () async => db, equipo: () async => equipo, reloj: () => _ahora);
    });

    tearDown(() => db.close());

    test('el reparto del jefe se guarda con quién, el equipo y cuándo, y espera subir', () async {
      final guardado = await barra.guardarReparto(_reparto(24, aviso: 6), quien: 'Jefe');
      expect((guardado.hechoPor, guardado.deviceId), ('Jefe', 'celu-de-nico'));
      final leidos = await barra.repartos(_fiesta);
      expect((leidos.single.barra, leidos.single.arranque, leidos.single.aviso), ('Barra 1', 24, 6));
      expect(await cola('barra_stock_barras'), hasLength(1));
      expect(await barra.repartos('otra-fiesta'), isEmpty);
    });

    test('guardarlo de nuevo reemplaza la misma fila y no le cambia cuándo nació', () async {
      final primero = await barra.guardarReparto(
        _reparto(24).sellado(createdAt: '2026-12-01T00:00:00.000Z', ahora: _ahora),
        quien: 'Jefe',
      );
      // Otro arranque para la misma barra y el mismo producto: el mismo id.
      final segundo = await barra.guardarReparto(_reparto(30, aviso: 4), quien: 'Jefe');
      expect(segundo.id, primero.id);
      final leidos = await barra.repartos(_fiesta);
      expect((leidos.single.arranque, leidos.single.aviso), (30, 4));
      expect(leidos.single.createdAt, primero.createdAt);
      // Otra barra es otra fila.
      await barra.guardarReparto(_reparto(12, barra: 'Barra 2'), quien: 'Jefe');
      expect(await barra.repartos(_fiesta), hasLength(2));
    });

    test('un movimiento queda a nombre de quien usa el aparato, con su equipo, y espera subir', () async {
      final m = await barra.anotarMovimientoDeStock(_reposicion(12), quien: 'Nico');
      expect((m.hechoPor, m.deviceId), ('Nico', 'celu-de-nico'));
      final leidos = await barra.movimientosDeStock(_fiesta);
      expect((leidos.single.tipo, leidos.single.cantidad, leidos.single.hacia),
          (TipoMovimientoDeStock.reposicion, 12, 'Barra 1'));
      expect(await cola('barra_stock_movimientos'), hasLength(1));
      // Si ya traía nombre, queda ese.
      final otro = await barra.anotarMovimientoDeStock(_reposicion(6, quien: 'el jefe'), quien: 'Nico');
      expect(otro.hechoPor, 'el jefe');
    });

    test('solo se agregan filas: el mismo, anotado dos veces, queda como estaba', () async {
      final m = _reposicion(12);
      await barra.anotarMovimientoDeStock(m, quien: 'Nico');
      final otraVez = await barra.anotarMovimientoDeStock(m, quien: 'Otro');
      expect(otraVez.hechoPor, 'Nico');
      expect(await barra.movimientosDeStock(_fiesta), hasLength(1));
      expect(await cola('barra_stock_movimientos'), hasLength(1));
    });

    test('"voy en camino" cuenta lo que YA llevó este equipo ahí, y solo este equipo', () async {
      // Este equipo repuso dos veces en la Barra 1 y una en la Barra 2; otro equipo, una.
      await barra.anotarMovimientoDeStock(_reposicion(6), quien: 'Nico');
      await barra.anotarMovimientoDeStock(_reposicion(6), quien: 'Nico');
      await barra.anotarMovimientoDeStock(_reposicion(6, barra: 'Barra 2'), quien: 'Nico');
      equipo = 'otro-celu';
      await barra.anotarMovimientoDeStock(_reposicion(6), quien: 'Otro');
      equipo = 'celu-de-nico';

      final aviso = await barra.avisarQueVa(eventoId: _fiesta, productoId: _speed, barra: 'Barra 1', quien: 'Nico');
      expect(aviso.tipo, TipoMovimientoDeStock.enCamino);
      expect((aviso.hacia, aviso.avisosPrevios, aviso.hechoPor, aviso.deviceId), ('Barra 1', 2, 'Nico', 'celu-de-nico'));

      // El aviso sigue en pie hasta que ESTE equipo reponga ahí.
      StockPorBarra cuenta(List<MovimientoDeStock> movimientos) => StockPorBarra.de(
            eventoId: _fiesta,
            precios: [
              PrecioBarra.para(eventoId: _fiesta, productoId: _speed, precio: 5000, stockInicial: 96, ahora: _ahora),
            ],
            repartos: [_reparto(24), _reparto(24, barra: 'Barra 2')],
            movimientos: movimientos,
            ventas: const [],
            cajas: const [],
            anulaciones: const [],
          );
      expect(cuenta(await barra.movimientosDeStock(_fiesta)).enCaminoDe('Barra 1', _speed), isNotNull);
      await barra.anotarMovimientoDeStock(_reposicion(12), quien: 'Nico');
      expect(cuenta(await barra.movimientosDeStock(_fiesta)).enCaminoDe('Barra 1', _speed), isNull,
          reason: 'repuso: el aviso se cumple solo');
    });

    test('el reparto y los movimientos viajan por la red del salón', () async {
      await barra.guardarReparto(_reparto(24), quien: 'Jefe');
      await barra.anotarMovimientoDeStock(_reposicion(12), quien: 'Nico');
      final filas = await barra.filasDeLaFiesta(_fiesta);
      expect(filas['barra_stock_barras'], hasLength(1));
      expect(filas['barra_stock_movimientos'], hasLength(1));
      expect(tablasDeLaRed, containsAll(['barra_stock_barras', 'barra_stock_movimientos']));
    });

    test('lo que llega de otro equipo por la red se guarda sin la cola: lo sube quien lo hizo', () async {
      final deOtro = _reposicion(12).selladoPor('Nico').conEquipo('otro-celu');
      expect(await barra.guardarDeOtroEquipo('barra_stock_movimientos', deOtro.toMap()), isTrue);
      expect(await barra.movimientosDeStock(_fiesta), hasLength(1));
      expect(await cola('barra_stock_movimientos'), isEmpty);
    });
  });

  group('la segunda llave (BarraConLaRed)', () {
    late BarraEnMemoria base;
    late RolEnLaBarra? rol;
    late BarraConLaRed conLlave;
    late List<String> salio;

    setUp(() {
      base = BarraEnMemoria()..equipo = 'celu-de-nico';
      rol = RolEnLaBarra.repositor;
      salio = [];
      final aviso = AvisoALaRed()..salida = (tabla, id) async => salio.add(tabla);
      conLlave = BarraConLaRed(caja: base, jefe: base, red: base, aviso: aviso, rolDeQuienUsa: () => rol);
    });

    test('el repositor anota el stock, y sale a la red del salón', () async {
      await conLlave.anotarMovimientoDeStock(_reposicion(12), quien: 'Nico');
      await conLlave.avisarQueVa(eventoId: _fiesta, productoId: _speed, barra: 'Barra 2', quien: 'Nico');
      expect(base.movimientosGuardados, hasLength(2));
      expect(salio, ['barra_stock_movimientos', 'barra_stock_movimientos']);
    });

    test('la cajera y la encargada no mueven el stock; el jefe sí', () async {
      for (final r in [RolEnLaBarra.cajera, RolEnLaBarra.encargada, null]) {
        rol = r;
        await expectLater(
          conLlave.anotarMovimientoDeStock(_reposicion(12), quien: 'X'),
          throwsA(isA<NoLeTocaEnLaBarra>().having((e) => e.motivo, 'motivo', 'El stock lo mueve el repositor')),
          reason: '$r',
        );
        await expectLater(
          conLlave.avisarQueVa(eventoId: _fiesta, productoId: _speed, barra: 'Barra 1', quien: 'X'),
          throwsA(isA<NoLeTocaEnLaBarra>()),
          reason: '$r',
        );
      }
      expect(base.movimientosGuardados, isEmpty);
      expect(salio, isEmpty);
      rol = RolEnLaBarra.jefe;
      await conLlave.anotarMovimientoDeStock(_reposicion(12), quien: 'Jefe');
      expect(base.movimientosGuardados, hasLength(1));
    });

    test('el reparto lo guarda solo el jefe, y sale a la red', () async {
      for (final r in [RolEnLaBarra.repositor, RolEnLaBarra.cajera, RolEnLaBarra.encargada, null]) {
        rol = r;
        await expectLater(
          conLlave.guardarReparto(_reparto(24), quien: 'X'),
          throwsA(isA<NoLeTocaEnLaBarra>().having((e) => e.motivo, 'motivo', 'El reparto lo hace el jefe')),
          reason: '$r',
        );
      }
      expect(base.repartosGuardados, isEmpty);
      rol = RolEnLaBarra.jefe;
      await conLlave.guardarReparto(_reparto(24), quien: 'Jefe');
      expect(base.repartosGuardados, hasLength(1));
      expect(salio, ['barra_stock_barras']);
    });

    test('el repositor no abre caja, no vende, no anula ni toca la plata', () async {
      await expectLater(
        conLlave.abrirCaja(eventoId: _fiesta, operadorId: _nico, operadorNombre: 'Nico', numeroCaja: 1),
        throwsA(isA<NoLeTocaEnLaBarra>()),
      );
      rol = RolEnLaBarra.cajera;
      final caja = await conLlave.abrirCaja(eventoId: _fiesta, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
      final venta = await conLlave.vender(
        caja: caja,
        renglones: const [RenglonVenta(productoId: _speed, nombre: 'Speed', precio: 5000, cantidad: 1)],
        medio: MedioBarra.efectivo,
        efectivo: 5000,
        quien: 'Marta',
      );
      rol = RolEnLaBarra.repositor;
      await expectLater(
        conLlave.vender(
          caja: caja,
          renglones: const [RenglonVenta(productoId: _speed, nombre: 'Speed', precio: 5000, cantidad: 1)],
          medio: MedioBarra.efectivo,
          efectivo: 5000,
          quien: 'Nico',
        ),
        throwsA(isA<NoLeTocaEnLaBarra>()),
      );
      await expectLater(conLlave.anular(venta, motivo: 'x', quien: 'Nico'), throwsA(isA<NoLeTocaEnLaBarra>()));
      await expectLater(
        conLlave.anotarMovimientoDeCaja(
          MovimientoDeCaja.nuevo(
            eventoId: _fiesta,
            cajaBarraId: caja.id,
            tipo: TipoMovimientoDeCaja.retiro,
            monto: 1000,
            motivo: 'x',
            ahora: _ahora,
          ),
          quien: 'Nico',
        ),
        throwsA(isA<NoLeTocaEnLaBarra>()),
      );
      expect(await conLlave.costos(_fiesta), isEmpty, reason: 'ni lee el precio de lista');
    });

    test('leer el stock no pide nada: lo leen todos (VENDER dice cuántas quedan)', () async {
      rol = RolEnLaBarra.jefe;
      await conLlave.guardarReparto(_reparto(24), quien: 'Jefe');
      await conLlave.anotarMovimientoDeStock(_reposicion(12), quien: 'Jefe');
      for (final r in [RolEnLaBarra.cajera, RolEnLaBarra.encargada, RolEnLaBarra.repositor]) {
        rol = r;
        expect(await conLlave.repartos(_fiesta), hasLength(1), reason: '$r');
        expect(await conLlave.movimientosDeStock(_fiesta), hasLength(1), reason: '$r');
      }
    });
  });
}
