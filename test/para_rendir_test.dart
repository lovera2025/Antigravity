// Las cuentas de las entradas para rendir (consignación, 21-nov-2026), sin
// pantalla ni base: lo que se llevó cada uno, lo que rindió, lo que devolvió, lo
// que no volvió y lo que le queda; los números que siguen ocupados; las reglas
// de DAR y RENDIR, y los avisos. Reglas 36, 37, 38, 39, 43, 44, 46, 47, 48, 49 y
// 58 de `docs/SPEC_entradas_para_rendir_2026-11-20.md` (sección 9).
//
// Lo que cuentan las cuentas tiene que dar lo mismo que el freno del
// repositorio (`MovimientoParaRendir.quedanSinRendir`), y el renglón que arma
// la pantalla para "A cobrar", lo mismo que guarda cada repositorio: si no, la
// pantalla diría una cosa y la caja cobraría otra.
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/entradas/cuentas/lugares_de_la_familia.dart';
import 'package:arguello_events/features/entradas/cuentas/numeros_de_entradas.dart';
import 'package:arguello_events/features/entradas/cuentas/para_rendir.dart';
import 'package:arguello_events/features/entradas/cuentas/pedido_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_local.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/models/entradas_retiro.dart' show TramoTalonario;

import '../tool/venta_entradas_prueba.dart' show EntradasDeUnEquipo;
import 'helpers/entradas_en_memoria.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _familia = 'c0000000-0000-4000-8000-000000000001';
const _otraFamilia = 'c0000000-0000-4000-8000-000000000002';
const _carla = 'a0000000-0000-4000-8000-000000000001';

/// El lunes 16-nov, cuando el jefe da las entradas.
final _lunes = DateTime.utc(2026, 11, 16, 15);
var _segundos = 0;

/// Cada cosa, un segundo después de la anterior.
DateTime _t() => _lunes.add(Duration(seconds: ++_segundos));

TramoTalonario _del(int desde, int hasta) => TramoTalonario(desde, hasta);

/// El jefe le da [cantidad] desde [desde] a [persona], a $8.000 la anticipada.
MovimientoParaRendir _dar({
  String persona = 'PÉREZ, JUAN',
  int desde = 1201,
  int cantidad = 20,
  List<TramoTalonario>? tramos,
  double precio = 8000,
  String nombrePrecio = 'Entrada anticipada',
  String? alumno,
  String? contacto,
}) =>
    MovimientoParaRendir.dio(
      eventoId: _fiesta,
      personaNombre: persona,
      personaContacto: contacto,
      contratoAlumnoId: alumno,
      cantidad: cantidad,
      tramos: tramos ?? [_del(desde, desde + cantidad - 1)],
      precio: precio,
      nombrePrecio: nombrePrecio,
      hechoPor: 'Jefe',
      ahora: _t(),
    );

/// El bloque de [dio] solo, para armar con él el renglón de una rendición.
BloqueParaRendir _soloElBloque(MovimientoParaRendir dio) =>
    ParaRendir.de(movimientos: [dio], ventas: const [], anulaciones: const [])
        .bloques
        .single;

/// Una rendición de [vendidas] de [dio] cobrada en efectivo por [caja]: la
/// venta (con el renglón de las cuentas) y su renglón `vendio`.
({VentaEntradas venta, MovimientoParaRendir vendio}) _rendicion(
  MovimientoParaRendir dio,
  int vendidas, {
  String caja = 'caja-carla',
  int numero = 1,
}) {
  final renglon = ParaRendir.renglon(_soloElBloque(dio), vendidas);
  final venta = VentaEntradas.nueva(
    cajaEntradasId: caja,
    eventoId: _fiesta,
    numero: numero,
    compradorNombre: dio.personaNombre!,
    renglones: [renglon],
    medio: MedioBarra.efectivo,
    efectivo: renglon.subtotal,
    ahora: _t(),
  );
  return (
    venta: venta,
    vendio: MovimientoParaRendir.vendio(
      dio,
      cantidad: vendidas,
      ventaId: venta.id,
      cajaEntradasId: caja,
      hechoPor: 'Carla',
      ahora: _t(),
    ),
  );
}

MovimientoParaRendir _devolvio(MovimientoParaRendir dio, List<TramoTalonario> tramos) =>
    MovimientoParaRendir.devolvio(dio, tramos: tramos, hechoPor: 'Carla', ahora: _t());

MovimientoParaRendir _noVolvieron(
  MovimientoParaRendir dio,
  int cantidad, [
  List<TramoTalonario> tramos = const [],
]) =>
    MovimientoParaRendir.noVolvieron(
      dio,
      cantidad: cantidad,
      tramos: tramos,
      motivo: 'dice que las perdió',
      hechoPor: 'Jefe',
      ahora: _t(),
    );

MovimientoParaRendir _anulo(MovimientoParaRendir m) =>
    MovimientoParaRendir.anulo(m, motivo: 'se cargó mal', hechoPor: 'Jefe', ahora: _t());

/// Un renglón que escribió una versión más nueva: un `que` que esta no conoce,
/// con cantidad, números y hasta un "anula" que apunta al bloque.
MovimientoParaRendir _desconocido(MovimientoParaRendir dio, {String? id}) {
  final iso = _t().toIso8601String();
  return MovimientoParaRendir(
    id: id ?? UuidUtils.generate(),
    eventoId: _fiesta,
    bloqueId: dio.id,
    queClave: 'regalo',
    personaNombre: dio.personaNombre,
    cantidad: 7,
    numeros: dio.numeros,
    precio: 1,
    anulaId: dio.id,
    ventaId: 'v-que-no-existe',
    motivo: 'una recompensa',
    createdAt: iso,
    updatedAt: iso,
  );
}

/// Una venta común de las anticipadas, con sus números.
VentaEntradas _venta(String comprador, List<TramoTalonario> numeros) {
  final cantidad = numeros.fold(0, (s, t) => s + t.cantidad);
  return VentaEntradas.nueva(
    cajaEntradasId: 'caja-carla',
    eventoId: _fiesta,
    numero: 1,
    compradorNombre: comprador,
    renglones: [
      RenglonEntradas.suelta(
          nombre: 'Entrada anticipada', precioLista: 8000, cantidad: cantidad),
    ],
    medio: MedioBarra.efectivo,
    efectivo: 8000.0 * cantidad,
    numeros: TramoTalonario.aTexto(numeros),
    ahora: _t(),
  );
}

AnulacionEntradas _anulada(VentaEntradas v, {bool devueltas = false}) =>
    AnulacionEntradas.de(v, motivo: 'se cobró dos veces', devueltas: devueltas, ahora: _t());

ParaRendir _cuenta(
  List<MovimientoParaRendir> movimientos, {
  List<VentaEntradas> ventas = const [],
  List<AnulacionEntradas> anulaciones = const [],
}) =>
    ParaRendir.de(movimientos: movimientos, ventas: ventas, anulaciones: anulaciones);

/// Los precios de la fiesta: $10.000 la general y $8.000 la anticipada hasta
/// el miércoles 18-nov.
ConfigEntradas _precios({
  double? anticipada = 8000,
  String? hasta = '2026-11-18',
  double general = 10000,
}) =>
    ConfigEntradas.vacia(_fiesta, ahora: _lunes).conPrecios(
      valorEntrada: general,
      precioAnticipada: anticipada,
      anticipadaHasta: anticipada == null ? null : hasta,
      descuentoLugaresPct: 50,
      recargoPct: 0,
      descuentoAMano: false,
    );

/// Todo lo que las cuentas dicen de una fiesta, para comparar dos de ellas.
List<Object?> _foto(ParaRendir p) => [
      for (final b in p.bloques)
        [
          b.id,
          b.anulado,
          b.vendidas,
          b.devueltas,
          b.noVolvieron,
          b.sinRendir,
          b.rindioDeMas,
          b.plataRendida,
          b.plataQueFalta,
          b.plataNoVolvio,
          b.plataEnCamino,
          b.tieneMovimientos,
          '${b.numerosOcupados}',
          '${b.numerosQueTiene}',
          [for (final m in b.movimientos) '${m.movimiento.id}:${m.cuenta}'],
        ],
      [for (final per in p.porPersona) '${per.clave}:${per.sinRendir}'],
      [for (final a in p.avisos) a.texto],
      [for (final c in p.cruces) c.texto],
      '${p.ocupados}',
      p.personas,
      p.sinRendir,
      p.plataQueFalta,
      p.noVolvieron,
      p.plataNoVolvio,
    ];

void main() {
  group('regla 37: con la anticipada vigente, queda "Entrada anticipada" con su precio',
      () {
    final precios = _precios();

    test('mientras rige, la anticipada; su último día entero; después, la general', () {
      expect(ParaRendir.precioParaDar(precios, DateTime(2026, 11, 16, 12)),
          (precio: 8000.0, nombre: 'Entrada anticipada'));
      expect(ParaRendir.precioParaDar(precios, DateTime(2026, 11, 18, 23, 59)),
          (precio: 8000.0, nombre: 'Entrada anticipada'),
          reason: 'el último día rige entero');
      expect(ParaRendir.precioParaDar(precios, DateTime(2026, 11, 19)),
          (precio: 10000.0, nombre: 'Entrada'));
      expect(ParaRendir.precioParaDar(_precios(anticipada: null), DateTime(2026, 11, 16)),
          (precio: 10000.0, nombre: 'Entrada'));
    });

    test('sin precio no hay nada que dar', () {
      expect(ParaRendir.precioParaDar(null, DateTime(2026, 11, 16)), isNull);
      final sinPrecio = ConfigEntradas.vacia(_fiesta, ahora: _lunes);
      expect(ParaRendir.precioParaDar(sinPrecio, DateTime(2026, 11, 16)), isNull);
    });

    test('es el mismo precio y el mismo nombre con que VENDER vende ese día', () {
      for (final dia in [DateTime(2026, 11, 16), DateTime(2026, 11, 18), DateTime(2026, 11, 19)]) {
        final venta = PedidoDeEntradas.nuevo(config: precios, hoyAr: dia)
            .paraAlguienDeAfuera()
            .conSueltas(1)
            .renglones
            .single;
        final dar = ParaRendir.precioParaDar(precios, dia)!;
        expect(dar.precio, venta.precioLista, reason: '$dia');
        expect(dar.nombre, venta.nombre, reason: '$dia');
      }
    });

    test('lo que se da ese día se rinde como "Entrada anticipada", a su precio', () {
      final hoy = ParaRendir.precioParaDar(precios, DateTime(2026, 11, 16))!;
      final dio = _dar(precio: hoy.precio, nombrePrecio: hoy.nombre);
      final renglon = ParaRendir.renglon(_soloElBloque(dio), 3);
      expect(renglon.nombre, 'Entrada anticipada · para rendir');
      expect(renglon.precio, 8000);
    });
  });

  group('regla 36: se rinde al precio y con el nombre del día en que se las llevó', () {
    test('aunque venza la anticipada o el jefe ponga GENERAL con otro precio', () {
      final dio = _dar(precio: 8000, nombrePrecio: 'Entrada anticipada');
      // Al otro día venció la anticipada y el jefe subió la general a $12.000.
      final despues = _precios(anticipada: null, general: 12000);
      expect(ParaRendir.precioParaDar(despues, DateTime(2026, 11, 20))!.precio, 12000);

      final bloque = _soloElBloque(dio);
      final renglon = ParaRendir.renglon(bloque, 15);
      expect(renglon.nombre, 'Entrada anticipada · para rendir');
      expect(renglon.precioLista, 8000);
      expect(renglon.precio, 8000);
      expect(bloque.precioDeCadaUna, 8000);
      expect(bloque.plataQueFalta, 160000, reason: 'las 20 al precio del lunes');

      final r = _rendicion(dio, 15);
      final p = _cuenta([dio, r.vendio], ventas: [r.venta]);
      expect(p.bloques.single.plataRendida, 120000);
      expect(p.bloques.single.plataQueFalta, 40000);
    });

    test('dado con la general, se rinde con la general', () {
      final dio = _dar(precio: 10000, nombrePrecio: 'Entrada');
      final renglon = ParaRendir.renglon(_soloElBloque(dio), 2);
      expect(renglon.nombre, 'Entrada · para rendir');
      expect(renglon.subtotal, 20000);
    });
  });

  group('regla 38: sin comisión ni descuento', () {
    test('el renglón va sin descuento y vale lo vendido por el precio', () {
      final bloque = _soloElBloque(_dar(precio: 8000));
      for (final n in [1, 7, 15, 20]) {
        final r = ParaRendir.renglon(bloque, n);
        expect(r.tipo, TipoRenglonEntradas.suelta);
        expect(r.descuentoPct, 0);
        expect(r.precio, r.precioLista);
        expect(r.descontado, 0);
        expect(r.cantidad, n);
        expect(r.subtotal, 8000.0 * n);
      }
    });

    test('la venta de la rendición cierra con ese renglón: total = vendidas × precio', () {
      final r = _rendicion(_dar(), 15);
      expect(r.venta.total, 120000);
      expect(r.venta.descuento, 0);
      expect(r.venta.cantidad, 15);
    });
  });

  group('regla 39: la venta de la rendición no es de la familia', () {
    test('rinde un alumno: la venta va sin familia y A PAGAR no cambia', () async {
      final repo = EntradasEnMemoria();
      final caja = await repo.abrirCaja(
          eventoId: _fiesta, operadorId: _carla, operadorNombre: 'Carla');
      final dio = await repo.darParaRendir(
        eventoId: _fiesta,
        personaNombre: 'GÓMEZ, LUCÍA',
        contratoAlumnoId: _familia,
        cantidad: 10,
        numeros: [_del(1221, 1230)],
        precio: 8000,
        nombrePrecio: 'Entrada anticipada',
        quien: 'Jefe',
      );
      final antes = _cuenta(await repo.paraRendir(_fiesta));
      expect(antes.bloques.single.esDeUnAlumno, isTrue);
      final renglon = ParaRendir.renglon(antes.bloques.single, 6);
      final r = await repo.rendir(
        caja: caja,
        bloque: dio,
        vendidas: 6,
        efectivo: renglon.subtotal,
        quien: 'Carla',
      );
      expect(r.venta!.contratoAlumnoId, isNull);
      final ventas = await repo.ventas(_fiesta);
      final anulaciones = await repo.anulaciones(_fiesta);
      expect(sueltasPorFamilia(ventas, anulaciones)[_familia], isNull,
          reason: 'si fuera de la familia, le descontaría esas entradas de lo que '
              'agregó después del sorteo');
      expect(compradasPorFamilia(ventas, anulaciones)[_familia], isNull);
    });

    test('el renglón es una entrada suelta, nunca de un lugar adicional', () {
      final bloque = _soloElBloque(_dar(alumno: _familia));
      expect(ParaRendir.renglon(bloque, 4).tipo, TipoRenglonEntradas.suelta);
    });

    // 21-nov-2026: la venta sube antes que su `vendio`, así que VENTAS tiene
    // que reconocerla por la venta misma: sin familia y con su renglón.
    test('la venta de una rendición se reconoce sin su "vendió"; una venta común, no', () {
      final dio = _dar();
      expect(ParaRendir.esVentaDeRendicion(_rendicion(dio, 3).venta), isTrue);
      expect(ParaRendir.esVentaDeRendicion(_venta('PÉREZ, JUAN', [_del(1, 2)])), isFalse);
      final deUnaFamilia = VentaEntradas.nueva(
        cajaEntradasId: 'caja-carla',
        eventoId: _fiesta,
        numero: 1,
        contratoAlumnoId: _familia,
        compradorNombre: 'PÉREZ, JUAN',
        renglones: [ParaRendir.renglon(_soloElBloque(dio), 1)],
        medio: MedioBarra.efectivo,
        efectivo: 8000,
        ahora: _t(),
      );
      expect(ParaRendir.esVentaDeRendicion(deUnaFamilia), isFalse,
          reason: 'una rendición nunca es de una familia');
    });
  });

  // Las tres implementaciones del repositorio guardan lo mismo que dicen las
  // cuentas (reglas 36, 38 y 39): la pantalla arma el cobro con
  // `ParaRendir.renglon` y el repositorio arma la venta por su cuenta.
  group('lo que guarda cada repositorio es lo que dicen las cuentas', () {
    late Directory docs;
    late DateTime ahora;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = Directory.systemTemp.createTempSync('para_rendir_cuentas');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => docs.path,
          );
      ahora = DateTime.utc(2026, 11, 16, 15);
    });

    tearDown(() async {
      await LocalDatabase.close();
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    final repositorios = <String, Object Function()>{
      'EntradasLocal (la base del equipo)': () => EntradasLocal(
            equipo: () async => 'pc-1',
            reloj: () => ahora = ahora.add(const Duration(seconds: 1)),
          ),
      'EntradasEnMemoria': () => EntradasEnMemoria(),
      'EntradasDeUnEquipo (la ventana de prueba)': () =>
          EntradasDeUnEquipo(equipo: 'pc-1'),
    };

    for (final MapEntry(key: nombre, value: armar) in repositorios.entries) {
      test('$nombre: el renglón, la plata, sin familia y lo que queda', () async {
        final repo = armar();
        final vende = repo as EntradasDeLaCaja;
        final jefe = repo as EntradasDelJefe;
        Future<ParaRendir> leer() async => ParaRendir.de(
              movimientos: await vende.paraRendir(_fiesta),
              ventas: await vende.ventas(_fiesta),
              anulaciones: await vende.anulaciones(_fiesta),
            );

        final caja = await vende.abrirCaja(
            eventoId: _fiesta, operadorId: _carla, operadorNombre: 'Carla');
        final hoy = ParaRendir.precioParaDar(_precios(), DateTime(2026, 11, 16))!;
        final dio = await jefe.darParaRendir(
          eventoId: _fiesta,
          personaNombre: 'GÓMEZ, LUCÍA',
          contratoAlumnoId: _familia,
          cantidad: 20,
          numeros: [_del(1201, 1220)],
          precio: hoy.precio,
          nombrePrecio: hoy.nombre,
          quien: 'Jefe',
        );

        // Como lo haría la pantalla: el renglón y los números propuestos de
        // las cuentas, y el cobro por lo que dice el renglón.
        final antes = (await leer()).bloques.single;
        final renglon = ParaRendir.renglon(antes, 15);
        final devueltos = ParaRendir.proponerDevueltos(antes, 5);
        expect(devueltos, [_del(1216, 1220)]);
        expect(
          ParaRendir.errorAlRendir(antes,
              vendidas: 15, devueltas: 5, numerosDevueltos: devueltos, hayCaja: true),
          isNull,
        );
        final r = await vende.rendir(
          caja: caja,
          bloque: dio,
          vendidas: 15,
          devueltas: 5,
          numerosDevueltos: devueltos,
          medio: MedioBarra.efectivo,
          efectivo: renglon.subtotal,
          quien: 'Carla',
        );
        expect(r.venta!.renglones.single, renglon,
            reason: 'el mismo nombre, precio, descuento y cantidad');
        expect(r.venta!.total, renglon.subtotal);
        expect(r.venta!.contratoAlumnoId, isNull);
        expect(r.venta!.numeros, isNull, reason: 'los números los lleva el bloque');
        // VENTAS la reconoce también antes de que llegue su `vendio`
        // (21-nov-2026): por la venta misma.
        expect(ParaRendir.esVentaDeRendicion(r.venta!), isTrue);

        final despues = await leer();
        final b = despues.bloques.single;
        expect(b.vendidas, 15);
        expect(b.devueltas, 5);
        expect(b.sinRendir, 0);
        expect(b.rindioTodo, isTrue);
        expect(b.plataRendida, 120000);
        expect(b.numerosOcupados, [_del(1201, 1215)]);
        expect(despues.bloqueDeLaVenta(r.venta!.id)?.id, dio.id);
        final movimientos = await vende.paraRendir(_fiesta);
        expect(
          b.sinRendir,
          MovimientoParaRendir.quedanSinRendir(dio, movimientos),
        );
      });
    }
  });

  group('lo que queda sin rendir da lo mismo que el freno del repositorio', () {
    test('en 300 historias al azar, con dos equipos, anulaciones y renglones nuevos', () {
      final azar = Random(20261121);
      // Que las historias pasen por lo difícil: si no, la prueba no prueba nada.
      var conDeMas = 0, anulados = 0, enCamino = 0, ventasAnuladas = 0, conDevueltos = 0;
      var anuladosConAlgo = 0;
      for (var h = 0; h < 300; h++) {
        final filas = <MovimientoParaRendir>[];
        final ventas = <VentaEntradas>[];
        final anulaciones = <AnulacionEntradas>[];
        final dios = <MovimientoParaRendir>[];
        var desde = 1;
        for (var i = 0; i < 1 + azar.nextInt(3); i++) {
          final cantidad = 1 + azar.nextInt(10);
          final d = _dar(persona: 'PERSONA $i, UNA', desde: desde, cantidad: cantidad);
          desde += cantidad + azar.nextInt(3);
          dios.add(d);
          filas.add(d);
        }
        void anular(MovimientoParaRendir m) {
          final a = _anulo(m);
          if (!filas.any((f) => f.id == a.id)) filas.add(a);
        }

        for (var paso = 0; paso < 10; paso++) {
          final d = dios[azar.nextInt(dios.length)];
          final t = d.tramos.single;
          switch (azar.nextInt(7)) {
            case 0 || 1:
              // Rinde: a veces más de lo que le queda (dos equipos sin
              // internet); a veces su venta todavía no bajó; a veces se anula.
              final r = _rendicion(d, 1 + azar.nextInt(d.cantidad));
              filas.add(r.vendio);
              if (azar.nextInt(3) > 0) ventas.add(r.venta);
              if (azar.nextInt(4) == 0) {
                anulaciones.add(_anulada(r.venta, devueltas: azar.nextBool()));
              }
            case 2:
              final a = t.desde + azar.nextInt(t.cantidad);
              filas.add(_devolvio(d, [_del(a, a + azar.nextInt(t.hasta - a + 1))]));
            case 3:
              filas.add(_noVolvieron(d, 1 + azar.nextInt(d.cantidad)));
            case 4:
              final candidatos = [
                for (final f in filas)
                  if (f.bloqueId == d.id && (f.esDevolvio || f.esNoVolvieron)) f,
              ];
              if (candidatos.isNotEmpty) anular(candidatos[azar.nextInt(candidatos.length)]);
            case 5:
              if (azar.nextInt(3) == 0) anular(d);
            case _:
              filas.add(_desconocido(d));
          }
        }
        filas.shuffle(azar);

        final p = _cuenta(filas, ventas: ventas, anulaciones: anulaciones);
        final anuladas = {for (final a in anulaciones) a.ventaId};
        final anuladosAca = {
          for (final f in filas)
            if (f.esAnulo) f.anulaId,
        };
        // Los totales de la fiesta, a mano: solo los bloques en pie.
        var sinRendirDeLaFiesta = 0, perdidasDeLaFiesta = 0;
        for (final d in dios) {
          final b = p.bloque(d.id)!;
          expect(
            b.sinRendir,
            MovimientoParaRendir.quedanSinRendir(d, filas, ventasAnuladas: anuladas),
            reason: 'historia $h, ${d.personaNombre}',
          );
          expect(
            {
              for (final m in b.movimientos)
                if (m.cuenta) m.movimiento.id,
            },
            {
              for (final m in MovimientoParaRendir.vigentesDe(d, filas,
                  ventasAnuladas: anuladas))
                m.id,
            },
            reason: 'historia $h: lo que cuenta es lo que cuenta el repositorio',
          );
          // Y la cuenta escrita a mano, sin las del modelo.
          int suma(bool Function(MovimientoParaRendir f) es) => filas
              .where((f) => f.bloqueId == d.id && es(f))
              .fold(0, (s, f) => s + f.cantidad);
          final vendidas =
              suma((f) => f.esVendio && !anuladas.contains(f.ventaId));
          final devueltas = suma((f) => f.esDevolvio && !anuladosAca.contains(f.id));
          final perdidas = suma((f) => f.esNoVolvieron && !anuladosAca.contains(f.id));
          expect(b.vendidas, vendidas, reason: 'historia $h');
          expect(b.devueltas, devueltas, reason: 'historia $h');
          expect(b.noVolvieron, perdidas, reason: 'historia $h');
          final usadas = vendidas + devueltas + perdidas;
          final anulado = anuladosAca.contains(d.id);
          expect(b.anulado, anulado, reason: 'historia $h');
          expect(b.sinRendir, anulado ? 0 : max(0, d.cantidad - usadas),
              reason: 'historia $h');
          expect(b.rindioDeMas, anulado ? 0 : max(0, usadas - d.cantidad),
              reason: 'historia $h');
          // Su persona (cada bloque es de otra): un bloque anulado no le suma
          // nada, aunque tenga algo rendido, devuelto o perdido.
          final persona = p.porPersona.singleWhere((per) => per.bloques.single.id == d.id);
          expect(
            [
              persona.seLlevo,
              persona.vendidas,
              persona.devueltas,
              persona.noVolvieron,
              persona.sinRendir,
              persona.plataRendida,
              persona.plataNoVolvio,
              persona.rindioTodo,
            ],
            anulado
                ? [0, 0, 0, 0, 0, 0.0, 0.0, false]
                : [
                    d.cantidad,
                    vendidas,
                    devueltas,
                    perdidas,
                    max(0, d.cantidad - usadas),
                    vendidas * 8000.0,
                    perdidas * 8000.0,
                    usadas == d.cantidad,
                  ],
            reason: 'historia $h, ${d.personaNombre}',
          );
          if (!anulado) {
            sinRendirDeLaFiesta += max(0, d.cantidad - usadas);
            perdidasDeLaFiesta += perdidas;
          }
          if (b.rindioDeMas > 0) conDeMas++;
          if (b.anulado) anulados++;
          if (anulado && usadas > 0) anuladosConAlgo++;
          if (b.plataEnCamino) enCamino++;
          if (b.devueltas > 0) conDevueltos++;
          if (b.movimientos.any((m) => m.anulacionDeLaVenta != null)) ventasAnuladas++;
        }
        expect(
          [p.sinRendir, p.plataQueFalta, p.noVolvieron, p.plataNoVolvio],
          [
            sinRendirDeLaFiesta,
            sinRendirDeLaFiesta * 8000.0,
            perdidasDeLaFiesta,
            perdidasDeLaFiesta * 8000.0,
          ],
          reason: 'historia $h: los totales de la fiesta, sin los bloques anulados',
        );
      }
      expect(conDeMas, greaterThan(20));
      expect(anulados, greaterThan(20));
      expect(anuladosConAlgo, greaterThan(20));
      expect(enCamino, greaterThan(20));
      expect(ventasAnuladas, greaterThan(20));
      expect(conDevueltos, greaterThan(20));
    });
  });

  group('regla 43: VENDER no vende un número que está en manos de alguien', () {
    final dio = _dar(persona: 'PÉREZ, JUAN', desde: 1201, cantidad: 20);
    final p = _cuenta([dio]);

    test('los números del bloque, a nombre de quien los tiene ", para rendir"', () {
      expect(NumerosDeEntradas.ocupadosParaRendir(p.bloques), {
        'PÉREZ, JUAN, para rendir': [_del(1201, 1220)],
      });
    });

    test('con las palabras de siempre', () {
      expect(
        NumerosDeEntradas.error(
            tramos: [_del(1205, 1206)], cantidad: 2, ocupados: p.ocupados),
        'El 1205 ya se le dio a PÉREZ, JUAN, para rendir (1201 al 1220).',
        reason: 'un solo paréntesis: el del tramo (21-nov-2026)',
      );
      expect(
        NumerosDeEntradas.error(
            tramos: [_del(1221, 1222)], cantidad: 2, ocupados: p.ocupados),
        isNull,
      );
      final pedido = PedidoDeEntradas.nuevo(
        config: _precios(),
        hoyAr: DateTime(2026, 11, 16),
        ocupados: p.ocupados,
      )
          .paraAlguienDeAfuera()
          .conSueltas(2)
          .conComprador('LÓPEZ, ANA')
          .conTramos([_del(1219, 1220)]);
      expect(pedido.falta,
          'El 1219 ya se le dio a PÉREZ, JUAN, para rendir (1201 al 1220).');
    });

    test('lo ocupado al vender junta lo vendido y lo que está para rendir', () {
      final venta = _venta('LÓPEZ, ANA', [_del(1300, 1301)]);
      final conVenta = _cuenta([dio], ventas: [venta]);
      expect(conVenta.ocupados, {
        'LÓPEZ, ANA': [_del(1300, 1301)],
        'PÉREZ, JUAN, para rendir': [_del(1201, 1220)],
      });
      expect(
        NumerosDeEntradas.ocupadosAlVender([venta], const [], conVenta.bloques),
        conVenta.ocupados,
      );
    });

    test('dos bloques de la misma persona juntan sus números', () {
      final otro = _dar(persona: 'PÉREZ, JUAN', desde: 1401, cantidad: 5);
      expect(NumerosDeEntradas.ocupadosParaRendir(_cuenta([dio, otro]).bloques), {
        'PÉREZ, JUAN, para rendir': [_del(1201, 1220), _del(1401, 1405)],
      });
    });

    test('el número que propone VENDER salta los bloques', () {
      final otro = _dar(persona: 'GÓMEZ, LUCÍA', desde: 1221, cantidad: 10);
      final venta = _venta('LÓPEZ, ANA', [_del(1231, 1232)]);
      final ocupados = _cuenta([dio, otro], ventas: [venta]).ocupados;
      expect(NumerosDeEntradas.primeroLibreDesde(1199, ocupados), 1199);
      expect(NumerosDeEntradas.primeroLibreDesde(1201, ocupados), 1233,
          reason: 'detrás de los dos bloques y de la venta que los sigue');
      expect(NumerosDeEntradas.primeroLibreDesde(1210, ocupados), 1233);
      expect(NumerosDeEntradas.primeroLibreDesde(1198, ocupados, cantidad: 5), 1233,
          reason: 'del 1198 al 1202 pisaría el bloque');
      expect(NumerosDeEntradas.primeroLibreDesde(1190, ocupados, cantidad: 5), 1190);
      expect(NumerosDeEntradas.primeroLibreDesde(0, ocupados), 1,
          reason: 'el talonario empieza en el 1');
      expect(NumerosDeEntradas.primeroLibreDesde(1201, const {}), 1201);
    });
  });

  group('regla 44: lo devuelto queda libre; lo vendido y lo que no volvió, no', () {
    final dio = _dar(desde: 1201, cantidad: 20);

    String? vender(ParaRendir p, List<TramoTalonario> tramos) => NumerosDeEntradas.error(
          tramos: tramos,
          cantidad: tramos.fold(0, (s, t) => s + t.cantidad),
          ocupados: p.ocupados,
        );

    test('los devueltos se pueden volver a vender', () {
      final p = _cuenta([dio, _devolvio(dio, [_del(1216, 1220)])]);
      expect(p.bloques.single.numerosOcupados, [_del(1201, 1215)]);
      expect(vender(p, [_del(1216, 1220)]), isNull);
      expect(vender(p, [_del(1215, 1216)]),
          'El 1215 ya se le dio a PÉREZ, JUAN, para rendir (1201 al 1215).');
    });

    test('lo vendido sigue ocupado: no se sabe cuáles vendió', () {
      final r = _rendicion(dio, 15);
      final p = _cuenta([dio, r.vendio], ventas: [r.venta]);
      expect(p.bloques.single.numerosOcupados, [_del(1201, 1220)]);
      expect(vender(p, [_del(1201, 1201)]), isNotNull);
    });

    test('lo que no volvió sigue ocupado para siempre, y ya no lo puede devolver', () {
      final perdidas = _noVolvieron(dio, 2, [_del(1214, 1215)]);
      final p = _cuenta([dio, perdidas]);
      final b = p.bloques.single;
      expect(b.numerosOcupados, [_del(1201, 1220)]);
      expect(b.numerosNoVolvieron, [_del(1214, 1215)]);
      expect(b.numerosQueTiene, [_del(1201, 1213), _del(1216, 1220)]);
      expect(vender(p, [_del(1214, 1214)]), isNotNull);
    });

    test('una devolución anulada vuelve a ocupar sus números', () {
      final devolvio = _devolvio(dio, [_del(1216, 1220)]);
      final p = _cuenta([dio, devolvio, _anulo(devolvio)]);
      final b = p.bloques.single;
      expect(b.numerosOcupados, [_del(1201, 1220)]);
      expect(b.devueltas, 0);
      expect(b.sinRendir, 20);
      expect(vender(p, [_del(1216, 1216)]), isNotNull);
    });

    test('un "no volvieron" anulado vuelve a estar a cargo de quien las llevó', () {
      final perdidas = _noVolvieron(dio, 2, [_del(1214, 1215)]);
      final b = _cuenta([dio, perdidas, _anulo(perdidas)]).bloques.single;
      expect(b.noVolvieron, 0);
      expect(b.sinRendir, 20);
      expect(b.numerosQueTiene, [_del(1201, 1220)]);
    });

    test('un bloque anulado libera todos sus números y no tiene nada para rendir', () {
      final p = _cuenta([dio, _anulo(dio)]);
      final b = p.bloques.single;
      expect(b.anulado, isTrue);
      expect(b.numerosOcupados, isEmpty);
      expect(b.numerosQueTiene, isEmpty);
      expect(b.sinRendir, 0);
      expect(b.plataQueFalta, 0);
      expect(NumerosDeEntradas.ocupadosParaRendir(p.bloques), isEmpty);
      expect(vender(p, [_del(1201, 1220)]), isNull);
      expect(p.personas, 0);
      expect(p.sinRendir, 0);
      expect(p.hayParaRendir, isFalse);
      // Su persona sigue en la lista (para la historia), sin nada encima.
      final persona = p.porPersona.single;
      expect(persona.bloques.single.id, dio.id);
      expect(persona.seLlevo, 0, reason: 'lo anulado no se lo llevó');
      expect(persona.rindioTodo, isFalse, reason: 'no tiene nada en pie para rendir');
      expect(persona.desde, isNull);
    });
  });

  group('regla 46: al dar, números obligatorios, sin pisar nada, y nombre y apellido',
      () {
    final precios = _precios();
    final lunes = DateTime(2026, 11, 16);

    String? dar({
      ConfigEntradas? config,
      bool sinPrecio = false,
      bool deAfuera = true,
      String? alumno,
      String nombre = 'PÉREZ, JUAN',
      int cantidad = 20,
      List<TramoTalonario> tramos = const [TramoTalonario(1201, 1220)],
      ParaRendir? fiesta,
    }) =>
        ParaRendir.errorAlDar(
          config: sinPrecio ? null : (config ?? precios),
          hoyAr: lunes,
          deAfuera: deAfuera,
          contratoAlumnoId: alumno,
          personaNombre: nombre,
          cantidad: cantidad,
          tramos: tramos,
          ocupados: (fiesta ?? _cuenta(const [])).ocupados,
        );

    test('todo bien', () {
      expect(dar(), isNull);
      expect(dar(deAfuera: false, alumno: _familia, nombre: 'GÓMEZ, LUCÍA'), isNull);
      expect(dar(tramos: [_del(1201, 1210), _del(1301, 1310)]), isNull,
          reason: 'hasta dos tramos');
    });

    test('sin precio, no se da, y al jefe se le dice dónde cargarlo', () {
      expect(dar(sinPrecio: true), ParaRendir.kSinPrecioParaDar);
      expect(dar(config: ConfigEntradas.vacia(_fiesta, ahora: _lunes)),
          ParaRendir.kSinPrecioParaDar);
      // DAR es del jefe: no le habla de "el jefe" (21-nov-2026).
      expect(ParaRendir.kSinPrecioParaDar, contains('PRECIOS'));
      expect(ParaRendir.kSinPrecioParaDar, isNot(contains('jefe')));
    });

    test('alguien de afuera, con nombre y apellido; un alumno, elegido de la lista', () {
      expect(dar(nombre: 'Juan'), 'Escribí nombre y apellido de quien se las lleva.');
      expect(dar(nombre: '  '), 'Escribí nombre y apellido de quien se las lleva.');
      expect(dar(deAfuera: false, alumno: null, nombre: 'GÓMEZ, LUCÍA'),
          'Elegí al alumno de la lista.');
      expect(dar(deAfuera: false, alumno: _familia, nombre: ''),
          'Elegí al alumno de la lista.');
    });

    test('la cantidad, de 1 en adelante', () {
      expect(dar(cantidad: 0, tramos: const []), 'Elegí cuántas entradas se lleva.');
    });

    test('los números son obligatorios (una venta los acepta sin números)', () {
      expect(dar(tramos: const []),
          'Escribí el primer número del talonario: son obligatorios.');
      expect(NumerosDeEntradas.error(tramos: const [], cantidad: 20), isNull);
    });

    test('la cantidad justa, bien escritos', () {
      expect(dar(tramos: [_del(1201, 1219)]), 'Son 19 números y se lleva 20 entradas.');
      expect(dar(cantidad: 2, tramos: [_del(1201, 1201)]),
          'Es 1 número y se lleva 2 entradas.');
      expect(dar(cantidad: 1, tramos: [_del(1201, 1202)]),
          'Son 2 números y se lleva 1 entrada.');
      expect(dar(tramos: [_del(1220, 1201)]), 'El tramo 1220 al 1201 está al revés.');
      expect(dar(tramos: [_del(0, 19)]), 'Los números del talonario empiezan en 1.');
      expect(dar(tramos: [_del(1201, 1210), _del(1210, 1219)]),
          'Los tramos 1201 al 1210 y 1210 al 1219 se pisan.');
    });

    test('sin pisar una venta', () {
      final fiesta = _cuenta(const [], ventas: [_venta('LÓPEZ, ANA', [_del(1205, 1206)])]);
      expect(dar(fiesta: fiesta), 'El 1205 ya se le dio a LÓPEZ, ANA (1205 al 1206).');
    });

    test('sin pisar otro bloque, salvo lo que ya devolvió o un bloque anulado', () {
      final lucia = _dar(persona: 'GÓMEZ, LUCÍA', desde: 1210, cantidad: 10);
      expect(dar(fiesta: _cuenta([lucia])),
          'El 1210 ya se le dio a GÓMEZ, LUCÍA, para rendir (1210 al 1219).');
      expect(dar(fiesta: _cuenta([lucia, _devolvio(lucia, [_del(1210, 1219)])])), isNull);
      expect(dar(fiesta: _cuenta([lucia, _anulo(lucia)])), isNull);
    });
  });

  group('regla 47: lo que se devuelve es de lo que todavía tiene', () {
    final dio = _dar(desde: 1201, cantidad: 20);
    final r = _rendicion(dio, 5);
    // Vendió 5, devolvió del 1216 al 1220 y no volvieron el 1214 y el 1215: le
    // quedan 8, y tiene del 1201 al 1213.
    final bloque = _cuenta(
      [dio, r.vendio, _devolvio(dio, [_del(1216, 1220)]), _noVolvieron(dio, 2, [_del(1214, 1215)])],
      ventas: [r.venta],
    ).bloques.single;

    String? rendir({
      int vendidas = 0,
      int devueltas = 0,
      List<TramoTalonario> numeros = const [],
      bool hayCaja = false,
      BloqueParaRendir? de,
    }) =>
        ParaRendir.errorAlRendir(
          de ?? bloque,
          vendidas: vendidas,
          devueltas: devueltas,
          numerosDevueltos: numeros,
          hayCaja: hayCaja,
        );

    test('la cuenta del bloque', () {
      expect(bloque.sinRendir, 8);
      expect(bloque.numerosQueTiene, [_del(1201, 1213)]);
    });

    test('de las que se llevó, y no devuelto ni perdido antes', () {
      expect(rendir(devueltas: 1, numeros: [_del(1230, 1230)]),
          'El 1230 no es de las que se llevó (1201 al 1220).');
      expect(rendir(devueltas: 1, numeros: [_del(1216, 1216)]), 'El 1216 ya lo devolvió.');
      const noVolvio = 'El 1214 está entre las que no volvieron: si la trajo, primero el '
          'jefe tiene que anular ese "no volvieron" en PARA RENDIR.';
      expect(rendir(devueltas: 1, numeros: [_del(1214, 1214)]), noVolvio);
      expect(rendir(devueltas: 2, numeros: [_del(1212, 1213)]), isNull);
      expect(rendir(devueltas: 3, numeros: [_del(1212, 1214)]), noVolvio);
    });

    test('con números, la cantidad justa y bien escritos', () {
      expect(rendir(devueltas: 1), 'Escribí los números de las que devuelve.');
      expect(rendir(devueltas: 1, numeros: [_del(1212, 1213)]), 'Son 2 números y devuelve 1.');
      expect(rendir(devueltas: 2, numeros: [_del(1213, 1213)]), 'Es 1 número y devuelve 2.');
      expect(rendir(vendidas: 1, numeros: [_del(1213, 1213)], hayCaja: true),
          'No devuelve ninguna: sacá los números.');
      expect(rendir(devueltas: 2, numeros: [_del(1213, 1212)]),
          'El tramo 1213 al 1212 está al revés.');
      expect(rendir(devueltas: 4, numeros: [_del(1201, 1202), _del(1202, 1203)]),
          'Los tramos 1201 al 1202 y 1202 al 1203 se pisan.');
    });

    test('no más de lo que le queda, y algo', () {
      expect(rendir(), 'Poné cuántas vendió o cuántas devuelve.');
      expect(rendir(vendidas: -1, devueltas: 2, numeros: [_del(1212, 1213)]),
          'Poné cuántas vendió o cuántas devuelve.');
      // Este bloque tiene 2 que no volvieron: hasta 10 entrarían anulándolas, y
      // el mensaje dice cómo.
      const guia = ' Si vendió o trajo alguna de las que no volvieron, primero el jefe '
          'tiene que anular ese "no volvieron" en PARA RENDIR.';
      expect(rendir(vendidas: 9, hayCaja: true), 'Le quedan 8: no puede rendir 9.$guia');
      expect(rendir(vendidas: 6, devueltas: 3, numeros: [_del(1211, 1213)], hayCaja: true),
          'Le quedan 8: no puede rendir 9.$guia');
      expect(rendir(vendidas: 10, hayCaja: true), 'Le quedan 8: no puede rendir 10.$guia');
      expect(rendir(vendidas: 11, hayCaja: true), 'Le quedan 8: no puede rendir 11.',
          reason: 'ni anulando lo que no volvió le alcanza: sin la guía');
      final casi = _cuenta([dio, _devolvio(dio, [_del(1202, 1220)])]).bloques.single;
      expect(rendir(vendidas: 2, hayCaja: true, de: casi), 'Le queda 1: no puede rendir 2.',
          reason: 'sin nada que no volvió, sin la guía');
      expect(rendir(vendidas: 8, hayCaja: true), isNull);
    });

    test('si rindió de más, la guía no promete lo que anulando tampoco le queda', () {
      // Se llevó 20; Carla y Romi, cada una en su tablet, le cobraron 12 y 7
      // (19), y el jefe dio por perdidas 3: rindió 22 de 20. Anulando el "no
      // volvieron" le quedaría 1, no 3.
      final dio = _dar(desde: 1201, cantidad: 20);
      final enCarla = _rendicion(dio, 12, caja: 'caja-carla');
      final enRomi = _rendicion(dio, 7, caja: 'caja-romi');
      final deMas = _cuenta(
        [dio, enCarla.vendio, enRomi.vendio, _noVolvieron(dio, 3)],
        ventas: [enCarla.venta, enRomi.venta],
      ).bloques.single;
      expect([deMas.vendidas, deMas.noVolvieron, deMas.sinRendir, deMas.rindioDeMas],
          [19, 3, 0, 2]);
      const guia = ' Si vendió o trajo alguna de las que no volvieron, primero el jefe '
          'tiene que anular ese "no volvieron" en PARA RENDIR.';
      expect(rendir(vendidas: 2, hayCaja: true, de: deMas), 'Le quedan 0: no puede rendir 2.',
          reason: 'anulando las 3 le quedaría 1: no le alcanza para 2');
      expect(rendir(vendidas: 1, hayCaja: true, de: deMas), 'Le quedan 0: no puede rendir 1.$guia');
    });

    test('una que no volvió y después la vendió: el jefe anula ese "no volvieron" y se '
        'rinde como vendida (sección 2 de la SPEC)', () async {
      final repo = EntradasEnMemoria();
      final caja = await repo.abrirCaja(
          eventoId: _fiesta, operadorId: _carla, operadorNombre: 'Carla');
      final dio = await repo.darParaRendir(
        eventoId: _fiesta,
        personaNombre: 'PÉREZ, JUAN',
        cantidad: 2,
        numeros: [_del(1201, 1202)],
        precio: 8000,
        nombrePrecio: 'Entrada anticipada',
        quien: 'Jefe',
      );
      final perdidas = await repo.noVolvieron(dio,
          cantidad: 2, motivo: 'dice que las perdió', quien: 'Jefe');
      Future<BloqueParaRendir> leer() async => ParaRendir.de(
            movimientos: await repo.paraRendir(_fiesta),
            ventas: await repo.ventas(_fiesta),
            anulaciones: await repo.anulaciones(_fiesta),
          ).bloques.single;

      // Con las dos dadas por perdidas no le queda ninguna: la cuenta lo dice
      // y el repositorio tampoco la guarda.
      var b = await leer();
      expect(b.sinRendir, 0);
      expect(ParaRendir.errorAlRendir(b, vendidas: 1, devueltas: 0, hayCaja: true),
          'Le quedan 0: no puede rendir 1. Si vendió o trajo alguna de las que no '
          'volvieron, primero el jefe tiene que anular ese "no volvieron" en PARA RENDIR.');
      await expectLater(
        repo.rendir(caja: caja, bloque: dio, vendidas: 1, efectivo: 8000, quien: 'Carla'),
        throwsStateError,
      );

      // El jefe anula el "no volvieron", se rinde la que vendió y la otra
      // vuelve a quedar perdida.
      await repo.anularDeParaRendir(perdidas, motivo: 'apareció: la vendió', quien: 'Jefe');
      b = await leer();
      expect(b.sinRendir, 2);
      expect(ParaRendir.errorAlRendir(b, vendidas: 1, devueltas: 0, hayCaja: true), isNull);
      final r = await repo.rendir(
        caja: caja,
        bloque: dio,
        vendidas: 1,
        efectivo: ParaRendir.renglon(b, 1).subtotal,
        quien: 'Carla',
      );
      expect(r.venta!.total, 8000);
      await repo.noVolvieron(dio, cantidad: 1, motivo: 'la otra no apareció', quien: 'Jefe');
      b = await leer();
      expect([b.vendidas, b.noVolvieron, b.sinRendir, b.plataRendida, b.plataNoVolvio],
          [1, 1, 0, 8000, 8000]);
    });

    test('lo vendido se cobra con la caja abierta; solo devolver no la pide', () {
      expect(rendir(vendidas: 2), 'Para cobrar lo vendido, abrí la caja.');
      expect(rendir(vendidas: 2, hayCaja: true), isNull);
      expect(rendir(devueltas: 2, numeros: [_del(1212, 1213)]), isNull);
    });

    test('unas entradas anuladas no se rinden', () {
      final anulado = _cuenta([dio, _anulo(dio)]).bloques.single;
      expect(rendir(vendidas: 1, hayCaja: true, de: anulado),
          'Estas entradas están anuladas: no hay nada para rendir.');
    });

    test('se proponen los últimos que todavía tiene', () {
      expect(ParaRendir.proponerDevueltos(bloque, 3), [_del(1211, 1213)]);
      expect(ParaRendir.proponerDevueltos(bloque, 13), [_del(1201, 1213)]);
      expect(ParaRendir.proponerDevueltos(bloque, 14), isEmpty, reason: 'no tiene tantos');
      expect(ParaRendir.proponerDevueltos(bloque, 0), isEmpty);
      // Con un hueco en el medio: devolvió solo el 1218.
      final conHueco = _cuenta([dio, _devolvio(dio, [_del(1218, 1218)])]).bloques.single;
      expect(ParaRendir.proponerDevueltos(conHueco, 3), [_del(1217, 1217), _del(1219, 1220)]);
      // Lo propuesto siempre pasa la regla.
      for (final n in [1, 3, 8]) {
        expect(
          rendir(devueltas: n, numeros: ParaRendir.proponerDevueltos(bloque, n)),
          isNull,
          reason: 'devolver $n',
        );
      }
    });

    test('lo que la regla acepta lo guarda el repositorio, y lo que rechaza, no', () async {
      final repo = EntradasEnMemoria();
      final guardado = await repo.darParaRendir(
        eventoId: _fiesta,
        personaNombre: 'PÉREZ, JUAN',
        cantidad: 20,
        numeros: [_del(1201, 1220)],
        precio: 8000,
        nombrePrecio: 'Entrada anticipada',
        quien: 'Jefe',
      );
      await repo.rendir(
        bloque: guardado,
        vendidas: 0,
        devueltas: 5,
        numerosDevueltos: [_del(1216, 1220)],
        quien: 'Carla',
      );
      final b = _cuenta(await repo.paraRendir(_fiesta)).bloques.single;
      final yaDevuelto = [_del(1216, 1216)];
      expect(ParaRendir.errorAlRendir(b,
              vendidas: 0, devueltas: 1, numerosDevueltos: yaDevuelto, hayCaja: false),
          'El 1216 ya lo devolvió.');
      await expectLater(
        repo.rendir(
            bloque: guardado,
            vendidas: 0,
            devueltas: 1,
            numerosDevueltos: yaDevuelto,
            quien: 'Carla'),
        throwsStateError,
      );
      final propuestos = ParaRendir.proponerDevueltos(b, 4);
      expect(ParaRendir.errorAlRendir(b,
              vendidas: 0, devueltas: 4, numerosDevueltos: propuestos, hayCaja: false),
          isNull);
      await repo.rendir(
        bloque: guardado,
        vendidas: 0,
        devueltas: 4,
        numerosDevueltos: propuestos,
        quien: 'Carla',
      );
      expect(_cuenta(await repo.paraRendir(_fiesta)).bloques.single.sinRendir, 11);
    });
  });

  // 21-nov-2026, la ventana de NO VOLVIERON de PARA RENDIR (etapa 5): lo dice
  // antes de guardar, con palabras, en vez de que el repositorio tire.
  group('NO VOLVIERON: de lo que le queda, con el motivo y los números de lo que '
      'tiene', () {
    final dio = _dar(desde: 1201, cantidad: 20);
    final r = _rendicion(dio, 5);
    // Como en la regla 47: le quedan 8, y tiene del 1201 al 1213.
    final bloque = _cuenta(
      [dio, r.vendio, _devolvio(dio, [_del(1216, 1220)]), _noVolvieron(dio, 2, [_del(1214, 1215)])],
      ventas: [r.venta],
    ).bloques.single;

    String? marcar({
      int cantidad = 1,
      List<TramoTalonario> numeros = const [],
      String motivo = 'dice que las perdió',
      BloqueParaRendir? de,
    }) =>
        ParaRendir.errorAlMarcarNoVolvieron(
          de ?? bloque,
          cantidad: cantidad,
          numeros: numeros,
          motivo: motivo,
        );

    test('sin números alcanza con la cantidad y el motivo', () {
      expect(marcar(), isNull);
      expect(marcar(cantidad: 8), isNull);
      expect(marcar(motivo: '  '), 'Escribí por qué no volvieron.');
    });

    test('no más de lo que le queda, y algo', () {
      expect(marcar(cantidad: 0), 'Elegí cuántas no volvieron.');
      expect(marcar(cantidad: 9), 'Le quedan 8 sin rendir: no se pueden marcar 9.');
      final uno = _cuenta([_dar(desde: 1, cantidad: 1)]).bloques.single;
      expect(marcar(de: uno, cantidad: 2), 'Le queda 1 sin rendir: no se pueden marcar 2.');
    });

    test('con números, la cantidad justa y de los que todavía tiene', () {
      expect(marcar(cantidad: 2, numeros: [_del(1212, 1213)]), isNull);
      expect(marcar(cantidad: 1, numeros: [_del(1212, 1213)]), 'Son 2 números y no volvió 1.');
      expect(marcar(cantidad: 2, numeros: [_del(1213, 1213)]), 'Es 1 número y no volvieron 2.');
      expect(marcar(numeros: [_del(1230, 1230)]),
          'El 1230 no es de las que se llevó (1201 al 1220).');
      expect(marcar(numeros: [_del(1216, 1216)]), 'El 1216 ya lo devolvió.');
      expect(marcar(numeros: [_del(1214, 1214)]), 'El 1214 ya está entre las que no volvieron.');
      expect(marcar(cantidad: 2, numeros: [_del(1213, 1212)]),
          'El tramo 1213 al 1212 está al revés.');
    });

    test('en un bloque anulado no hay nada que marcar', () {
      final otro = _dar(desde: 1, cantidad: 3);
      final anulado = _cuenta([otro, _anulo(otro)]).bloques.single;
      expect(marcar(de: anulado), 'Estas entradas están anuladas: no hay nada para marcar.');
    });

    test('lo que deja pasar, el repositorio lo guarda', () async {
      final e = EntradasEnMemoria();
      final dado = await e.darParaRendir(
        eventoId: _fiesta,
        personaNombre: 'PÉREZ, JUAN',
        cantidad: 20,
        numeros: [_del(1201, 1220)],
        precio: 8000,
        nombrePrecio: 'Entrada anticipada',
        quien: 'Jefe',
      );
      final b = _cuenta(e.listaParaRendir).bloques.single;
      expect(marcar(de: b, cantidad: 2, numeros: [_del(1219, 1220)]), isNull);
      final perdidas = await e.noVolvieron(
        dado,
        cantidad: 2,
        numeros: [_del(1219, 1220)],
        motivo: 'dice que las perdió',
        quien: 'Jefe',
      );
      expect(perdidas.esNoVolvieron, isTrue);
      final despues = _cuenta(e.listaParaRendir).bloques.single;
      expect(despues.sinRendir, 18);
      // Y lo que ya marcó, no lo deja marcar otra vez (el repositorio tampoco).
      expect(marcar(de: despues, cantidad: 1, numeros: [_del(1220, 1220)]),
          'El 1220 ya está entre las que no volvieron.');
      await expectLater(
        e.noVolvieron(dado, cantidad: 1, numeros: [_del(1220, 1220)], motivo: 'x', quien: 'Jefe'),
        throwsStateError,
      );
    });
  });

  group('regla 48: una rendición anulada en VENTAS vuelve a "sin rendir"', () {
    final dio = _dar(desde: 1201, cantidad: 20);
    final r = _rendicion(dio, 15);

    for (final devueltas in [false, true]) {
      test('anulada ${devueltas ? 'con' : 'sin'} "devolvieron las entradas": las 15 '
          'vuelven a estar a cargo de quien las llevó', () {
        final antes = _cuenta([dio, r.vendio], ventas: [r.venta]).bloques.single;
        expect(antes.sinRendir, 5);
        final p = _cuenta(
          [dio, r.vendio],
          ventas: [r.venta],
          anulaciones: [_anulada(r.venta, devueltas: devueltas)],
        );
        final b = p.bloques.single;
        expect(b.vendidas, 0);
        expect(b.sinRendir, 20);
        expect(b.plataRendida, 0);
        expect(b.plataQueFalta, 160000);
        expect(b.movimientos.single.cuenta, isFalse);
        expect(b.movimientos.single.anulacionDeLaVenta, isNotNull);
        expect(b.tieneMovimientos, isFalse);
        // Los números siguen siendo del bloque: la venta de la rendición no
        // llevaba números, así que anularla no libera ni anula ninguno.
        expect(b.numerosOcupados, [_del(1201, 1220)]);
        expect(p.ocupados, {'PÉREZ, JUAN, para rendir': [_del(1201, 1220)]});
        expect(p.bloqueDeLaVenta(r.venta.id)?.id, dio.id);
        expect(
          b.sinRendir,
          MovimientoParaRendir.quedanSinRendir(dio, [dio, r.vendio],
              ventasAnuladas: {r.venta.id}),
        );
      });
    }

    test('con la anulación ya acá y la venta todavía no, tampoco cuenta', () {
      final b = _cuenta([dio, r.vendio], anulaciones: [_anulada(r.venta)]).bloques.single;
      expect(b.vendidas, 0);
      expect(b.sinRendir, 20);
      expect(b.plataEnCamino, isFalse);
    });
  });

  group('regla 49: si rindió de más, se avisa y no se esconde', () {
    final dio = _dar(desde: 1201, cantidad: 20);
    // Carla y Romi, cada una en su tablet sin internet, le cobraron al mismo.
    final enCarla = _rendicion(dio, 15, caja: 'caja-carla');
    final enRomi = _rendicion(dio, 10, caja: 'caja-romi');
    final p = _cuenta(
      [dio, enCarla.vendio, enRomi.vendio],
      ventas: [enCarla.venta, enRomi.venta],
    );
    final b = p.bloques.single;

    test('se ve todo lo que rindió, y cuánto de más', () {
      expect(b.vendidas, 25);
      expect(b.sinRendir, 0);
      expect(b.rindioDeMas, 5);
      expect(b.rindioTodo, isFalse, reason: 'tiene algo para revisar');
      expect(b.plataRendida, 200000);
      expect(
        b.sinRendir,
        MovimientoParaRendir.quedanSinRendir(dio, [dio, enCarla.vendio, enRomi.vendio]),
      );
    });

    test('el aviso, y la persona sigue en la lista', () {
      final aviso =
          p.avisos.singleWhere((a) => a.que == QueAvisoParaRendir.rindioDeMas);
      expect(aviso.bloqueId, dio.id);
      expect(aviso.texto, contains('PÉREZ, JUAN rindió 25 de las 20'));
      expect(aviso.texto, contains('revisar'));
      expect(p.porPersona.single.rindioDeMas, 5);
      expect(p.porPersona.single.rindioTodo, isFalse);
      expect(p.porPersona.single.vendidas, 25);
    });

    test('anulando en VENTAS la que sobra, queda bien', () {
      final arreglado = _cuenta(
        [dio, enCarla.vendio, enRomi.vendio],
        ventas: [enCarla.venta, enRomi.venta],
        anulaciones: [_anulada(enRomi.venta)],
      );
      expect(arreglado.bloques.single.rindioDeMas, 0);
      expect(arreglado.bloques.single.sinRendir, 5);
      expect(arreglado.avisos, isEmpty);
    });

    // 21-nov-2026: lo que dice VENTAS antes de anular una rendición sale de
    // acá, y es lo que queda después: lo de más se descuenta primero.
    test('cuántas le quedarían si una rendición dejara de contar', () {
      expect(b.sinRendirSiDejanDeContar(10), 5, reason: 'anular la de Romi');
      expect(b.sinRendirSiDejanDeContar(15), 10, reason: 'anular la de Carla');
      expect(b.sinRendirSiDejanDeContar(3), 0, reason: 'sigue rindiendo de más');
      final sinCarla = _cuenta(
        [dio, enCarla.vendio, enRomi.vendio],
        ventas: [enCarla.venta, enRomi.venta],
        anulaciones: [_anulada(enCarla.venta)],
      );
      expect(sinCarla.bloques.single.sinRendir, b.sinRendirSiDejanDeContar(15));
      // Sin rendir de más, vuelven todas; en un bloque anulado, ninguna.
      final justo = _cuenta([dio, enCarla.vendio], ventas: [enCarla.venta]).bloques.single;
      expect([justo.sinRendir, justo.sinRendirSiDejanDeContar(15)], [5, 20]);
      final anulado =
          _cuenta([dio, enCarla.vendio, _anulo(dio)], ventas: [enCarla.venta]).bloques.single;
      expect(anulado.sinRendirSiDejanDeContar(15), 0);
    });
  });

  group('regla 58: un renglón que esta versión no conoce no le cambia nada a nadie',
      () {
    test('ni la cuenta, ni los números, ni los avisos, ni la lista', () {
      final juan = _dar(persona: 'PÉREZ, JUAN', desde: 1201, cantidad: 20);
      final lucia = _dar(persona: 'GÓMEZ, LUCÍA', desde: 1221, cantidad: 10, alumno: _familia);
      final r = _rendicion(juan, 5);
      final base = [
        juan,
        lucia,
        r.vendio,
        _devolvio(juan, [_del(1216, 1220)]),
        _noVolvieron(lucia, 2),
      ];
      final ventas = [r.venta, _venta('LÓPEZ, ANA', [_del(1300, 1301)])];
      final sin = _cuenta(base, ventas: ventas);

      // Uno que cuelga del bloque; otro cuyo id usa como bloque un renglón que
      // esta versión sí conoce (los dos los escribió una versión más nueva).
      final nuevo = _desconocido(juan);
      final colgado = MovimientoParaRendir.vendio(
        _dar(persona: 'NUEVO, UNO', desde: 2001, cantidad: 3),
        cantidad: 1,
        ventaId: 'v-de-la-nueva',
        cajaEntradasId: 'caja-carla',
        ahora: _t(),
      );
      final deLaNueva = _desconocido(lucia, id: colgado.bloqueId);
      final con = _cuenta([...base, nuevo, deLaNueva, colgado], ventas: ventas);

      expect(_foto(con), _foto(sin));
      expect(con.avisos, isEmpty);
    });
  });

  group('los avisos', () {
    test('un bloque anulado que tiene algo rendido después', () {
      final dio = _dar();
      // Un equipo anuló el bloque y otro, sin internet, recibió la devolución.
      final p = _cuenta([dio, _anulo(dio), _devolvio(dio, [_del(1216, 1220)])]);
      final aviso = p.avisos.single;
      expect(aviso.que, QueAvisoParaRendir.anuladoConMovimientos);
      expect(aviso.bloqueId, dio.id);
      expect(aviso.texto, contains('PÉREZ, JUAN (1201 al 1220)'));
      expect(p.bloques.single.sinRendir, 0);
      expect(p.bloques.single.numerosOcupados, isEmpty);
      // El bloque muestra lo que pasó, pero ni su persona ni la fiesta lo suman.
      expect(p.bloques.single.devueltas, 5);
      final persona = p.porPersona.single;
      expect([persona.seLlevo, persona.devueltas, persona.rindioTodo], [0, 0, false]);
      expect(p.personas, 0);
    });

    test('lo que llegó de un bloque que todavía no bajó: avisa y no cuenta', () {
      final noBajo = _dar(persona: 'SOSA, DIEGO');
      final r = _rendicion(noBajo, 3);
      final p = _cuenta([r.vendio], ventas: [r.venta]);
      expect(p.bloques, isEmpty);
      expect(p.sinRendir, 0);
      final aviso = p.avisos.single;
      expect(aviso.que, QueAvisoParaRendir.deUnBloqueQueNoBajo);
      expect(aviso.bloqueId, noBajo.id);
      expect(aviso.texto, startsWith('SOSA, DIEGO:'));
      // Cuando baja, el aviso se va y lo rendido cuenta.
      final despues = _cuenta([noBajo, r.vendio], ventas: [r.venta]);
      expect(despues.avisos, isEmpty);
      expect(despues.bloques.single.vendidas, 3);
    });

    test('un número de un bloque que también está en una venta', () {
      final dio = _dar();
      final p = _cuenta([dio], ventas: [_venta('LÓPEZ, ANA', [_del(1205, 1206)])]);
      final cruce = p.cruces.single;
      expect(cruce.numero, 1205);
      expect(cruce.conUnaVenta, isTrue);
      expect(cruce.texto,
          'El 1205 se le dio a PÉREZ, JUAN para rendir y también está en una venta '
          'a LÓPEZ, ANA: revisar.');
      expect(p.avisos.single.que, QueAvisoParaRendir.numerosCruzados);
      expect(p.avisos.single.texto, cruce.texto);
    });

    test('un número en dos bloques', () {
      final juan = _dar(persona: 'PÉREZ, JUAN', desde: 1201, cantidad: 20);
      final lucia = _dar(persona: 'GÓMEZ, LUCÍA', desde: 1215, cantidad: 10);
      final cruce = _cuenta([juan, lucia]).cruces.single;
      expect(cruce.numero, 1215);
      expect(cruce.otroBloqueId, lucia.id);
      expect(cruce.texto,
          'El 1215 se le dio para rendir a PÉREZ, JUAN y también a GÓMEZ, LUCÍA: '
          'revisar.');
      final otraVez = _dar(persona: 'PÉREZ, JUAN', desde: 1220, cantidad: 2);
      expect(_cuenta([juan, otraVez]).cruces.single.texto,
          'El 1220 está dos veces en las que se le dieron a PÉREZ, JUAN para rendir: '
          'revisar.');
    });

    test('no es un cruce: lo devuelto que se vendió, una venta anulada con lo '
        'devuelto, un bloque anulado, la venta de la rendición y los dos tramos de '
        'un mismo bloque', () {
      final dio = _dar(tramos: [_del(1201, 1210), _del(1301, 1310)], cantidad: 20);
      final r = _rendicion(dio, 5);
      final revendida = _venta('LÓPEZ, ANA', [_del(1309, 1310)]);
      final anuladaConTodo = _venta('RUIZ, MARTA', [_del(1201, 1202)]);
      final anulado = _dar(persona: 'MOLINA, CARLOS', desde: 1203, cantidad: 2);
      final p = _cuenta(
        [dio, r.vendio, _devolvio(dio, [_del(1309, 1310)]), anulado, _anulo(anulado)],
        ventas: [r.venta, revendida, anuladaConTodo],
        anulaciones: [_anulada(anuladaConTodo, devueltas: true)],
      );
      expect(p.cruces, isEmpty);
      expect(p.avisos, isEmpty);
    });

    test('una venta anulada sin devolver las entradas sí se cruza: esos números '
        'quedaron anulados', () {
      final venta = _venta('RUIZ, MARTA', [_del(1201, 1202)]);
      final p = _cuenta([_dar()], ventas: [venta], anulaciones: [_anulada(venta)]);
      expect(p.cruces.single.otro, 'RUIZ, MARTA ${NumerosDeEntradas.sinDevolver}');
    });

    test('lo que llega de otro equipo con la venta todavía en camino', () {
      final dio = _dar();
      final r = _rendicion(dio, 4);
      final b = _cuenta([dio, r.vendio]).bloques.single;
      expect(b.vendidas, 4, reason: 'cuenta: si no, se le podría rendir dos veces');
      expect(b.plataEnCamino, isTrue);
      expect(b.movimientos.single.plataEnCamino, isTrue);
      expect(b.plataRendida, 32000);
      final llego = _cuenta([dio, r.vendio], ventas: [r.venta]).bloques.single;
      expect(llego.plataEnCamino, isFalse);
      expect(llego.plataRendida, 32000);
    });
  });

  group('por persona y los totales', () {
    test('un alumno por su ficha; alguien de afuera por su nombre', () {
      final lucia1 = _dar(persona: 'GÓMEZ, LUCÍA', desde: 1201, cantidad: 10, alumno: _familia);
      final lucia2 = _dar(persona: 'GOMEZ LUCIA', desde: 1211, cantidad: 4, alumno: _familia);
      final deAfuera = _dar(persona: 'Gómez, Lucía', desde: 1221, cantidad: 2);
      final juan1 = _dar(persona: 'Pérez, Juan', desde: 1301, cantidad: 3, contacto: '351 555-0101');
      final juan2 = _dar(persona: 'PEREZ  JUAN', desde: 1311, cantidad: 3);
      final otraFamilia =
          _dar(persona: 'GÓMEZ, LUCÍA', desde: 1401, cantidad: 1, alumno: _otraFamilia);
      final p = _cuenta([lucia1, lucia2, deAfuera, juan1, juan2, otraFamilia]);
      final personas = {for (final per in p.porPersona) per.clave: per};
      expect(personas, hasLength(4));
      final alumna = personas['alumno|$_familia']!;
      expect(alumna.bloques.map((b) => b.id), [lucia1.id, lucia2.id]);
      expect(alumna.seLlevo, 14);
      expect(alumna.nombre, 'GOMEZ LUCIA', reason: 'el del bloque más nuevo');
      expect(alumna.esDeUnAlumno, isTrue);
      final juan = personas['afuera|perez juan']!;
      expect(juan.bloques.map((b) => b.id), [juan1.id, juan2.id]);
      expect(juan.contacto, '351 555-0101');
      expect(juan.esDeUnAlumno, isFalse);
      expect(personas['afuera|gomez lucia']!.bloques.single.id, deAfuera.id,
          reason: 'la de afuera no es la alumna');
      expect(personas['alumno|$_otraFamilia']!.bloques.single.id, otraFamilia.id);
    });

    test('primero quien tiene más sin rendir', () {
      final mucho = _dar(persona: 'ZAPATA, ANA', desde: 1201, cantidad: 20);
      final poco = _dar(persona: 'ACOSTA, LUIS', desde: 1301, cantidad: 3);
      final nada = _dar(persona: 'BRAVO, EVA', desde: 1401, cantidad: 2);
      final r = _rendicion(nada, 2);
      final p = _cuenta([poco, nada, r.vendio, mucho], ventas: [r.venta]);
      expect([for (final per in p.porPersona) per.nombre],
          ['ZAPATA, ANA', 'ACOSTA, LUIS', 'BRAVO, EVA']);
      expect(p.porPersona.last.rindioTodo, isTrue);
      expect(p.porPersona.last.desde, isNull);
      expect(p.porPersona.first.desde, mucho.createdAt);
    });

    test('los totales: personas, sin rendir, faltan hasta y lo que no volvió, sin '
        'los bloques anulados', () {
      final juan = _dar(persona: 'PÉREZ, JUAN', desde: 1201, cantidad: 20);
      final lucia = _dar(persona: 'GÓMEZ, LUCÍA', desde: 1221, cantidad: 10, precio: 10000,
          nombrePrecio: 'Entrada');
      final sol = _dar(persona: 'FERREYRA, SOL', desde: 1231, cantidad: 8);
      final anulado = _dar(persona: 'MOLINA, CARLOS', desde: 1241, cantidad: 10);
      // Otro bloque de JUAN y otro de SOL, los dos anulados.
      final juanAnulado = _dar(persona: 'PÉREZ, JUAN', desde: 1251, cantidad: 6);
      final solAnulado = _dar(persona: 'FERREYRA, SOL', desde: 1261, cantidad: 3);
      final rJuan = _rendicion(juan, 15);
      final rSol = _rendicion(sol, 8);
      // Lo que otro equipo anotó en los bloques de CARLOS y de JUAN antes de
      // enterarse de que el jefe los anuló (el caso del aviso "anuladas, pero
      // tienen algo rendido"): el bloque lo muestra, y no lo suma ni su persona
      // ni la fiesta.
      final rCarlos = _rendicion(anulado, 3, numero: 2);
      final perdidasCarlos = _noVolvieron(anulado, 2);
      final devolvioCarlos = _devolvio(anulado, [_del(1249, 1250)]);
      final rJuanAnulado = _rendicion(juanAnulado, 1, numero: 3);
      final perdidasJuanAnulado = _noVolvieron(juanAnulado, 4);
      final p = _cuenta(
        [
          juan,
          lucia,
          sol,
          anulado,
          juanAnulado,
          solAnulado,
          rJuan.vendio,
          rSol.vendio,
          _noVolvieron(lucia, 2),
          rCarlos.vendio,
          perdidasCarlos,
          devolvioCarlos,
          rJuanAnulado.vendio,
          perdidasJuanAnulado,
          _anulo(anulado),
          _anulo(juanAnulado),
          _anulo(solAnulado),
        ],
        ventas: [rJuan.venta, rSol.venta, rCarlos.venta, rJuanAnulado.venta],
      );

      // Sin esto la prueba no prueba nada: los bloques anulados sí tienen algo.
      final bCarlos = p.bloque(anulado.id)!;
      expect(
        [bCarlos.anulado, bCarlos.vendidas, bCarlos.devueltas, bCarlos.noVolvieron],
        [true, 3, 2, 2],
      );
      expect(bCarlos.plataRendida, 24000);
      expect(bCarlos.plataNoVolvio, 16000);
      final bJuanAnulado = p.bloque(juanAnulado.id)!;
      expect([bJuanAnulado.vendidas, bJuanAnulado.noVolvieron], [1, 4]);
      expect(
        [
          for (final a in p.avisos)
            if (a.que == QueAvisoParaRendir.anuladoConMovimientos) a.bloqueId,
        ],
        [anulado.id, juanAnulado.id],
      );

      // La fiesta.
      expect(p.personas, 2, reason: 'SOL rindió todo y CARLOS está anulado');
      expect(p.sinRendir, 5 + 8);
      expect(p.plataQueFalta, 5 * 8000 + 8 * 10000);
      expect(p.noVolvieron, 2, reason: 'las de LUCÍA; las de los bloques anulados, no');
      expect(p.plataNoVolvio, 20000);
      expect(p.hayParaRendir, isTrue);
      expect(p.bloques.map((b) => b.id),
          [juan.id, lucia.id, sol.id, anulado.id, juanAnulado.id, solAnulado.id],
          reason: 'el más viejo primero, también los anulados');

      // Cada persona: lo que se llevó, vendió, devolvió, no volvió, le queda,
      // rindió y valía lo perdido, y si rindió todo.
      List<Object?> cuentaDe(PersonaParaRendir per) => [
            per.seLlevo,
            per.vendidas,
            per.devueltas,
            per.noVolvieron,
            per.sinRendir,
            per.rindioDeMas,
            per.plataRendida,
            per.plataQueFalta,
            per.plataNoVolvio,
            per.rindioTodo,
          ];
      final personas = {for (final per in p.porPersona) per.clave: per};
      final carlos = personas['afuera|molina carlos']!;
      expect(carlos.bloques.single.id, anulado.id, reason: 'sigue en la lista');
      expect(cuentaDe(carlos), [0, 0, 0, 0, 0, 0, 0, 0, 0, false],
          reason: 'solo tiene un bloque anulado: no se llevó nada ni rindió todo');
      expect(carlos.desde, isNull);
      final dePerez = personas['afuera|perez juan']!;
      expect(dePerez.bloques.map((b) => b.id), [juan.id, juanAnulado.id]);
      expect(cuentaDe(dePerez), [20, 15, 0, 0, 5, 0, 120000, 40000, 0, false],
          reason: 'sin lo del bloque anulado: 6 que se llevó, 1 vendida y 4 perdidas');
      final deFerreyra = personas['afuera|ferreyra sol']!;
      expect(deFerreyra.bloques.map((b) => b.id), [sol.id, solAnulado.id]);
      expect(cuentaDe(deFerreyra), [8, 8, 0, 0, 0, 0, 64000, 0, 0, true],
          reason: 'rindió todo lo que tiene en pie: el bloque anulado no le falta');
      expect(cuentaDe(personas['afuera|gomez lucia']!),
          [10, 0, 0, 2, 8, 0, 0, 80000, 20000, false]);
    });

    test('sin nada', () {
      final p = _cuenta(const []);
      expect(p.bloques, isEmpty);
      expect(p.porPersona, isEmpty);
      expect(p.avisos, isEmpty);
      expect(p.personas, 0);
      expect(p.hayParaRendir, isFalse);
      expect(p.ocupados, isEmpty);
    });
  });
}
