import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';

import 'helpers/barra_en_memoria.dart';

/// **Quién puede qué en la barra** (decidido por el usuario el 26-nov-2026). Una prueba
/// por casillero de la matriz del plan, y la segunda llave: el guardado no hace lo que no
/// le toca a quien usa el aparato, aunque una pantalla lo deje.
const _fiesta = 'e0000000-0000-4000-8000-000000000001';

void main() {
  const cajera = RolEnLaBarra.cajera,
      encargada = RolEnLaBarra.encargada,
      repositor = RolEnLaBarra.repositor,
      jefe = RolEnLaBarra.jefe;

  group('la matriz', () {
    void fila(String que, bool Function(RolEnLaBarra?) regla, Set<RolEnLaBarra?> pueden) {
      test(que, () {
        for (final r in [cajera, encargada, repositor, jefe, null]) {
          expect(regla(r), pueden.contains(r), reason: '$que · $r');
        }
      });
    }

    fila('abrir caja y vender: la cajera y la encargada', ReglasDeLaBarra.abreCajaYVende, {cajera, encargada});
    fila('anular: la encargada y el jefe (la cajera no)', ReglasDeLaBarra.anula, {encargada, jefe});
    fila('retirar y manejar el cambio: la encargada y el jefe', ReglasDeLaBarra.manejaLaPlataDeLasCajas, {encargada, jefe});
    fila('ver la plata de todas las cajas: la encargada y el jefe', ReglasDeLaBarra.veLaPlataDeTodas, {encargada, jefe});
    fila('dar el OK: la encargada y el jefe', ReglasDeLaBarra.daElOk, {encargada, jefe});
    fila('mover el stock: el repositor y el jefe (la encargada no)', ReglasDeLaBarra.mueveElStock, {repositor, jefe});
    fila('repartir el stock: solo el jefe', ReglasDeLaBarra.reparteElStock, {jefe});
    fila('catálogo y precios: solo el jefe', ReglasDeLaBarra.cambiaCatalogoYPrecios, {jefe});

    test('el rol sale de los permisos', () {
      expect(ReglasDeLaBarra.dePermisos(const PermisosEfectivos(barra: true)), cajera);
      expect(ReglasDeLaBarra.dePermisos(const PermisosEfectivos(barra: true, encargadaBarra: true)), encargada);
      expect(ReglasDeLaBarra.dePermisos(const PermisosEfectivos(cobros: true)), isNull);
    });

    test('la cajera pone el cambio una vez: sin cambio y sin ventas', () {
      final sin = CajaBarra.abrir(eventoId: _fiesta, numeroCaja: 1, ahora: DateTime.now());
      final con = CajaBarra.abrir(eventoId: _fiesta, numeroCaja: 1, cambioInicial: 1000, ahora: DateTime.now());
      expect(ReglasDeLaBarra.cajeraPoneElCambio(sin, yaVendio: false), isTrue);
      expect(ReglasDeLaBarra.cajeraPoneElCambio(sin, yaVendio: true), isFalse);
      expect(ReglasDeLaBarra.cajeraPoneElCambio(con, yaVendio: false), isFalse);
    });

    test('cerrar: con el OK o sin esperar (con motivo); el jefe y la encargada, siempre', () {
      final c = CajaBarra.abrir(eventoId: _fiesta, numeroCaja: 1, ahora: DateTime.now());
      final pedido = PasoDelCierre.pedir(caja: c, efectivoContado: 0, hechoPor: 'Marta', ahora: DateTime.now());
      PasoDelCierre resp(TipoPasoDelCierre t) =>
          PasoDelCierre.responder(pedido: pedido, tipo: t, hechoPor: 'x', ahora: DateTime.now());
      expect(ReglasDeLaBarra.puedeCerrar(cajera, c.id, const []), isFalse);
      expect(ReglasDeLaBarra.puedeCerrar(cajera, c.id, [pedido]), isFalse, reason: 'esperando');
      expect(ReglasDeLaBarra.puedeCerrar(cajera, c.id, [pedido, resp(TipoPasoDelCierre.recontar)]), isFalse);
      expect(ReglasDeLaBarra.puedeCerrar(cajera, c.id, [pedido, resp(TipoPasoDelCierre.ok)]), isTrue);
      expect(ReglasDeLaBarra.puedeCerrar(encargada, c.id, [pedido, resp(TipoPasoDelCierre.sinOk)]), isTrue);
      expect(ReglasDeLaBarra.puedeCerrar(jefe, c.id, const []), isTrue);
      // 27-nov-2026: "La encargada puede cerrar su caja sin necesidad que le confirmen."
      expect(ReglasDeLaBarra.puedeCerrar(encargada, c.id, const []), isTrue);
      expect(ReglasDeLaBarra.cierraSinPedir(encargada), isTrue);
      expect(ReglasDeLaBarra.cierraSinPedir(cajera), isFalse);
      expect(ReglasDeLaBarra.cierraSinPedir(RolEnLaBarra.repositor), isFalse);
    });
  });

  group('la segunda llave: el guardado', () {
    late BarraEnMemoria barra;
    late RolEnLaBarra? rol;
    late BarraConLaRed conLlave;

    setUp(() {
      barra = BarraEnMemoria()..equipo = 'tablet-a';
      rol = cajera;
      conLlave = BarraConLaRed(caja: barra, jefe: barra, red: barra, aviso: AvisoALaRed(), rolDeQuienUsa: () => rol);
    });

    Future<VentaBarra> unaVenta(CajaBarra c) => conLlave.vender(
          caja: c,
          renglones: const [RenglonVenta(productoId: 'p', nombre: 'Fernet', precio: 6000, cantidad: 1)],
          medio: MedioBarra.efectivo,
          efectivo: 6000,
          quien: 'Marta',
        );

    test('la cajera no anula; la encargada sí', () async {
      final c = await conLlave.abrirCaja(eventoId: _fiesta, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
      final v = await unaVenta(c);
      await expectLater(conLlave.anular(v, motivo: 'x', quien: 'Marta'), throwsA(isA<NoLeTocaEnLaBarra>()));
      expect(barra.anulacionesGuardadas, isEmpty);
      rol = encargada;
      await conLlave.anular(v, motivo: 'x', quien: 'Romi');
      expect(barra.anulacionesGuardadas, hasLength(1));
    });

    test('la cajera no cierra sin el OK', () async {
      final c = await conLlave.abrirCaja(eventoId: _fiesta, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
      await expectLater(
        conLlave.cerrarCaja(c, efectivoContado: 0, diferencia: 0, quien: 'Marta'),
        throwsA(isA<NoLeTocaEnLaBarra>()),
      );
      expect(barra.cajasGuardadas.single.abierta, isTrue);
      final pedido = await conLlave.anotarPasoDelCierre(
          PasoDelCierre.pedir(caja: c, efectivoContado: 0, hechoPor: 'Marta', ahora: DateTime.now()));
      await conLlave.anotarPasoDelCierre(
          PasoDelCierre.responder(pedido: pedido, tipo: TipoPasoDelCierre.ok, hechoPor: 'Romi', ahora: DateTime.now()));
      await conLlave.cerrarCaja(c, efectivoContado: 0, diferencia: 0, quien: 'Marta');
      expect(barra.cajasGuardadas.single.abierta, isFalse);
    });

    test('el cambio: la cajera una vez antes de vender; después nadie lo pisa sin motivo, salvo el jefe', () async {
      var c = await conLlave.abrirCaja(eventoId: _fiesta, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
      c = await conLlave.ponerCambio(c, 20000, quien: 'Marta');
      await expectLater(conLlave.ponerCambio(c, 30000, quien: 'Marta'), throwsA(isA<NoLeTocaEnLaBarra>()));
      // 27-nov-2026: la encargada tampoco, ni en su propia caja ("con motivo y anotado").
      rol = encargada;
      await expectLater(
        conLlave.ponerCambio(c, 30000, quien: 'Romi'),
        throwsA(isA<NoLeTocaEnLaBarra>().having((e) => e.motivo, 'motivo', contains('LAS CAJAS'))),
      );
      expect(barra.cajasGuardadas.single.cambioInicial, 20000, reason: 'no se pisó');
      rol = RolEnLaBarra.jefe;
      c = await conLlave.ponerCambio(c, 30000, quien: 'Jefe');
      expect(c.cambioInicial, 30000);
    });

    test('la encargada con su caja pone el cambio una vez, antes de vender, como cualquiera', () async {
      rol = encargada;
      var c = await conLlave.abrirCaja(eventoId: _fiesta, operadorId: 'r', operadorNombre: 'Romi', numeroCaja: 2);
      c = await conLlave.ponerCambio(c, 15000, quien: 'Romi');
      expect(c.cambioInicial, 15000);
      await expectLater(conLlave.ponerCambio(c, 10000, quien: 'Romi'), throwsA(isA<NoLeTocaEnLaBarra>()));
      expect(ReglasDeLaBarra.pisaElCambioInicial(encargada), isFalse);
      expect(ReglasDeLaBarra.pisaElCambioInicial(cajera), isFalse);
      expect(ReglasDeLaBarra.pisaElCambioInicial(RolEnLaBarra.jefe), isTrue);
    });

    test('la cajera que ya vendió no pone el cambio', () async {
      final c = await conLlave.abrirCaja(eventoId: _fiesta, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
      await unaVenta(c);
      await expectLater(conLlave.ponerCambio(c, 20000, quien: 'Marta'), throwsA(isA<NoLeTocaEnLaBarra>()));
    });

    test('el repositor no abre caja ni vende; el catálogo y los precios, solo el jefe', () async {
      rol = repositor;
      await expectLater(
        conLlave.abrirCaja(eventoId: _fiesta, operadorId: 'n', operadorNombre: 'Nico', numeroCaja: 1),
        throwsA(isA<NoLeTocaEnLaBarra>()),
      );
      rol = encargada;
      final p = barra.producto('Fernet');
      await expectLater(conLlave.guardarProducto(p, quien: 'Romi'), throwsA(isA<NoLeTocaEnLaBarra>()));
      rol = jefe;
      await conLlave.guardarProducto(p, quien: 'Jefe');
    });

    test('la app pone la llave: la barra de este equipo pregunta quién la usa', () {
      final c = ProviderContainer(overrides: [rolEnLaBarraProvider.overrideWithValue(cajera)]);
      addTearDown(c.dispose);
      final barraDelEquipo = c.read(barraDeEsteEquipoProvider);
      expect(barraDelEquipo.rolDeQuienUsa, isNotNull);
      expect(barraDelEquipo.rolDeQuienUsa!(), cajera);
    });
  });
}
