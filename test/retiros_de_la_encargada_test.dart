import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/central/filas_de_la_red.dart';
import 'package:arguello_events/features/barra/central/llave_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_local.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/modelo_ticket.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/widgets/ok_del_cierre.dart';

import 'helpers/barra_en_memoria.dart';

/// **La encargada saca efectivo y da cambio** (`barra_caja_movimientos`, v84; respuestas
/// del usuario del 27-nov-2026): desde su sesión, en cualquier caja (también la suya),
/// siempre con motivo. Nunca la cajera ni el repositor, ni con el PIN de la encargada en
/// la tablet de la cajera. Sobre una caja cerrada no se anota. Cruza por la red del salón
/// **antes que el OK**, así la caja de la cajera cierra con la diferencia que es.
const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _marta = 'a0000000-0000-4000-8000-000000000001';

MovimientoDeCaja _retiro(CajaBarra caja, double monto, {String motivo = 'Mucho efectivo'}) => MovimientoDeCaja.nuevo(
      eventoId: caja.eventoId,
      cajaBarraId: caja.id,
      tipo: TipoMovimientoDeCaja.retiro,
      monto: monto,
      motivo: motivo,
      ahora: DateTime.utc(2026, 12, 5, 1),
    );

MovimientoDeCaja _cambio(CajaBarra caja, double monto) => MovimientoDeCaja.nuevo(
      eventoId: caja.eventoId,
      cajaBarraId: caja.id,
      tipo: TipoMovimientoDeCaja.cambio,
      monto: monto,
      motivo: 'Sin billetes chicos',
      ahora: DateTime.utc(2026, 12, 5, 1),
    );

Future<void> hasta(bool Function() listo, {String? que, int segundos = 6}) async {
  final limite = DateTime.now().add(Duration(seconds: segundos));
  while (!listo()) {
    if (DateTime.now().isAfter(limite)) fail('no pasó: ${que ?? 'lo esperado'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('en la base del equipo (BarraLocal, SQLite de verdad)', () {
    sqfliteFfiInit();
    late Database db;
    late BarraLocal barra;
    late CajaBarra caja;

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
      await LocalDatabase.crearTablasV79(db);
      await LocalDatabase.crearTablasV83(db);
      await LocalDatabase.crearTablasV84(db);
      barra = BarraLocal(
        abrir: () async => db,
        equipo: () async => 'notebook',
        reloj: () => DateTime.utc(2026, 12, 5, 1, 30),
      );
      caja = await barra.abrirCaja(
        eventoId: _fiesta,
        operadorId: _marta,
        operadorNombre: 'Marta',
        numeroCaja: 2,
        cambioInicial: 15000,
      );
    });

    tearDown(() => db.close());

    test('se guarda sellado con quién y el equipo, y se encola para subir', () async {
      final hecho = await barra.anotarMovimientoDeCaja(_retiro(caja, 25000), quien: 'Romi');
      expect(hecho.hechoPor, 'Romi');
      expect(hecho.deviceId, 'notebook');
      expect((await barra.movimientosDeCaja(_fiesta)).single.toMap(), hecho.toMap());
      expect((await barra.movimientosDeLaCaja(caja.id)).single.id, hecho.id);
      final cola = await db.query('_sync_queue', where: 'tabla = ?', whereArgs: ['barra_caja_movimientos']);
      expect(cola.single['registro_id'], hecho.id);
      expect((await barra.pendientesDeLaBarra()).otros, greaterThanOrEqualTo(1));
    });

    test('solo se agregan filas: el mismo, anotado dos veces, queda uno', () async {
      final m = _retiro(caja, 25000);
      await barra.anotarMovimientoDeCaja(m, quien: 'Romi');
      await barra.anotarMovimientoDeCaja(m, quien: 'Otro');
      final todos = await barra.movimientosDeCaja(_fiesta);
      expect(todos, hasLength(1));
      expect(todos.single.hechoPor, 'Romi');
    });

    test('sobre una caja cerrada no se anota', () async {
      await barra.cerrarCaja(caja, efectivoContado: 15000, diferencia: 0, quien: 'Marta');
      await expectLater(barra.anotarMovimientoDeCaja(_retiro(caja, 1000), quien: 'Romi'), throwsA(isA<CajaYaCerrada>()));
      expect(await barra.movimientosDeCaja(_fiesta), isEmpty);
    });

    test('lo de otra caja no entra en los de esta', () async {
      final otra = await barra.abrirCaja(
        eventoId: _fiesta,
        operadorId: 'a0000000-0000-4000-8000-000000000009',
        operadorNombre: 'Lucas',
        numeroCaja: 3,
      );
      await barra.anotarMovimientoDeCaja(_retiro(caja, 1000), quien: 'Romi');
      await barra.anotarMovimientoDeCaja(_cambio(otra, 2000), quien: 'Romi');
      expect((await barra.movimientosDeLaCaja(caja.id)).single.monto, 1000);
      expect((await barra.movimientosDeLaCaja(otra.id)).single.monto, 2000);
    });

    test('el de otro equipo, por la red del salón: se guarda sin encolar y se manda al que se conecta', () async {
      final deRomi = _retiro(caja, 25000).sellado(hechoPor: 'Romi', deviceId: 'tablet-de-romi', ahora: DateTime.utc(2026, 12, 5, 1));
      expect(await barra.guardarDeOtroEquipo('barra_caja_movimientos', deRomi.toMap()), isTrue);
      expect(await barra.guardarDeOtroEquipo('barra_caja_movimientos', deRomi.toMap()), isFalse, reason: 'igual, no cambia nada');
      expect(await db.query('_sync_queue', where: 'tabla = ?', whereArgs: ['barra_caja_movimientos']), isEmpty);
      final fiesta = await barra.filasDeLaFiesta(_fiesta);
      expect(fiesta['barra_caja_movimientos']!.single['id'], deRomi.id);
      expect(await barra.filaDeLaRed('barra_caja_movimientos', deRomi.id), isNotNull);
    });
  });

  group('la segunda llave (BarraConLaRed)', () {
    late BarraEnMemoria b;
    late CajaBarra caja;
    final salieron = <String>[];

    setUp(() async {
      b = BarraEnMemoria()..equipo = 'tablet-de-marta';
      caja = await b.abrirCaja(eventoId: _fiesta, operadorId: _marta, operadorNombre: 'Marta', numeroCaja: 2);
      salieron.clear();
    });

    BarraConLaRed con(RolEnLaBarra? rol) {
      final aviso = AvisoALaRed()..salida = (tabla, id) async => salieron.add('$tabla $id');
      return BarraConLaRed(caja: b, jefe: b, red: b, aviso: aviso, rolDeQuienUsa: () => rol);
    }

    for (final rol in [RolEnLaBarra.cajera, RolEnLaBarra.repositor, null]) {
      test('${rol?.name ?? 'nadie de la barra'} no saca efectivo ni da cambio, ni en su propia caja', () async {
        await expectLater(
          con(rol).anotarMovimientoDeCaja(_retiro(caja, 1000), quien: 'Marta'),
          throwsA(isA<NoLeTocaEnLaBarra>()),
        );
        expect(b.movimientosDeCajaGuardados, isEmpty);
        expect(salieron, isEmpty);
      });
    }

    for (final rol in [RolEnLaBarra.encargada, RolEnLaBarra.jefe]) {
      test('${rol.name}: se guarda y sale a la red del salón', () async {
        final hecho = await con(rol).anotarMovimientoDeCaja(_retiro(caja, 1000), quien: 'Romi');
        expect(b.movimientosDeCajaGuardados.single.id, hecho.id);
        expect(salieron, ['barra_caja_movimientos ${hecho.id}']);
      });
    }

    test('la encargada también en su propia caja (respuesta del 27-nov)', () async {
      final suya = await b.abrirCaja(eventoId: _fiesta, operadorId: 'romi', operadorNombre: 'Romi', numeroCaja: 3);
      await con(RolEnLaBarra.encargada).anotarMovimientoDeCaja(_retiro(suya, 5000), quien: 'Romi');
      expect(b.movimientosDeCajaGuardados.single.cajaBarraId, suya.id);
    });
  });

  group('lo que acepta la central (ReglasDeLaBarra.porQueNoSeGuarda)', () {
    final caja = CajaBarra.abrir(
      eventoId: _fiesta,
      operadorId: _marta,
      operadorNombre: 'Marta',
      numeroCaja: 2,
      ahora: DateTime.utc(2026, 12, 4, 23),
    ).sellada(hechoPor: 'Marta', deviceId: 'tablet-de-marta', ahora: DateTime.utc(2026, 12, 4, 23));
    final cerrada = caja.cerrada(efectivoContado: 0, diferencia: 0, ahora: DateTime.utc(2026, 12, 5, 4));

    String? porQueNo(RolEnLaBarra rol, String equipo, {CajaBarra? de, Map<String, Object?>? yaEsta, String? operadorId}) {
      final fila = _retiro(caja, 1000).sellado(hechoPor: 'X', deviceId: equipo, ahora: DateTime.utc(2026, 12, 5, 1)).toMap();
      return ReglasDeLaBarra.porQueNoSeGuarda(
        tabla: 'barra_caja_movimientos',
        fila: fila,
        rol: rol,
        equipo: equipo,
        operadorId: operadorId,
        yaEsta: yaEsta,
        caja: de,
        // Aunque la firma sea de una encargada: en la sesión de la cajera no vale.
        hechoPorUnaEncargada: true,
      );
    }

    test('la encargada, desde su aparato, en la caja de otra y en la suya', () {
      expect(porQueNo(RolEnLaBarra.encargada, 'tablet-de-romi', de: caja), isNull);
      expect(porQueNo(RolEnLaBarra.encargada, 'tablet-de-marta', de: caja, operadorId: _marta), isNull);
    });

    test('la cajera no, ni con la firma de la encargada en su tablet', () {
      expect(porQueNo(RolEnLaBarra.cajera, 'tablet-de-marta', de: caja, operadorId: _marta),
          'La plata de las cajas la maneja la encargada');
    });

    test('el repositor no', () {
      expect(porQueNo(RolEnLaBarra.repositor, 'celu-del-repo', de: caja), isNotNull);
    });

    test('no sobre una caja cerrada, ni sin saber de qué caja es, ni cambiando uno que ya está', () {
      expect(porQueNo(RolEnLaBarra.encargada, 'tablet-de-romi', de: cerrada), 'La caja ya cerró');
      expect(porQueNo(RolEnLaBarra.encargada, 'tablet-de-romi'), 'No se sabe de qué caja es');
      expect(porQueNo(RolEnLaBarra.encargada, 'tablet-de-romi', de: caja, yaEsta: const {'id': 'x'}),
          'Un retiro no se cambia');
    });

    test('van antes que los pasos del cierre: la tablet tiene el retiro antes que el OK', () {
      expect(tablasDeLaRed, contains('barra_caja_movimientos'));
      expect(tablasDeLaRed.indexOf('barra_caja_movimientos'), lessThan(tablasDeLaRed.indexOf('barra_cierres')));
    });
  });

  test('la tablet que espera el OK baja los retiros antes que los pasos del cierre', () {
    final fuente = File('lib/core/services/sync_engine.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final desde = fuente.indexOf('Future<bool> bajarCierresDeLaBarra()');
    final cuerpo = fuente.substring(desde, fuente.indexOf('\n  }\n', desde));
    final retiros = cuerpo.indexOf("_pullTable(db, 'barra_caja_movimientos'");
    final cierres = cuerpo.indexOf("_pullTable(db, 'barra_cierres'");
    expect(retiros, greaterThan(0), reason: 'baja los retiros');
    expect(cierres, greaterThan(retiros), reason: 'y después el OK');
  });

  group('la cuenta: LAS CAJAS y el cartel del OK', () {
    test('LAS CAJAS: cada caja con lo suyo, y los totales de lo que se sacó y se dio', () async {
      final b = BarraEnMemoria();
      final c1 = await b.abrirCaja(eventoId: _fiesta, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1, cambioInicial: 10000);
      final c2 = await b.abrirCaja(eventoId: _fiesta, operadorId: 'l', operadorNombre: 'Lucas', numeroCaja: 2, cambioInicial: 5000);
      final r = ResumenDeCajas.de(
        cajas: [c1, c2],
        ventas: const [],
        anulaciones: const [],
        movimientos: [_retiro(c1, 4000), _cambio(c2, 2000)],
      );
      expect(r.cajas[0].cuentas.efectivoEsperado, 6000);
      expect(r.cajas[1].cuentas.efectivoEsperado, 7000);
      expect((r.retirado, r.cambioAgregado), (4000, 2000));
      expect(r.deLaFiesta!.efectivoEsperado, 13000);
    });

    test('si un retiro llegó después del cierre, la tarjeta lo puede decir sin tocar lo anotado', () async {
      final b = BarraEnMemoria();
      final abierta = await b.abrirCaja(eventoId: _fiesta, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1, cambioInicial: 10000);
      // La tablet cerró sin saber del retiro: contó 6.000 y anotó "faltan 4.000".
      final cerrada = await b.cerrarCaja(abierta, efectivoContado: 6000, diferencia: -4000, quien: 'Marta');
      final sinRetiro = ResumenDeCajas.de(cajas: [cerrada], ventas: const [], anulaciones: const []);
      expect(sinRetiro.cajas.single.cambioDespuesDelCierre, isFalse);
      final conRetiro = ResumenDeCajas.de(
        cajas: [cerrada],
        ventas: const [],
        anulaciones: const [],
        movimientos: [_retiro(abierta, 4000)],
      );
      final caja = conRetiro.cajas.single;
      expect(caja.diferencia, -4000, reason: 'lo anotado al cerrar no se toca');
      expect(caja.diferenciaConTodo, 0);
      expect(caja.cambioDespuesDelCierre, isTrue);
    });

    test('LAS CAJAS lee los retiros de la barra de este equipo', () async {
      final b = BarraEnMemoria();
      final caja = await b.abrirCaja(eventoId: _fiesta, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1, cambioInicial: 15000);
      await b.anotarMovimientoDeCaja(_retiro(caja, 5000), quien: 'Romi');
      final c = ProviderContainer(overrides: [barraDelJefeProvider.overrideWithValue(b)]);
      addTearDown(c.dispose);
      final fiesta = await c.read(cajasDelJefeProvider(_fiesta).future);
      final noche = fiesta.delDia(DiaDeOperacion.deLaCaja(caja));
      expect(noche.resumen.cajas.single.cuentas.efectivoEsperado, 10000);
      expect(noche.resumen.retirado, 5000);
    });

    test('el papel del cierre dice lo que dio y lo que sacó la encargada, solo si hubo', () async {
      final b = BarraEnMemoria();
      final caja = await b.abrirCaja(eventoId: _fiesta, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1, cambioInicial: 15000);
      List<String> renglones(Iterable<MovimientoDeCaja> movs) => [
            for (final r in ModeloTicket.deCierre(caja, CierreDeBarra.de(caja, const [], const [], movimientos: movs), fiesta: 'X')
                .whereType<RenglonTicket>())
              '${r.izquierda} ${r.derecha}',
          ];
      expect(renglones(const []).where((r) => r.contains('encargada')), isEmpty);
      final con = renglones([_cambio(caja, 5000), _retiro(caja, 25000)]);
      expect(con, containsAllInOrder([
        r'Cambio inicial $ 15.000',
        r'Cambio de la encargada +$ 5.000',
        r'Sacó la encargada -$ 25.000',
        r'Efectivo esperado $ -5.000',
      ]));
    });

    test('el cartel del OK cuenta lo que sacó la encargada', () async {
      final b = BarraEnMemoria();
      final caja = await b.abrirCaja(eventoId: _fiesta, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1, cambioInicial: 15000);
      await b.vender(
        caja: caja,
        renglones: const [RenglonVenta(productoId: 'p', nombre: 'Cerveza', precio: 12000, cantidad: 1)],
        medio: MedioBarra.efectivo,
        efectivo: 12000,
        quien: 'Marta',
      );
      await b.anotarMovimientoDeCaja(_retiro(caja, 10000), quien: 'Romi');
      expect((await cuentasParaElOk(b, caja)).efectivoEsperado, 17000);
    });
  });

  group('de punta a punta, con la central de verdad (loopback)', () {
    late QuienEsQuienEnMemoria personas;
    late BarraEnMemoria notebook;
    late CentralBarra central;
    late DondeEstaLaCentral donde;
    final aCerrar = <void Function()>[];

    setUp(() async {
      personas = QuienEsQuienEnMemoria(maestro: '8642');
      notebook = BarraEnMemoria()..equipo = 'notebook';
      notebook.reloj = () => DateTime.now().toUtc();
      central = CentralBarra(
        eventoId: _fiesta,
        barra: notebook,
        quienEsQuien: personas,
        esperaDelPin: const Duration(milliseconds: 600),
      );
      final puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
      donde = DondeEstaLaCentral('127.0.0.1', puerto);
    });

    tearDown(() async {
      for (final c in aCerrar.reversed) {
        c();
      }
      aCerrar.clear();
      await central.cerrar();
    });

    ({BarraEnMemoria barra, BarraConLaRed red, ClienteDeLaCentral cliente}) aparato(
      String equipo,
      String persona,
      RolEnLaBarra rol,
    ) {
      final cred = personas.persona('op-$equipo', persona, pin: '1234', rol: rol);
      final barra = BarraEnMemoria()
        ..equipo = equipo
        ..reloj = () => DateTime.now().toUtc();
      final cliente = ClienteDeLaCentral(
        credencial: () async => cred,
        eventoId: _fiesta,
        equipo: equipo,
        nombreCaja: 'Caja · $persona',
        barra: barra,
        aMano: donde,
        latido: const Duration(milliseconds: 100),
        silencioMaximo: const Duration(seconds: 2),
        pausa: const Duration(milliseconds: 100),
      );
      final aviso = AvisoALaRed()..salida = cliente.mandar;
      final red = BarraConLaRed(caja: barra, jefe: barra, red: barra, aviso: aviso, rolDeQuienUsa: () => rol);
      cliente.arrancar();
      aCerrar.add(cliente.dispose);
      return (barra: barra, red: red, cliente: cliente);
    }

    test('la encargada saca efectivo desde su tablet y la cajera, al cerrar, lo tiene en lo que tenía que haber',
        () async {
      final marta = aparato('tablet-de-marta', 'Marta', RolEnLaBarra.cajera);
      final romi = aparato('tablet-de-romi', 'Romi', RolEnLaBarra.encargada);
      await hasta(() => marta.cliente.conectada && romi.cliente.conectada, que: 'se conectan las dos');

      final caja = await marta.red.abrirCaja(
        eventoId: _fiesta,
        operadorId: 'op-tablet-de-marta',
        operadorNombre: 'Marta',
        numeroCaja: 1,
        cambioInicial: 15000,
      );
      await marta.red.vender(
        caja: caja,
        renglones: const [RenglonVenta(productoId: 'p', nombre: 'Cerveza', precio: 12000, cantidad: 1)],
        medio: MedioBarra.efectivo,
        efectivo: 12000,
        quien: 'Marta',
      );
      await hasta(() => romi.barra.cajasGuardadas.any((c) => c.id == caja.id), que: 'la caja llega a Romi');

      final retiro = await romi.red.anotarMovimientoDeCaja(_retiro(caja, 10000), quien: 'Romi');
      await hasta(() => marta.barra.movimientosDeCajaGuardados.any((m) => m.id == retiro.id),
          que: 'el retiro llega a la tablet de Marta');
      expect(notebook.movimientosDeCajaGuardados.single.id, retiro.id, reason: 'y queda en la central');

      final ventas = await marta.barra.ventasDeLaCaja(caja.id);
      final movs = await marta.barra.movimientosDeLaCaja(caja.id);
      final cierre = CierreDeBarra.de(caja, ventas, const [], movimientos: movs);
      expect(cierre.efectivoEsperado, 17000);
      expect(cierre.diferenciaCon(17000), 0, reason: 'contó lo que había: justo');
    });

    test('lo que manda la tablet de la cajera como retiro, la central no lo guarda ni lo reparte', () async {
      final marta = aparato('tablet-de-marta', 'Marta', RolEnLaBarra.cajera);
      final romi = aparato('tablet-de-romi', 'Romi', RolEnLaBarra.encargada);
      await hasta(() => marta.cliente.conectada && romi.cliente.conectada);
      final caja = await marta.red.abrirCaja(
        eventoId: _fiesta,
        operadorId: 'op-tablet-de-marta',
        operadorNombre: 'Marta',
        numeroCaja: 1,
      );
      await hasta(() => notebook.cajasGuardadas.any((c) => c.id == caja.id));
      // Sin pasar por la segunda llave: la fila cruda, como la mandaría otra versión.
      final falso = _retiro(caja, 50000).sellado(hechoPor: 'Romi', deviceId: 'tablet-de-marta', ahora: DateTime.now());
      await marta.barra.guardarDeOtroEquipo('barra_caja_movimientos', falso.toMap());
      await marta.cliente.mandar('barra_caja_movimientos', falso.id);
      await hasta(() => marta.cliente.rechazadas.any((r) => r.id == falso.id), que: 'la central lo rechaza');
      expect(marta.cliente.rechazadas.firstWhere((r) => r.id == falso.id).motivo,
          'La plata de las cajas la maneja la encargada');
      expect(notebook.movimientosDeCajaGuardados, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(romi.barra.movimientosDeCajaGuardados, isEmpty);
    });
  });
}
