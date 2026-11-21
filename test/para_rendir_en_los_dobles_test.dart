// Las entradas para rendir en los dobles de prueba hacen lo mismo que la base
// del equipo (revisión del 20-nov-2026). Las pantallas de la etapa 5 se van a
// probar con `EntradasEnMemoria`, y el recorrido de dos equipos de la etapa 7
// con `EntradasDeUnEquipo` (tool/venta_entradas_prueba.dart): si un doble se
// separara de `EntradasLocal`, una pantalla pasaría sus pruebas y en la app
// haría otra cosa, sin que nadie se entere. Por eso los mismos casos de las
// reglas 41 y 55 (volver a contar, el bloque anulado, anular dos veces) y los de
// la caja de la rendición corren contra los tres.
//
// Al final, los dos equipos de la ventana de prueba: lo que da el jefe en la PC
// y lo que rinde Carla en la tablet cruzan por la nube de prueba, y sin internet
// quedan en la cola hasta que vuelve.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/entradas/datos/entradas_local.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/models/entradas_retiro.dart' show TramoTalonario;

import '../tool/venta_entradas_prueba.dart';
import 'helpers/entrega_en_memoria.dart' show idFiestaEntrega;
import 'helpers/entradas_en_memoria.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _otraFiesta = 'e0000000-0000-4000-8000-000000000002';
const _carla = 'a0000000-0000-4000-8000-000000000001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late DateTime ahora;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('para_rendir_dobles');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );
    ahora = DateTime.utc(2026, 11, 20, 15);
  });

  tearDown(() async {
    await LocalDatabase.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  // Los tres implementan lo de la caja y lo del jefe.
  final repositorios = <String, Object Function()>{
    'EntradasLocal (la base del equipo)': () => EntradasLocal(
          equipo: () async => 'pc-1',
          reloj: () => ahora = ahora.add(const Duration(seconds: 1)),
        ),
    'EntradasEnMemoria': () => EntradasEnMemoria(),
    'EntradasDeUnEquipo (la ventana de prueba, sin nube)': () =>
        EntradasDeUnEquipo(equipo: 'pc-1'),
  };

  for (final MapEntry(key: nombre, value: armar) in repositorios.entries) {
    group(nombre, () {
      late Object repo;
      late EntradasDeLaCaja vende;
      late EntradasDelJefe jefe;
      late CajaEntradas caja;

      setUp(() async {
        repo = armar();
        vende = repo as EntradasDeLaCaja;
        jefe = repo as EntradasDelJefe;
        caja = await vende.abrirCaja(
          eventoId: _fiesta,
          operadorId: _carla,
          operadorNombre: 'Carla',
        );
      });

      Future<MovimientoParaRendir> dar() => jefe.darParaRendir(
            eventoId: _fiesta,
            personaNombre: 'Juan Pérez',
            cantidad: 20,
            numeros: const [TramoTalonario(1201, 1220)],
            precio: 8000,
            nombrePrecio: 'Entrada anticipada',
            quien: 'Jefe',
          );

      Future<RendicionDeEntradas> rendir(
        MovimientoParaRendir bloque, {
        int vendidas = 0,
        List<TramoTalonario> devueltos = const [],
        CajaEntradas? conCaja,
      }) =>
          vende.rendir(
            caja: conCaja ?? (vendidas > 0 ? caja : null),
            bloque: bloque,
            vendidas: vendidas,
            devueltas: devueltos.fold(0, (s, t) => s + t.cantidad),
            numerosDevueltos: devueltos,
            medio: MedioBarra.efectivo,
            efectivo: vendidas * 8000.0,
            quien: 'Carla',
          );

      /// Cuántos renglones y ventas hay: lo que falla no tiene que dejar nada.
      Future<(int, int)> cuantos() async => (
            (await vende.paraRendir(_fiesta)).length,
            (await vende.ventas(_fiesta)).length,
          );

      Future<MovimientoParaRendir> perder(
        MovimientoParaRendir bloque, {
        int cantidad = 1,
        List<TramoTalonario> numeros = const [],
        String motivo = 'la perdió',
      }) =>
          jefe.noVolvieron(
            bloque,
            cantidad: cantidad,
            numeros: numeros,
            motivo: motivo,
            quien: 'Jefe',
          );

      /// Un renglón que bajó de otro equipo, sin pasar por la cola: en la base
      /// del equipo o en la lista del doble.
      Future<void> ponerComoBajado(MovimientoParaRendir m) async {
        final r = repo;
        if (r is EntradasEnMemoria) {
          r.listaParaRendir.add(m);
        } else {
          final db = await LocalDatabase.instance;
          await db.insert(EntradasLocal.tablaParaRendir, m.toMap());
        }
      }

      test('regla 41: se vuelve a contar; la pantalla con la cuenta vieja no rinde de más',
          () async {
        final bloque = await dar();
        await rendir(bloque, vendidas: 15);
        final antes = await cuantos();
        await expectLater(rendir(bloque, vendidas: 10), throwsStateError);
        expect(await cuantos(), antes);
        await rendir(bloque, devueltos: const [TramoTalonario(1216, 1220)]);
        await expectLater(rendir(bloque, vendidas: 1), throwsStateError);
        expect(
          MovimientoParaRendir.quedanSinRendir(bloque, await vende.paraRendir(_fiesta)),
          0,
        );
      });

      test('regla 41: un número que ya volvió no se devuelve de nuevo, ni uno que no se llevó',
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
        );
        await expectLater(rendir(bloque, vendidas: 16), throwsStateError);
        await rendir(bloque, vendidas: 15);
      });

      test('regla 41: una rendición anulada en VENTAS vuelve a quedar para rendir', () async {
        final bloque = await dar();
        final r = await rendir(bloque, vendidas: 20);
        await expectLater(rendir(bloque, vendidas: 1), throwsStateError);
        await jefe.anular(r.venta!, motivo: 'se cobró mal', devueltas: false, quien: 'Jefe');
        await rendir(bloque, vendidas: 20);
      });

      test('regla 41: lo que no volvió cuenta, y anular un "devolvió" se lo devuelve', () async {
        final bloque = await dar();
        await jefe.noVolvieron(bloque, cantidad: 5, motivo: 'las perdió', quien: 'Jefe');
        await expectLater(rendir(bloque, vendidas: 16), throwsStateError);
        final r = await rendir(bloque, devueltos: const [TramoTalonario(1201, 1215)]);
        await expectLater(rendir(bloque, vendidas: 1), throwsStateError);
        await jefe.anularDeParaRendir(r.devolvio!, motivo: 'no las trajo', quien: 'Jefe');
        await rendir(bloque, vendidas: 15);
        await expectLater(
          jefe.noVolvieron(bloque, cantidad: 1, motivo: 'otra', quien: 'Jefe'),
          throwsStateError,
        );
      });

      test('NO VOLVIERON: sin motivo, o con números que no cierran, no escribe nada', () async {
        final bloque = await dar();
        final antes = await cuantos();
        await expectLater(perder(bloque, motivo: '   '), throwsArgumentError);
        await expectLater(
          perder(bloque, cantidad: 2, numeros: const [TramoTalonario(1220, 1220)]),
          throwsArgumentError,
          reason: 'un número y dos entradas',
        );
        await expectLater(
          perder(bloque, numeros: const [TramoTalonario(1221, 1221)]),
          throwsArgumentError,
          reason: 'el 1221 no es de las que se llevó',
        );
        expect(await cuantos(), antes);
        final perdida = await perder(bloque, numeros: const [TramoTalonario(1220, 1220)]);
        expect(perdida.tramos, const [TramoTalonario(1220, 1220)]);
        expect(perdida.motivo, 'la perdió');
      });

      test('NO VOLVIERON: un número que ya volvió no se da por perdido', () async {
        final bloque = await dar();
        await rendir(bloque, devueltos: const [TramoTalonario(1216, 1220)]);
        final antes = await cuantos();
        await expectLater(
          perder(bloque, numeros: const [TramoTalonario(1220, 1220)]),
          throwsStateError,
        );
        expect(await cuantos(), antes);
        await perder(bloque, numeros: const [TramoTalonario(1215, 1215)]);
      });

      test('NO VOLVIERON: uno que se dio por perdido no se devuelve, salvo que se anule',
          () async {
        final bloque = await dar();
        final perdida = await perder(bloque, numeros: const [TramoTalonario(1220, 1220)]);
        final antes = await cuantos();
        await expectLater(
          rendir(bloque, devueltos: const [TramoTalonario(1220, 1220)]),
          throwsStateError,
        );
        await expectLater(
          rendir(bloque, vendidas: 2, devueltos: const [TramoTalonario(1219, 1220)]),
          throwsStateError,
        );
        expect(await cuantos(), antes);
        await rendir(bloque, devueltos: const [TramoTalonario(1201, 1219)]);
        await jefe.anularDeParaRendir(perdida, motivo: 'apareció', quien: 'Jefe');
        await rendir(bloque, devueltos: const [TramoTalonario(1220, 1220)]);
      });

      /// Lo que espera subir en la cola del equipo (solo la base tiene cola).
      Future<int> enLaCola() async {
        if (repo is! EntradasLocal) return 0;
        final db = await LocalDatabase.instance;
        return (await db.query('_sync_queue')).length;
      }

      test('DAR: tramos que se pisan, al revés o desde el 0 no escriben nada', () async {
        final antes = (await cuantos(), await enLaCola());
        Future<MovimientoParaRendir> darCon(int cantidad, List<TramoTalonario> numeros) =>
            jefe.darParaRendir(
              eventoId: _fiesta,
              personaNombre: 'Juan Pérez',
              cantidad: cantidad,
              numeros: numeros,
              precio: 8000,
              nombrePrecio: 'Entrada anticipada',
              quien: 'Jefe',
            );
        await expectLater(
          darCon(20, const [TramoTalonario(1201, 1210), TramoTalonario(1201, 1210)]),
          throwsArgumentError,
          reason: '20 entradas con 10 números',
        );
        await expectLater(
          darCon(15, const [TramoTalonario(1201, 1210), TramoTalonario(1206, 1210)]),
          throwsArgumentError,
          reason: 'los dos tramos se pisan',
        );
        await expectLater(
          darCon(1, const [TramoTalonario(1210, 1201), TramoTalonario(1205, 1216)]),
          throwsArgumentError,
          reason: 'un tramo al revés',
        );
        await expectLater(
          darCon(5, const [TramoTalonario(0, 4)]),
          throwsArgumentError,
          reason: 'el talonario empieza en 1',
        );
        expect((await cuantos(), await enLaCola()), antes);
      });

      test('RENDIR y NO VOLVIERON: tramos que se pisan no escriben nada', () async {
        final bloque = await dar();
        final antes = (await cuantos(), await enLaCola());
        await expectLater(
          rendir(bloque, devueltos: const [
            TramoTalonario(1216, 1220),
            TramoTalonario(1216, 1220),
          ]),
          throwsArgumentError,
          reason: 'diez devueltas con cinco números',
        );
        await expectLater(
          rendir(bloque, vendidas: 5, devueltos: const [
            TramoTalonario(1211, 1220),
            TramoTalonario(1219, 1220),
          ]),
          throwsArgumentError,
        );
        await expectLater(
          perder(bloque, cantidad: 4, numeros: const [
            TramoTalonario(1219, 1220),
            TramoTalonario(1219, 1220),
          ]),
          throwsArgumentError,
          reason: 'cuatro perdidas con dos números',
        );
        await expectLater(
          perder(bloque, numeros: const [TramoTalonario(1220, 1219)]),
          throwsArgumentError,
          reason: 'un tramo al revés',
        );
        expect((await cuantos(), await enLaCola()), antes);
        expect(
          MovimientoParaRendir.quedanSinRendir(bloque, await vende.paraRendir(_fiesta)),
          20,
        );
      });

      test('un bloque de dos tramos: el número del hueco no vuelve; uno de cada tramo, sí',
          () async {
        final bloque = await jefe.darParaRendir(
          eventoId: _fiesta,
          personaNombre: 'Juan Pérez',
          cantidad: 20,
          numeros: const [TramoTalonario(1201, 1210), TramoTalonario(1301, 1310)],
          precio: 8000,
          nombrePrecio: 'Entrada anticipada',
          quien: 'Jefe',
        );
        final antes = (await cuantos(), await enLaCola());
        await expectLater(
          rendir(bloque, devueltos: const [TramoTalonario(1250, 1250)]),
          throwsArgumentError,
          reason: 'el 1250 está entre los dos tramos: nunca se le dio',
        );
        await expectLater(
          rendir(bloque, devueltos: const [TramoTalonario(1209, 1302)]),
          throwsArgumentError,
          reason: 'un tramo que cruza el hueco',
        );
        await expectLater(
          perder(bloque, numeros: const [TramoTalonario(1250, 1250)]),
          throwsArgumentError,
        );
        expect((await cuantos(), await enLaCola()), antes);
        await rendir(bloque, devueltos: const [
          TramoTalonario(1210, 1210),
          TramoTalonario(1301, 1301),
        ]);
        expect(
          MovimientoParaRendir.quedanSinRendir(bloque, await vende.paraRendir(_fiesta)),
          18,
        );
      });

      test('regla 58: un renglón que esta versión no conoce no le resta nada al bloque',
          () async {
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
          createdAt: '2026-11-20T16:00:00.000Z',
          updatedAt: '2026-11-20T16:00:00.000Z',
        );
        await ponerComoBajado(desconocido);
        expect(
          MovimientoParaRendir.quedanSinRendir(bloque, await vende.paraRendir(_fiesta)),
          20,
        );
        await rendir(bloque, vendidas: 15, devueltos: const [TramoTalonario(1216, 1220)]);
        final conservado =
            (await vende.paraRendir(_fiesta)).singleWhere((m) => m.id == desconocido.id);
        expect(conservado.toMap(), desconocido.toMap());
      });

      test('regla 41 y 55: un bloque anulado no se rinde ni se da por perdido', () async {
        final bloque = await dar();
        await jefe.anularDeParaRendir(bloque, motivo: 'se cargó mal', quien: 'Jefe');
        final antes = await cuantos();
        await expectLater(rendir(bloque, vendidas: 1), throwsStateError);
        await expectLater(
          rendir(bloque, devueltos: const [TramoTalonario(1220, 1220)]),
          throwsStateError,
        );
        await expectLater(
          jefe.noVolvieron(bloque, cantidad: 1, motivo: 'x', quien: 'Jefe'),
          throwsStateError,
        );
        expect(await cuantos(), antes);
      });

      test('regla 55: anular dos veces deja una sola fila, con el id fijo', () async {
        final bloque = await dar();
        final primera = await jefe.anularDeParaRendir(
          bloque,
          motivo: 'se cargó mal',
          quien: 'Jefe',
        );
        expect(primera.id, UuidUtils.entradasParaRendirAnulacionId(bloque.id));
        expect(primera.anulaId, bloque.id);
        final segunda = await jefe.anularDeParaRendir(bloque, motivo: 'otro', quien: 'Otro');
        expect(segunda.toMap(), primera.toMap(), reason: 'devuelve la que ya había');
        expect(
          [for (final m in await vende.paraRendir(_fiesta)) if (m.esAnulo) m.id],
          [primera.id],
        );
      });

      test('regla 55: con algo en pie el bloque no se anula; lo vendido, en VENTAS', () async {
        final bloque = await dar();
        final r = await rendir(
          bloque,
          vendidas: 2,
          devueltos: const [TramoTalonario(1220, 1220)],
        );
        final antes = await cuantos();
        await expectLater(
          jefe.anularDeParaRendir(bloque, motivo: 'se cargó mal', quien: 'Jefe'),
          throwsStateError,
        );
        expect(await cuantos(), antes);
        await jefe.anularDeParaRendir(r.devolvio!, motivo: 'no volvió', quien: 'Jefe');
        await expectLater(
          jefe.anularDeParaRendir(bloque, motivo: 'se cargó mal', quien: 'Jefe'),
          throwsStateError,
          reason: 'lo vendido sigue en pie',
        );
        await expectLater(
          jefe.anularDeParaRendir(r.vendio!, motivo: 'x', quien: 'Jefe'),
          throwsArgumentError,
        );
        await jefe.anular(r.venta!, motivo: 'se cobró mal', devueltas: false, quien: 'Jefe');
        final anulo = await jefe.anularDeParaRendir(
          bloque,
          motivo: 'se cargó mal',
          quien: 'Jefe',
        );
        expect(anulo.anulaId, bloque.id);
      });

      test('regla 55: sin motivo no se anula, una anulación no se anula, y va sin números',
          () async {
        final bloque = await dar();
        await expectLater(
          jefe.anularDeParaRendir(bloque, motivo: '  ', quien: 'Jefe'),
          throwsArgumentError,
        );
        final anulo = await jefe.anularDeParaRendir(bloque, motivo: 'mal', quien: 'Jefe');
        expect(anulo.numeros, isNull, reason: 'los del bloque se leen por anulaId');
        expect(anulo.cantidad, 20);
        await expectLater(
          jefe.anularDeParaRendir(anulo, motivo: 'otra', quien: 'Jefe'),
          throwsArgumentError,
        );
        expect(await vende.paraRendir(_fiesta), hasLength(2));
      });

      test('el precio, el nombre y la fiesta son los del bloque guardado, no los de la pantalla',
          () async {
        final bloque = await dar();
        final tocado = MovimientoParaRendir.fromMap({
          ...bloque.toMap(),
          'precio': 1,
          'nombre_precio': 'Otra cosa',
        });
        final r = await rendir(tocado, vendidas: 2);
        final venta = r.venta!;
        expect(venta.renglones.single.precioLista, 8000);
        expect(venta.renglones.single.nombre, 'Entrada anticipada · para rendir');
        expect(venta.renglones.single.descuentoPct, 0);
        expect(venta.total, 16000);
        expect(venta.contratoAlumnoId, isNull, reason: 'la rendición no es de la familia');
        expect(venta.numeros, isNull, reason: 'los números los lleva el bloque');
        expect(venta.compradorNombre, 'Juan Pérez');
        expect(venta.eventoId, _fiesta);
        expect(venta.cajaEntradasId, caja.id);
        expect(r.vendio!.cajaEntradasId, caja.id);
        expect(r.vendio!.ventaId, venta.id);

        // Con la caja tocada en la pantalla, la venta va con la fiesta de la
        // caja guardada.
        final cajaTocada = CajaEntradas.fromMap({
          ...caja.toMap(),
          'evento_id': _otraFiesta,
        });
        final otra = await rendir(bloque, vendidas: 1, conCaja: cajaTocada);
        expect(otra.venta!.eventoId, _fiesta);
        expect(await vende.ventas(_otraFiesta), isEmpty);
      });

      test('solo devolviendo, la caja va solo si está acá y abierta; nunca una que no existe',
          () async {
        final bloque = await dar();
        final ajena = CajaEntradas.abrir(eventoId: _fiesta, ahora: ahora);
        expect(
          (await rendir(
            bloque,
            devueltos: const [TramoTalonario(1220, 1220)],
            conCaja: ajena,
          ))
              .devolvio!
              .cajaEntradasId,
          isNull,
        );
        expect(
          (await rendir(
            bloque,
            devueltos: const [TramoTalonario(1219, 1219)],
            conCaja: caja,
          ))
              .devolvio!
              .cajaEntradasId,
          caja.id,
        );
        await vende.cerrarCaja(caja, efectivoContado: 0, diferencia: 0, quien: 'Carla');
        expect(
          (await rendir(
            bloque,
            devueltos: const [TramoTalonario(1218, 1218)],
            conCaja: caja,
          ))
              .devolvio!
              .cajaEntradasId,
          isNull,
          reason: 'la pantalla tiene la caja abierta en la mano: vale la guardada',
        );
        // Y con la caja cerrada o ajena no se cobra.
        await expectLater(rendir(bloque, vendidas: 1), throwsStateError);
        await expectLater(rendir(bloque, vendidas: 1, conCaja: ajena), throwsStateError);
      });

      test('una caja de otra fiesta no cobra, aunque la pantalla traiga el bloque tocado',
          () async {
        final bloque = await dar();
        final deOtra = await vende.abrirCaja(
          eventoId: _otraFiesta,
          operadorId: _carla,
          operadorNombre: 'Carla',
        );
        final tocado = MovimientoParaRendir.fromMap({
          ...bloque.toMap(),
          'evento_id': _otraFiesta,
        });
        final antes = await cuantos();
        await expectLater(rendir(tocado, vendidas: 2, conCaja: deOtra), throwsArgumentError);
        await expectLater(
          rendir(tocado, devueltos: const [TramoTalonario(1220, 1220)], conCaja: deOtra),
          throwsArgumentError,
        );
        expect(await cuantos(), antes);
        expect(await vende.ventas(_otraFiesta), isEmpty);
      });
    });
  }

  // ── Los dos equipos de la ventana de prueba ──────────────────────────────────
  //
  // `_sube('entradas_para_rendir')`, el `rendir` que sube la venta y sus
  // renglones juntos, y el caso de `ponerDeOtroEquipo`: lo que el recorrido de
  // la etapa 7 da por hecho.
  group('los dos equipos de la ventana de prueba', () {
    late LadosDeLaVenta lados;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      lados = await armarLados(
        demoraDeSubida: Duration.zero,
        hoy: () => DateTime.utc(2026, 11, 20, 12),
        relojDelJefe: () => DateTime(2026, 11, 20, 12),
      );
    });
    tearDown(() => lados.dispose());

    Future<CajaEntradas> cajaDeCarla() => lados.tablet.abrirCaja(
          eventoId: idFiestaEntrega,
          operadorId: lados.operadora.id,
          operadorNombre: 'Carla',
        );

    Future<MovimientoParaRendir> darEnLaPc() => lados.pc.darParaRendir(
          eventoId: idFiestaEntrega,
          personaNombre: 'Juan Pérez',
          cantidad: 20,
          numeros: const [TramoTalonario(1201, 1220)],
          precio: 8000,
          nombrePrecio: 'Entrada anticipada',
          quien: 'Jefe',
        );

    Future<Set<String>> ids(EntradasDeUnEquipo e) async =>
        {for (final m in await e.paraRendir(idFiestaEntrega)) m.id};

    test('el jefe da en la PC, Carla rinde en la tablet sin internet, y al volver la PC lo ve',
        () async {
      expect(lados.hayInternet, isTrue);
      final caja = await cajaDeCarla();
      final bajadas = <Set<String>>[];
      final escucha = lados.nube.tablet.motor.bajo.stream.listen(bajadas.add);
      addTearDown(escucha.cancel);
      final bloque = await darEnLaPc();
      expect(lados.pc.pendientes, isEmpty, reason: 'con internet, subió');
      expect(await ids(lados.tablet), {bloque.id}, reason: 'y la tablet lo bajó');
      await Future<void>.delayed(Duration.zero);
      expect(bajadas, anyElement(contains('entradas_para_rendir')),
          reason: 'por su tabla: lo que mira esa tabla se relee');

      lados.cambiarInternet(); // CORTAR INTERNET
      expect(lados.hayInternet, isFalse);
      final r = await lados.tablet.rendir(
        caja: caja,
        bloque: bloque,
        vendidas: 15,
        devueltas: 5,
        numerosDevueltos: const [TramoTalonario(1216, 1220)],
        medio: MedioBarra.efectivo,
        efectivo: 15 * 8000,
        quien: 'Carla',
      );
      expect(
        [for (final p in lados.tablet.pendientes) p.tabla],
        ['entradas_ventas', 'entradas_para_rendir', 'entradas_para_rendir'],
        reason: 'la venta y sus dos renglones, juntos en la cola',
      );
      expect(await lados.tablet.ventasSinSubir(), 1);
      expect(await lados.tablet.cambiosSinSubir(), 2, reason: 'el vendió y el devolvió');
      expect(await ids(lados.pc), {bloque.id}, reason: 'sin internet, nada cruza');

      lados.cambiarInternet(); // VOLVER EL INTERNET
      expect(lados.tablet.pendientes, isEmpty);
      final enLaPc = await lados.pc.paraRendir(idFiestaEntrega);
      expect({for (final m in enLaPc) m.id}, {bloque.id, r.vendio!.id, r.devolvio!.id});
      expect(MovimientoParaRendir.quedanSinRendir(bloque, enLaPc), 0);
      expect(
        [for (final v in await lados.pc.ventasDeLaCaja(caja.id)) v.id],
        contains(r.venta!.id),
        reason: 'la plata, en la caja de Carla',
      );
    });

    test('sin internet, lo que da el jefe y lo que no volvió quedan en su cola como cambios',
        () async {
      lados.cambiarInternet(); // CORTAR INTERNET
      final bloque = await darEnLaPc();
      final perdidas = await lados.pc.noVolvieron(
        bloque,
        cantidad: 1,
        motivo: 'la perdió',
        quien: 'Jefe',
      );
      expect(
        [for (final p in lados.pc.pendientes) p.tabla],
        ['entradas_para_rendir', 'entradas_para_rendir'],
      );
      expect(await lados.pc.cambiosSinSubir(), 2);
      expect(await lados.pc.ventasSinSubir(), 0);
      expect(await ids(lados.tablet), isEmpty, reason: 'la tablet no lo conoce todavía');

      lados.cambiarInternet(); // VOLVER EL INTERNET
      expect(lados.pc.pendientes, isEmpty);
      expect(await ids(lados.tablet), {bloque.id, perdidas.id});
    });

    test('dos equipos rinden el mismo bloque sin internet: al juntarse están las dos',
        () async {
      final caja = await cajaDeCarla();
      final bloque = await darEnLaPc();
      lados.cambiarInternet(); // CORTAR INTERNET
      final enLaTablet = await lados.tablet.rendir(
        caja: caja,
        bloque: bloque,
        vendidas: 15,
        efectivo: 15 * 8000,
        quien: 'Carla',
      );
      final cajaDelJefe = await lados.pc.abrirCaja(
        eventoId: idFiestaEntrega,
        operadorNombre: 'Jefe',
      );
      final enLaPc = await lados.pc.rendir(
        caja: cajaDelJefe,
        bloque: bloque,
        vendidas: 10,
        efectivo: 10 * 8000,
        quien: 'Jefe',
      );
      lados.cambiarInternet(); // VOLVER EL INTERNET

      // No se puede evitar sin internet; lo avisa PARA RENDIR ("rindió de
      // más"). Acá, que ninguna de las dos se pierda.
      for (final equipo in [lados.tablet, lados.pc]) {
        final movimientos = await equipo.paraRendir(idFiestaEntrega);
        final vendidas = MovimientoParaRendir.vigentesDe(bloque, movimientos)
            .fold<int>(0, (s, m) => s + m.cantidad);
        expect(vendidas, 25, reason: equipo.equipo);
        expect(MovimientoParaRendir.quedanSinRendir(bloque, movimientos), 0);
        final ventas = {for (final v in await equipo.ventas(idFiestaEntrega)) v.id};
        expect(ventas, containsAll([enLaTablet.venta!.id, enLaPc.venta!.id]));
      }
    });

    test('lo que no volvió cruza, y anular lo mismo en los dos equipos deja una sola fila',
        () async {
      final bloque = await darEnLaPc();
      final r = await lados.tablet.rendir(
        bloque: bloque,
        vendidas: 0,
        devueltas: 5,
        numerosDevueltos: const [TramoTalonario(1216, 1220)],
        quien: 'Carla',
      );
      final perdidas = await lados.pc.noVolvieron(
        bloque,
        cantidad: 2,
        motivo: 'las perdió',
        quien: 'Jefe',
      );
      expect(await ids(lados.tablet), {bloque.id, r.devolvio!.id, perdidas.id});
      expect(await ids(lados.pc), {bloque.id, r.devolvio!.id, perdidas.id});

      // Con internet: lo que anuló el jefe ya está en la tablet, y anularlo de
      // nuevo allá no escribe ni sube nada.
      final anuloDelJefe = await lados.pc.anularDeParaRendir(
        perdidas,
        motivo: 'aparecieron',
        quien: 'Jefe',
      );
      expect(await ids(lados.tablet), contains(anuloDelJefe.id));
      final escriturasAntes = lados.tablet.escrituras;
      final otraVez = await lados.tablet.anularDeParaRendir(
        perdidas,
        motivo: 'otra vez',
        quien: 'Carla',
      );
      expect(otraVez.toMap(), anuloDelJefe.toMap(), reason: 'devuelve la que bajó');
      expect(lados.tablet.escrituras, escriturasAntes);
      final enLaPc = (await lados.pc.paraRendir(idFiestaEntrega))
          .singleWhere((m) => m.id == anuloDelJefe.id);
      expect(enLaPc.motivo, 'aparecieron', reason: 'la tablet no subió otra encima');

      // Sin internet, los dos anulan el "devolvió": el id es fijo, así que al
      // juntarse queda una sola fila en cada equipo.
      lados.cambiarInternet(); // CORTAR INTERNET
      final anuloEnLaPc = await lados.pc.anularDeParaRendir(
        r.devolvio!,
        motivo: 'no las trajo',
        quien: 'Jefe',
      );
      final anuloEnLaTablet = await lados.tablet.anularDeParaRendir(
        r.devolvio!,
        motivo: 'se cargó mal',
        quien: 'Carla',
      );
      expect(anuloEnLaTablet.id, anuloEnLaPc.id);
      expect([for (final p in lados.tablet.pendientes) p.tabla], ['entradas_para_rendir']);
      expect([for (final p in lados.pc.pendientes) p.tabla], ['entradas_para_rendir']);
      lados.cambiarInternet(); // VOLVER EL INTERNET
      for (final equipo in [lados.tablet, lados.pc]) {
        final anulos = [
          for (final m in await equipo.paraRendir(idFiestaEntrega))
            if (m.esAnulo && m.anulaId == r.devolvio!.id) m,
        ];
        expect(anulos, hasLength(1), reason: equipo.equipo);
        expect(anulos.single.id, UuidUtils.entradasParaRendirAnulacionId(r.devolvio!.id));
      }
    });
  });
}
