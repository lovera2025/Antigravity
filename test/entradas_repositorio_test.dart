// La venta de entradas en la base del equipo (`EntradasLocal`, v80): el precio
// de la fiesta, la caja, las ventas con su número, anular y "Pago verificado".
// Y las entradas para rendir (v82): dar, rendir, no volvieron y anular.
// Sobre una base temporal y sin red.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/entradas/cuentas/linea_de_subida.dart';
import 'package:arguello_events/features/entradas/datos/entradas_local.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/models/entradas_retiro.dart' show TramoTalonario;

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
      // La línea de VENDER lo cuenta como un cambio, no como una venta
      // (20-nov-2026: "Todo subido" tiene que ser que no queda nada).
      expect(await entradas.cambiosSinSubir(), 1);
      expect(await entradas.ventasSinSubir(), 0);
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
      expect(await entradas.cambiosSinSubir(), 1, reason: 'la caja que se abrió');
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

  // ── Las entradas para rendir (v82, 20-nov-2026) ──────────────────────────────
  //
  // Reglas 36, 38, 40, 41, 54 y 55 de `docs/SPEC_entradas_para_rendir_2026-11-20.md`.
  group('las entradas para rendir', () {
    late CajaEntradas caja;

    setUp(() async {
      caja = await entradas.abrirCaja(
        eventoId: _fiesta,
        operadorId: _f1,
        operadorNombre: 'Carla',
      );
    });

    Future<MovimientoParaRendir> dar({
      int cantidad = 20,
      List<TramoTalonario> numeros = const [TramoTalonario(1201, 1220)],
      double precio = 8000,
      String nombrePrecio = 'Entrada anticipada',
      String? familia,
    }) =>
        entradas.darParaRendir(
          eventoId: _fiesta,
          personaNombre: '  Juan   Pérez ',
          personaContacto: '3794 000000',
          contratoAlumnoId: familia,
          cantidad: cantidad,
          numeros: numeros,
          precio: precio,
          nombrePrecio: nombrePrecio,
          quien: 'Jefe',
        );

    Future<RendicionDeEntradas> rendir(
      MovimientoParaRendir bloque, {
      int vendidas = 0,
      List<TramoTalonario> devueltos = const [],
      double? precio,
      EntradasLocal? desde,
    }) {
      final plata = vendidas * (precio ?? 8000.0);
      return (desde ?? entradas).rendir(
        caja: vendidas > 0 ? caja : null,
        bloque: bloque,
        vendidas: vendidas,
        devueltas: devueltos.fold(0, (s, t) => s + t.cantidad),
        numerosDevueltos: devueltos,
        medio: MedioBarra.efectivo,
        efectivo: plata,
        quien: 'Carla',
      );
    }

    Future<List<Map<String, Object?>>> filas(String tabla) async {
      final db = await LocalDatabase.instance;
      return db.query(tabla);
    }

    /// Todo lo de la venta y de las entradas para rendir, con su cola: para ver
    /// que algo que falló no dejó nada a medias.
    Future<String> foto() async {
      final db = await LocalDatabase.instance;
      return jsonEncode({
        for (final t in [
          'entradas_ventas',
          EntradasLocal.tablaParaRendir,
          '_sync_queue',
        ])
          t: await db.query(t, orderBy: 'rowid'),
      });
    }

    test('dar guarda el bloque con su precio fijo, sin pulseras, y va a la cola',
        () async {
      final bloque = await dar(familia: _familia);
      expect(bloque.esDio, isTrue);
      expect(bloque.bloqueId, bloque.id);
      expect(bloque.personaNombre, 'Juan Pérez', reason: 'sin espacios de más');
      expect(bloque.contratoAlumnoId, _familia);
      expect(bloque.precio, 8000);
      expect(bloque.nombrePrecio, 'Entrada anticipada');
      expect(bloque.conPulseras, isFalse, reason: 'la pulsera no se vende');
      expect(bloque.hechoPor, 'Jefe');
      expect(bloque.deviceId, 'pc-1');
      final enLaBase = (await filas(EntradasLocal.tablaParaRendir)).single;
      expect(MovimientoParaRendir.fromMap(enLaBase).toMap(), bloque.toMap());
      expect(enLaBase['venta_id'], isNull, reason: 'los vínculos van en null, nunca en ""');
      expect(enLaBase['anula_id'], isNull);
      final enCola = (await cola(EntradasLocal.tablaParaRendir)).single;
      expect(enCola['registro_id'], bloque.id);
      expect(
        (jsonDecode(enCola['payload'] as String) as Map).keys.toSet(),
        enLaBase.keys.toSet(),
      );
      expect((await entradas.paraRendir(_fiesta)).single.id, bloque.id);
      expect(await entradas.paraRendir(_otraFiesta), isEmpty);
    });

    test('dar sin números, con la cantidad que no da o sin precio, no guarda nada',
        () async {
      await expectLater(dar(numeros: const []), throwsArgumentError);
      await expectLater(
        dar(cantidad: 20, numeros: const [TramoTalonario(1201, 1210)]),
        throwsArgumentError,
      );
      await expectLater(dar(precio: 0), throwsArgumentError);
      expect(await filas(EntradasLocal.tablaParaRendir), isEmpty);
      expect(await cola(EntradasLocal.tablaParaRendir), isEmpty);
    });

    // Trampa de CLAUDE.md y SPEC §3: en la nube los vínculos son uuid, y un ''
    // traba la fila en la cola para siempre. Lo que llega vacío de la pantalla
    // (el contacto en blanco de "Alguien de afuera", un alumno sin elegir) tiene
    // que quedar NULL en la base y en lo que sube.
    group('los vínculos van en null, nunca en ""', () {
      const vinculos = [
        'contrato_alumno_id',
        'persona_contacto',
        'venta_id',
        'caja_entradas_id',
        'anula_id',
      ];

      test('dar a alguien de afuera con los vínculos vacíos guarda NULL, en la base y en la cola',
          () async {
        final bloque = await entradas.darParaRendir(
          eventoId: _fiesta,
          personaNombre: 'Ana Gómez',
          personaContacto: '  ',
          contratoAlumnoId: '',
          cantidad: 2,
          numeros: const [TramoTalonario(1, 2)],
          precio: 8000,
          nombrePrecio: 'Entrada anticipada',
          nota: ' ',
          quien: 'Jefe',
        );
        expect(bloque.contratoAlumnoId, isNull);
        expect(bloque.personaContacto, isNull);
        expect(bloque.nota, isNull);
        final enLaBase = (await filas(EntradasLocal.tablaParaRendir)).single;
        final payload = jsonDecode(
          (await cola(EntradasLocal.tablaParaRendir)).single['payload'] as String,
        ) as Map<String, dynamic>;
        for (final columna in [...vinculos, 'nota', 'motivo']) {
          expect(enLaBase[columna], isNull, reason: '$columna en la base');
          expect(payload.containsKey(columna), isTrue, reason: '$columna en la cola');
          expect(payload[columna], isNull, reason: '$columna en la cola');
        }
      });

      test('lo que arma cada renglón pasa un vínculo vacío a null, o no se arma', () {
        final bloque = MovimientoParaRendir.dio(
          eventoId: _fiesta,
          personaNombre: 'Ana Gómez',
          personaContacto: '',
          contratoAlumnoId: '  ',
          cantidad: 2,
          tramos: const [TramoTalonario(1, 2)],
          precio: 8000,
          nombrePrecio: 'Entrada anticipada',
          ahora: ahora,
        );
        expect(bloque.toMap()['contrato_alumno_id'], isNull);
        expect(bloque.toMap()['persona_contacto'], isNull);
        final devolvio = MovimientoParaRendir.devolvio(
          bloque,
          tramos: const [TramoTalonario(2, 2)],
          cajaEntradasId: '',
          ahora: ahora,
        );
        expect(devolvio.cajaEntradasId, isNull);
        expect(devolvio.toMap()['caja_entradas_id'], isNull);
        // Lo vendido sin la venta o sin la caja que cobró no se arma.
        expect(
          () => MovimientoParaRendir.vendio(
            bloque,
            cantidad: 1,
            ventaId: '',
            cajaEntradasId: _f1,
            ahora: ahora,
          ),
          throwsArgumentError,
        );
        expect(
          () => MovimientoParaRendir.vendio(
            bloque,
            cantidad: 1,
            ventaId: _f1,
            cajaEntradasId: ' ',
            ahora: ahora,
          ),
          throwsArgumentError,
        );
      });

      test('una fila con "" en un vínculo se lee null (y se volvería a escribir en null)', () {
        final leido = MovimientoParaRendir.fromMap({
          'id': _f1,
          'evento_id': _fiesta,
          'bloque_id': _f2,
          'que': 'anulo',
          'persona_nombre': 'Ana Gómez',
          'contrato_alumno_id': '',
          'persona_contacto': '',
          'venta_id': '',
          'caja_entradas_id': ' ',
          'anula_id': '',
          'numeros': '',
          'nota': '',
          'cantidad': 0,
          'created_at': '2026-11-20T15:00:00.000Z',
          'updated_at': '2026-11-20T15:00:00.000Z',
        });
        expect(leido.contratoAlumnoId, isNull);
        expect(leido.personaContacto, isNull);
        expect(leido.ventaId, isNull);
        expect(leido.cajaEntradasId, isNull);
        expect(leido.anulaId, isNull);
        expect(leido.numeros, isNull);
        final mapa = leido.toMap();
        for (final columna in vinculos) {
          expect(mapa[columna], isNull, reason: columna);
        }
      });
    });

    group('regla 36 y 38: se rinde al precio y con el nombre del día en que se las llevó', () {
      test('aunque el jefe cambie PRECIOS y la anticipada ya no rija', () async {
        await entradas.guardarConfig(conPrecio(valor: 10000), quien: 'Jefe');
        final bloque = await dar(precio: 8000, nombrePrecio: 'Entrada anticipada');
        // Después el jefe sube la entrada y pone GENERAL: la anticipada se borra.
        await entradas.guardarConfig(conPrecio(valor: 15000), quien: 'Jefe');

        final r = await rendir(bloque, vendidas: 15);
        final venta = r.venta!;
        final renglon = venta.renglones.single;
        expect(renglon.nombre, 'Entrada anticipada · para rendir');
        expect(renglon.precioLista, 8000);
        expect(renglon.precio, 8000);
        expect(renglon.descuentoPct, 0, reason: 'sin comisión ni descuento');
        expect(renglon.tipo, TipoRenglonEntradas.suelta);
        expect(renglon.cantidad, 15);
        expect(venta.total, 15 * 8000.0);
        expect(venta.descuento, 0);
        expect(venta.efectivo, 15 * 8000.0);
      });

      test('el precio es el guardado en la base, no el que trae la pantalla', () async {
        final bloque = await dar(precio: 8000);
        // Una pantalla con el bloque viejo o tocado: lo que vale es lo de la base.
        final tocado = MovimientoParaRendir.fromMap({
          ...bloque.toMap(),
          'precio': 1,
          'nombre_precio': 'Otra cosa',
        });
        final r = await rendir(tocado, vendidas: 2);
        expect(r.venta!.renglones.single.precioLista, 8000);
        expect(r.venta!.renglones.single.nombre, 'Entrada anticipada · para rendir');
        expect(r.venta!.total, 16000);
      });

      test('la venta va a nombre de quien rinde, sin familia y sin números', () async {
        final bloque = await dar(familia: _familia);
        final r = await rendir(bloque, vendidas: 3);
        final venta = r.venta!;
        expect(venta.contratoAlumnoId, isNull,
            reason: 'si llevara la familia, se le descontarían de sus lugares');
        expect(venta.compradorNombre, 'Juan Pérez');
        expect(venta.numeros, isNull, reason: 'los números los lleva el bloque');
        expect(venta.cajaEntradasId, caja.id);
        expect(venta.hechoPor, 'Carla');
        final enLaBase = (await filas('entradas_ventas')).single;
        expect(enLaBase['contrato_alumno_id'], isNull);
        expect(enLaBase['numeros'], isNull);
        // Y el renglón dice qué venta tiene la plata.
        expect(r.vendio!.ventaId, venta.id);
        expect(r.vendio!.cajaEntradasId, caja.id);
        expect(r.vendio!.cantidad, 3);
      });

      test('una venta de la caja lleva el número que sigue, como cualquiera', () async {
        await vender(caja);
        final bloque = await dar();
        final r = await rendir(bloque, vendidas: 1);
        expect(r.venta!.numero, 2);
      });
    });

    group('regla 40: rendir es todo o nada', () {
      Future<void> trabar(String cuando) async {
        final db = await LocalDatabase.instance;
        await db.execute('''
          CREATE TRIGGER traba_de_la_prueba BEFORE INSERT ON $cuando
          BEGIN SELECT RAISE(ABORT, 'la base no anda (prueba)'); END
        ''');
      }

      Future<void> destrabar() async {
        final db = await LocalDatabase.instance;
        await db.execute('DROP TRIGGER IF EXISTS traba_de_la_prueba');
      }

      test('si falla un renglón, la venta no queda (ni en la cola)', () async {
        final bloque = await dar();
        final antes = await foto();
        final db = await LocalDatabase.instance;
        await db.execute('''
          CREATE TRIGGER traba_de_la_prueba BEFORE INSERT ON entradas_para_rendir
          WHEN NEW.que = 'devolvio'
          BEGIN SELECT RAISE(ABORT, 'la base no anda (prueba)'); END
        ''');
        await expectLater(
          rendir(bloque, vendidas: 15, devueltos: const [TramoTalonario(1216, 1220)]),
          throwsA(anything),
        );
        await destrabar();
        expect(await foto(), antes, reason: 'ni la venta, ni el "vendió", ni su cola');
        // Y el número de la caja no se gastó.
        expect((await rendir(bloque, vendidas: 1)).venta!.numero, 1);
      });

      test('si falla la venta, los renglones no quedan', () async {
        final bloque = await dar();
        final antes = await foto();
        await trabar('entradas_ventas');
        await expectLater(
          rendir(bloque, vendidas: 15, devueltos: const [TramoTalonario(1216, 1220)]),
          throwsA(anything),
        );
        await destrabar();
        expect(await foto(), antes);
      });

      test('una cuenta de plata que no cierra no guarda nada', () async {
        final bloque = await dar();
        final antes = await foto();
        await expectLater(
          entradas.rendir(
            caja: caja,
            bloque: bloque,
            vendidas: 2,
            devueltas: 3,
            numerosDevueltos: const [TramoTalonario(1218, 1220)],
            medio: MedioBarra.efectivo,
            efectivo: 1000, // no da 2 × 8000
            quien: 'Carla',
          ),
          throwsArgumentError,
        );
        expect(await foto(), antes);
      });

      test('vendió y devolvió: una venta y dos renglones, cada uno con su cola', () async {
        final bloque = await dar();
        final r = await rendir(
          bloque,
          vendidas: 15,
          devueltos: const [TramoTalonario(1216, 1220)],
        );
        expect(r.devolvio!.cantidad, 5);
        expect(r.devolvio!.tramos, const [TramoTalonario(1216, 1220)]);
        expect(r.devolvio!.cajaEntradasId, caja.id);
        expect(r.movimientos.map((m) => m.queClave), ['vendio', 'devolvio']);
        expect(await filas('entradas_ventas'), hasLength(1));
        expect(await filas(EntradasLocal.tablaParaRendir), hasLength(3));
        expect(
          {for (final c in await cola(EntradasLocal.tablaParaRendir)) c['registro_id']},
          {bloque.id, r.vendio!.id, r.devolvio!.id},
        );
        expect((await cola('entradas_ventas')).single['registro_id'], r.venta!.id);
      });

      test('solo devolver no pide caja ni plata, y no hace venta', () async {
        final bloque = await dar();
        final r = await entradas.rendir(
          bloque: bloque,
          vendidas: 0,
          devueltas: 2,
          numerosDevueltos: const [TramoTalonario(1219, 1220)],
          quien: 'Carla',
        );
        expect(r.venta, isNull);
        expect(r.vendio, isNull);
        expect(r.devolvio!.cajaEntradasId, isNull);
        expect(await filas('entradas_ventas'), isEmpty);
        // Con plata y sin vender, no cierra.
        await expectLater(
          entradas.rendir(
            bloque: bloque,
            vendidas: 0,
            devueltas: 1,
            numerosDevueltos: const [TramoTalonario(1218, 1218)],
            efectivo: 8000,
            quien: 'Carla',
          ),
          throwsArgumentError,
        );
        // Vender sin caja, tampoco.
        await expectLater(
          entradas.rendir(
            bloque: bloque,
            vendidas: 1,
            efectivo: 8000,
            quien: 'Carla',
          ),
          throwsArgumentError,
        );
      });

      test('con la caja cerrada no se cobra lo vendido', () async {
        final bloque = await dar();
        await entradas.cerrarCaja(caja, efectivoContado: 0, diferencia: 0, quien: 'Carla');
        final antes = await foto();
        await expectLater(rendir(bloque, vendidas: 2), throwsStateError);
        expect(await foto(), antes);
      });
    });

    // La caja y la fiesta se miran como están en la base, dentro de la
    // transacción, no como las trae la pantalla (revisión del 20-nov-2026).
    group('la caja de la rendición es la de la base', () {
      Future<RendicionDeEntradas> devolver(
        MovimientoParaRendir bloque,
        int numero, {
        CajaEntradas? conCaja,
      }) =>
          entradas.rendir(
            caja: conCaja,
            bloque: bloque,
            vendidas: 0,
            devueltas: 1,
            numerosDevueltos: [TramoTalonario(numero, numero)],
            quien: 'Carla',
          );

      Future<Object?> cajaEnLaBase(MovimientoParaRendir m) async =>
          (await filas(EntradasLocal.tablaParaRendir))
              .singleWhere((f) => f['id'] == m.id)['caja_entradas_id'];

      test('solo devolviendo, la caja va solo si está en este equipo y abierta', () async {
        final bloque = await dar();
        final ajena = CajaEntradas.abrir(eventoId: _fiesta, ahora: ahora);
        final conAjena = await devolver(bloque, 1220, conCaja: ajena);
        expect(conAjena.devolvio!.cajaEntradasId, isNull,
            reason: 'nunca apuntando a una caja que este equipo no tiene');
        expect(await cajaEnLaBase(conAjena.devolvio!), isNull);

        final conLaSuya = await devolver(bloque, 1219, conCaja: caja);
        expect(conLaSuya.devolvio!.cajaEntradasId, caja.id);
        expect(await cajaEnLaBase(conLaSuya.devolvio!), caja.id);

        await entradas.cerrarCaja(caja, efectivoContado: 0, diferencia: 0, quien: 'Carla');
        // La pantalla todavía tiene la caja abierta en la mano: vale la base.
        final conCerrada = await devolver(bloque, 1218, conCaja: caja);
        expect(conCerrada.devolvio!.cajaEntradasId, isNull);
      });

      test('una caja de otra fiesta no cobra, aunque la pantalla traiga el bloque tocado',
          () async {
        final bloque = await dar();
        final deOtra = await entradas.abrirCaja(
          eventoId: _otraFiesta,
          operadorId: _f1,
          operadorNombre: 'Carla',
        );
        // Una pantalla con el bloque cambiado de fiesta: la fiesta que vale es la
        // del bloque guardado.
        final tocado = MovimientoParaRendir.fromMap({
          ...bloque.toMap(),
          'evento_id': _otraFiesta,
        });
        final antes = await foto();
        await expectLater(
          entradas.rendir(
            caja: deOtra,
            bloque: tocado,
            vendidas: 2,
            medio: MedioBarra.efectivo,
            efectivo: 16000,
            quien: 'Carla',
          ),
          throwsArgumentError,
        );
        await expectLater(devolver(tocado, 1220, conCaja: deOtra), throwsArgumentError);
        expect(await foto(), antes, reason: 'ni la venta en la caja de la otra fiesta');
      });
    });

    group('regla 41: no se rinde más de lo que le queda', () {
      test('se vuelve a contar: la pantalla con la cuenta vieja no rinde de más', () async {
        final bloque = await dar();
        await rendir(bloque, vendidas: 15);
        final antes = await foto();
        // La misma pantalla, con el bloque de antes en la mano, pide 10 más.
        await expectLater(rendir(bloque, vendidas: 10), throwsStateError);
        expect(await foto(), antes);
        // Las 5 que le quedan, sí.
        await rendir(bloque, devueltos: const [TramoTalonario(1216, 1220)]);
        await expectLater(rendir(bloque, vendidas: 1), throwsStateError,
            reason: 'ya no le queda ninguna');
      });

      test('dos rendiciones a la vez del mismo bloque: una sola entra', () async {
        final bloque = await dar();
        final otraPantalla = EntradasLocal(
          equipo: () async => 'pc-1',
          reloj: () => ahora = ahora.add(const Duration(seconds: 1)),
        );
        final resultados = await Future.wait([
          rendir(bloque, vendidas: 15).then<Object>((r) => r, onError: (Object e) => e),
          rendir(bloque, vendidas: 10, desde: otraPantalla)
              .then<Object>((r) => r, onError: (Object e) => e),
        ]);
        expect(resultados.whereType<RendicionDeEntradas>(), hasLength(1));
        expect(resultados.whereType<StateError>(), hasLength(1));
        expect(await filas('entradas_ventas'), hasLength(1));
      });

      test('lo devuelto se cuenta, y un número que ya volvió no se devuelve de nuevo',
          () async {
        final bloque = await dar();
        await rendir(bloque, devueltos: const [TramoTalonario(1216, 1220)]);
        await expectLater(
          rendir(bloque, devueltos: const [TramoTalonario(1220, 1220)]),
          throwsStateError,
        );
        await expectLater(
          rendir(bloque, devueltos: const [TramoTalonario(1221, 1221)]),
          throwsArgumentError,
          reason: 'el 1221 no es de las que se llevó',
        );
        await expectLater(rendir(bloque, vendidas: 16), throwsStateError);
        await rendir(bloque, vendidas: 15);
      });

      test('una rendición anulada en VENTAS vuelve a quedar para rendir', () async {
        final bloque = await dar();
        final r = await rendir(bloque, vendidas: 20);
        await expectLater(rendir(bloque, vendidas: 1), throwsStateError);
        await entradas.anular(r.venta!, motivo: 'se cobró mal', devueltas: false, quien: 'Jefe');
        await rendir(bloque, vendidas: 20);
      });

      test('lo que no volvió se cuenta, y anular un "devolvió" se lo devuelve', () async {
        final bloque = await dar();
        await entradas.noVolvieron(bloque, cantidad: 5, motivo: 'las perdió', quien: 'Jefe');
        await expectLater(rendir(bloque, vendidas: 16), throwsStateError);
        final r = await rendir(bloque, devueltos: const [TramoTalonario(1201, 1215)]);
        await expectLater(rendir(bloque, vendidas: 1), throwsStateError);
        await entradas.anularDeParaRendir(r.devolvio!, motivo: 'no las trajo', quien: 'Jefe');
        await rendir(bloque, vendidas: 15);
        // Y no volvieron no pasa de lo que le queda.
        await expectLater(
          entradas.noVolvieron(bloque, cantidad: 1, motivo: 'otra', quien: 'Jefe'),
          throwsStateError,
        );
      });

      test('un bloque anulado no se rinde', () async {
        final bloque = await dar();
        await entradas.anularDeParaRendir(bloque, motivo: 'se cargó mal', quien: 'Jefe');
        await expectLater(rendir(bloque, vendidas: 1), throwsStateError);
      });

      test('un bloque que no está en este equipo no se rinde', () async {
        final deOtro = MovimientoParaRendir.dio(
          eventoId: _fiesta,
          personaNombre: 'Juan Pérez',
          cantidad: 2,
          tramos: const [TramoTalonario(1, 2)],
          precio: 8000,
          nombrePrecio: 'Entrada anticipada',
          ahora: ahora,
        );
        await expectLater(rendir(deOtro, vendidas: 1), throwsStateError);
        expect(await filas('entradas_ventas'), isEmpty);
      });
    });

    // SPEC §2 y §3: NO VOLVIERON lleva motivo, y esos números quedan anulados
    // para siempre. Lo frenan tres cosas (el motivo, la cantidad justa y del
    // bloque al armar el renglón, y lo que ya no tiene dentro de la
    // transacción); sin estas pruebas, sacar cualquiera de las tres no rompía
    // nada, y un mismo número podía quedar a la vez devuelto y perdido.
    group('NO VOLVIERON: con motivo, y lo que no volvió ya no vuelve', () {
      Future<MovimientoParaRendir> perder(
        MovimientoParaRendir bloque, {
        int cantidad = 1,
        List<TramoTalonario> numeros = const [],
        String motivo = 'la perdió',
      }) =>
          entradas.noVolvieron(
            bloque,
            cantidad: cantidad,
            numeros: numeros,
            motivo: motivo,
            quien: 'Jefe',
          );

      test('sin motivo no se da por perdida ninguna, y no escribe nada', () async {
        final bloque = await dar();
        final antes = await foto();
        await expectLater(perder(bloque, motivo: '   '), throwsArgumentError);
        await expectLater(
          perder(bloque, numeros: const [TramoTalonario(1220, 1220)], motivo: ''),
          throwsArgumentError,
        );
        expect(await foto(), antes);
        final perdida = await perder(bloque, motivo: '  se le mojaron ');
        expect(perdida.motivo, 'se le mojaron');
      });

      test('con números, la cantidad justa y de las que se llevó; si no, no escribe nada',
          () async {
        final bloque = await dar();
        final antes = await foto();
        await expectLater(
          perder(bloque, cantidad: 2, numeros: const [TramoTalonario(1220, 1220)]),
          throwsArgumentError,
          reason: 'un número y dos entradas',
        );
        await expectLater(
          perder(bloque, cantidad: 1, numeros: const [TramoTalonario(1221, 1221)]),
          throwsArgumentError,
          reason: 'el 1221 no es de las que se llevó',
        );
        await expectLater(
          perder(bloque, cantidad: 2, numeros: const [TramoTalonario(1220, 1221)]),
          throwsArgumentError,
          reason: 'uno es suyo y el otro no',
        );
        expect(await foto(), antes);
        final perdidas = await perder(
          bloque,
          cantidad: 2,
          numeros: const [TramoTalonario(1219, 1220)],
        );
        expect(perdidas.tramos, const [TramoTalonario(1219, 1220)]);
        expect(perdidas.cantidad, 2);
      });

      test('un número que ya volvió no se da por perdido', () async {
        final bloque = await dar();
        await rendir(bloque, devueltos: const [TramoTalonario(1216, 1220)]);
        final antes = await foto();
        await expectLater(
          perder(bloque, numeros: const [TramoTalonario(1220, 1220)]),
          throwsStateError,
        );
        await expectLater(
          perder(bloque, cantidad: 2, numeros: const [TramoTalonario(1215, 1216)]),
          throwsStateError,
          reason: 'tampoco si viene junto con uno que todavía tiene',
        );
        expect(await foto(), antes);
        // Uno que todavía tiene, sí.
        await perder(bloque, numeros: const [TramoTalonario(1215, 1215)]);
      });

      test('uno que se dio por perdido no se devuelve: queda anulado para siempre', () async {
        final bloque = await dar();
        final perdida = await perder(bloque, numeros: const [TramoTalonario(1220, 1220)]);
        final antes = await foto();
        await expectLater(
          rendir(bloque, devueltos: const [TramoTalonario(1220, 1220)]),
          throwsStateError,
        );
        await expectLater(
          rendir(bloque, vendidas: 2, devueltos: const [TramoTalonario(1219, 1220)]),
          throwsStateError,
          reason: 'tampoco junto con otro, ni cobrando algo en la misma rendición',
        );
        expect(await foto(), antes, reason: 'ni la venta ni sus renglones');
        // Los 19 que todavía tiene, sí.
        await rendir(bloque, devueltos: const [TramoTalonario(1201, 1219)]);
        // Si el jefe anula el "no volvieron" (aparecieron), ese número vuelve a
        // ser suyo y se puede devolver.
        await entradas.anularDeParaRendir(perdida, motivo: 'apareció', quien: 'Jefe');
        await rendir(bloque, devueltos: const [TramoTalonario(1220, 1220)]);
      });
    });

    // Regla 58 en la base (SPEC §3): una versión más nueva puede anotar un
    // renglón que esta no conoce. Se conserva tal cual y no cuenta: ni le resta
    // entradas al bloque ni le saca números. La cuenta entera (`ParaRendir.de`)
    // es de la etapa 4; esto cuida lo que frena dentro de la transacción.
    group('regla 58: un renglón que esta versión no conoce no cuenta', () {
      test('no le resta entradas ni números al bloque, y se conserva como vino', () async {
        final bloque = await dar();
        final desconocido = MovimientoParaRendir(
          id: UuidUtils.generate(),
          eventoId: _fiesta,
          bloqueId: bloque.id,
          queClave: 'regalo',
          personaNombre: 'Juan Pérez',
          cantidad: 5,
          numeros: '1216-1220',
          motivo: 'premio',
          deviceId: 'tablet-nueva',
          createdAt: '2026-11-20T16:00:00.000Z',
          updatedAt: '2026-11-20T16:00:00.000Z',
        );
        // Como si hubiera bajado de otro equipo: sin cola.
        final db = await LocalDatabase.instance;
        await db.insert(EntradasLocal.tablaParaRendir, desconocido.toMap());

        expect(
          MovimientoParaRendir.quedanSinRendir(bloque, await entradas.paraRendir(_fiesta)),
          20,
        );
        // Rinde las 20: 15 vendidas y las 5 de los números de ese renglón.
        final r = await rendir(
          bloque,
          vendidas: 15,
          devueltos: const [TramoTalonario(1216, 1220)],
        );
        expect(r.venta!.cantidad, 15);
        expect(r.devolvio!.tramos, const [TramoTalonario(1216, 1220)]);
        final enLaBase = (await filas(EntradasLocal.tablaParaRendir))
            .singleWhere((f) => f['id'] == desconocido.id);
        expect(MovimientoParaRendir.fromMap(enLaBase).toMap(), desconocido.toMap());
        expect(MovimientoParaRendir.fromMap(enLaBase).que, isNull);
      });
    });

    group('regla 54: "Todo subido" cuenta la tabla nueva', () {
      test('dar, devolver y no volvieron son cambios; lo rendido, una venta', () async {
        final db = await LocalDatabase.instance;
        await db.delete('_sync_queue'); // la caja que se abrió
        expect(await entradas.cambiosSinSubir(), 0);

        final bloque = await dar();
        expect(await entradas.cambiosSinSubir(), 1);
        expect(await entradas.ventasSinSubir(), 0);

        await rendir(bloque, vendidas: 2, devueltos: const [TramoTalonario(1220, 1220)]);
        expect(await entradas.ventasSinSubir(), 1);
        expect(await entradas.cambiosSinSubir(), 3, reason: 'el bloque, el vendió y el devolvió');

        await entradas.noVolvieron(bloque, cantidad: 1, motivo: 'la perdió', quien: 'Jefe');
        expect(await entradas.cambiosSinSubir(), 4);
      });

      // El otro lado de la regla 54: la línea de arriba de VENDER, armada como
      // la arma VENDER (`_pendientes`, sin las entregas, que son otra tabla).
      // La pantalla entera se prueba en la etapa 5.
      test('con un bloque dado sin subir, VENDER no dice "Todo subido"', () async {
        final db = await LocalDatabase.instance;
        await db.delete('_sync_queue'); // la caja que se abrió
        Future<String> linea({bool internet = true}) async => lineaDeSubidaDeEntradas(
              hayInternet: internet,
              pendientes: PendientesDeEntradas(
                ventas: await entradas.ventasSinSubir(),
                otros: await entradas.cambiosSinSubir(),
              ),
            ).texto;

        expect(await linea(), 'Todo subido');
        final bloque = await dar();
        expect(await linea(), '1 cambio subiendo');
        expect(await linea(internet: false), 'Sin internet · 1 cambio por subir');

        // El bloque ya subió, y la tablet rinde sin internet (SPEC §7).
        await db.delete('_sync_queue');
        await rendir(bloque, vendidas: 15);
        expect(await linea(internet: false), 'Sin internet · 1 venta y 1 cambio por subir');
      });
    });

    group('regla 55: anular es otra fila con id fijo', () {
      test('dos veces (o desde dos equipos) deja una sola', () async {
        final bloque = await dar();
        final primera = await entradas.anularDeParaRendir(
          bloque,
          motivo: 'se cargó mal',
          quien: 'Jefe',
        );
        expect(primera.esAnulo, isTrue);
        expect(primera.anulaId, bloque.id);
        expect(primera.bloqueId, bloque.id);
        expect(primera.id, UuidUtils.entradasParaRendirAnulacionId(bloque.id));
        expect(primera.motivo, 'se cargó mal');

        final otroEquipo = EntradasLocal(
          equipo: () async => 'tablet-9',
          reloj: () => ahora = ahora.add(const Duration(seconds: 1)),
        );
        final segunda = await otroEquipo.anularDeParaRendir(
          bloque,
          motivo: 'otro motivo',
          quien: 'Otro',
        );
        expect(segunda.toMap(), primera.toMap(), reason: 'devuelve la que ya había');
        final anulos = [
          for (final f in await filas(EntradasLocal.tablaParaRendir))
            if (f['que'] == 'anulo') f,
        ];
        expect(anulos, hasLength(1));
        // El bloque sigue como se dio: anular no lo toca.
        final elBloque = (await filas(EntradasLocal.tablaParaRendir))
            .singleWhere((f) => f['id'] == bloque.id);
        expect(MovimientoParaRendir.fromMap(elBloque).toMap(), bloque.toMap());
      });

      test('un bloque con algo en pie no se anula; anulado lo suyo, sí', () async {
        final bloque = await dar();
        final r = await rendir(
          bloque,
          vendidas: 2,
          devueltos: const [TramoTalonario(1220, 1220)],
        );
        final antes = await foto();
        await expectLater(
          entradas.anularDeParaRendir(bloque, motivo: 'se cargó mal', quien: 'Jefe'),
          throwsStateError,
        );
        expect(await foto(), antes);

        await entradas.anularDeParaRendir(r.devolvio!, motivo: 'no volvió', quien: 'Jefe');
        await expectLater(
          entradas.anularDeParaRendir(bloque, motivo: 'se cargó mal', quien: 'Jefe'),
          throwsStateError,
          reason: 'lo vendido sigue en pie',
        );
        // Lo vendido no se anula acá: se anula su venta en VENTAS.
        await expectLater(
          entradas.anularDeParaRendir(r.vendio!, motivo: 'x', quien: 'Jefe'),
          throwsArgumentError,
        );
        await entradas.anular(r.venta!, motivo: 'se cobró mal', devueltas: false, quien: 'Jefe');
        final anulo = await entradas.anularDeParaRendir(
          bloque,
          motivo: 'se cargó mal',
          quien: 'Jefe',
        );
        expect(anulo.anulaId, bloque.id);
      });

      test('la anulación lleva la cantidad de lo que anula, y no sus números', () async {
        final bloque = await dar();
        final r = await rendir(bloque, devueltos: const [TramoTalonario(1216, 1220)]);
        final anulo = await entradas.anularDeParaRendir(
          r.devolvio!,
          motivo: 'no las trajo',
          quien: 'Jefe',
        );
        expect(anulo.anulaId, r.devolvio!.id);
        expect(anulo.bloqueId, bloque.id);
        expect(anulo.cantidad, 5, reason: 'para que quede escrito');
        // Si llevara los números, quien juntara los de todas las filas del bloque
        // vería otro bloque del 1216 al 1220 (SPEC §3 y §4).
        expect(anulo.numeros, isNull);
        expect(anulo.tramos, isEmpty);
        final enLaBase = (await filas(EntradasLocal.tablaParaRendir))
            .singleWhere((f) => f['id'] == anulo.id);
        expect(enLaBase['numeros'], isNull);
        // Y esos números vuelven a ser suyos: se pueden devolver otra vez.
        await rendir(bloque, devueltos: const [TramoTalonario(1216, 1220)]);
      });

      test('sin motivo no se anula, y una anulación no se anula', () async {
        final bloque = await dar();
        await expectLater(
          entradas.anularDeParaRendir(bloque, motivo: '  ', quien: 'Jefe'),
          throwsArgumentError,
        );
        final anulo = await entradas.anularDeParaRendir(bloque, motivo: 'mal', quien: 'Jefe');
        await expectLater(
          entradas.anularDeParaRendir(anulo, motivo: 'otra', quien: 'Jefe'),
          throwsArgumentError,
        );
        expect(await filas(EntradasLocal.tablaParaRendir), hasLength(2));
      });
    });
  });

  test('una base que todavía no migró se lee vacía, sin tirar', () async {
    final sinTablas = EntradasLocal(
      abrir: () async {
        final db = await LocalDatabase.instance;
        for (final t in [...EntradasLocal.tablas, EntradasLocal.tablaParaRendir]) {
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
    expect(await sinTablas.paraRendir(_fiesta), isEmpty);
    expect(await sinTablas.cajaAbierta(eventoId: _fiesta), isNull);
  });

  test('las entradas para rendir no entran en las cinco tablas de la v80', () {
    expect(EntradasLocal.tablas, hasLength(5));
    expect(EntradasLocal.tablas, isNot(contains(EntradasLocal.tablaParaRendir)));
  });
}
