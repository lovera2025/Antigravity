import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/reimpresion_de_barra.dart';
import 'package:arguello_events/features/barra/cuentas/vales_de_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

/// El freno de la copia (3-nov): la cajera reimprime solo la última venta de su caja, una
/// vez, con motivo; la copia saca el mismo vale que salió; una anulada no se reimprime.
const _caja = 'b0000000-0000-4000-8000-000000000001';
const _evento = 'e0000000-0000-4000-8000-000000000001';

void main() {
  final ahora = DateTime.utc(2026, 12, 5, 1, 30);

  VentaBarra venta(int numero, {List<RenglonVenta>? renglones}) {
    final r = renglones ??
        const [
          RenglonVenta(productoId: 'a', nombre: 'Cerveza lata', precio: 3500, cantidad: 10),
          RenglonVenta(productoId: 'b', nombre: 'Fernet con coca', precio: 6000, cantidad: 2),
        ];
    final total = r.fold<double>(0, (s, x) => s + x.subtotal);
    return VentaBarra.nueva(
      cajaBarraId: _caja,
      eventoId: _evento,
      numero: numero,
      renglones: r,
      medio: MedioBarra.efectivo,
      efectivo: total,
      ahora: ahora,
    );
  }

  ValeBarra salio(
    VentaBarra v,
    List<BebidaDelVale> bebidas, {
    int? numero,
    bool porSeparado = false,
    int copia = 0,
  }) =>
      ValeBarra.salio(
        venta: v,
        bebidas: bebidas,
        porSeparado: porSeparado,
        numeroVale: numero,
        copiaNumero: copia,
        motivo: copia > 0 ? 'se le mojó' : null,
        ahora: ahora,
      );

  ValeBarra todoJunto(VentaBarra v) =>
      salio(v, const [BebidaDelVale(10, 'Cerveza lata'), BebidaDelVale(2, 'Fernet con coca')]);

  test('las ventas de la caja, la última primero, cada una con lo suyo', () {
    final a = venta(1), b = venta(2), c = venta(3);
    final lista = VentaDeLaCaja.armar(
      ventas: [a, c, b],
      anulaciones: [AnulacionBarra.de(b, motivo: 'error', ahora: ahora)],
      vales: [todoJunto(a), todoJunto(c)],
    );
    expect([for (final x in lista) x.venta.numero], [3, 2, 1]);
    expect([for (final x in lista) x.esLaUltima], [true, false, false]);
    expect([for (final x in lista) x.anulada], [false, true, false]);
    expect([for (final x in lista) x.vales.length], [1, 0, 1]);
    expect(VentaDeLaCaja.armar(ventas: const [], anulaciones: const [], vales: const []), isEmpty);
  });

  group('reimprimir', () {
    test('la última venta, con sus vales, se reimprime', () {
      final v = venta(4);
      final x = VentaDeLaCaja(venta: v, vales: [todoJunto(v)], esLaUltima: true);
      expect(x.porQueNoSeReimprime, isNull);
      final copia = x.copia(motivo: 'se le mojó', hechoPor: 'Marta', ahora: ahora);
      expect(copia, hasLength(1));
      expect(copia.single.vale.bebidas, todoJunto(v).bebidas, reason: 'el mismo vale que salió');
      expect(copia.single.vale.numero, isNull, reason: 'era el único: sin número');
      expect(copia.single.copia.numero, 1);
      expect(copia.single.copia.motivo, 'se le mojó');
      expect(copia.single.copia.hechoPor, 'Marta');
    });

    test('una venta que no es la última no la reimprime la cajera', () {
      final v = venta(3);
      final x = VentaDeLaCaja(venta: v, vales: [todoJunto(v)], esLaUltima: false);
      expect(x.porQueNoSeReimprime, 'Solo se reimprime la última venta');
      expect(x.copia(motivo: 'x', ahora: ahora), isEmpty);
    });

    test('una vez: con la copia hecha, la próxima solo el jefe', () {
      final v = venta(4);
      final x = VentaDeLaCaja(
        venta: v,
        vales: [todoJunto(v), salio(v, todoJunto(v).bebidas, copia: 1)],
        esLaUltima: true,
      );
      expect(x.porQueNoSeReimprime, 'Ya se reimprimió: otra copia, solo el jefe');
      expect(x.copia(motivo: 'otra vez', ahora: ahora), isEmpty);
    });

    test('una anulada no se reimprime', () {
      final v = venta(4);
      final x = VentaDeLaCaja(
        venta: v,
        anulacion: AnulacionBarra.de(v, motivo: 'error', ahora: ahora),
        vales: [todoJunto(v)],
        esLaUltima: true,
      );
      expect(x.porQueNoSeReimprime, 'Anulada: no se reimprime');
      expect(x.faltanVales, isFalse);
    });

    test('el jefe no tiene el freno: cualquier venta, otra copia de cada vale', () {
      final v = venta(2);
      final cerveza = salio(v, const [BebidaDelVale(10, 'Cerveza lata')], numero: 1, porSeparado: true);
      final fernet = salio(v, const [BebidaDelVale(2, 'Fernet con coca')], numero: 2, porSeparado: true);
      final x = VentaDeLaCaja(
        venta: v,
        vales: [cerveza, fernet, salio(v, cerveza.bebidas, numero: 1, porSeparado: true, copia: 1)],
        esLaUltima: false,
      );
      expect(x.sePuedeReimprimir, isFalse, reason: 'la cajera no: no es la última');
      expect(x.porQueNoReimprimeElJefe, isNull);
      final copia = x.copiaDelJefe(motivo: 'se le mojó', hechoPor: 'Jefe', ahora: ahora);
      expect([for (final c in copia) c.vale.numero], [1, 2], reason: 'todos los vales que salieron');
      expect([for (final c in copia) c.copia.numero], [2, 1], reason: 'cada uno con la copia que le sigue');
      expect(copia.first.copia.hechoPor, 'Jefe');
      expect(() => x.copiaDelJefe(motivo: '  ', ahora: ahora), throwsArgumentError);
    });

    test('el jefe tampoco reimprime una anulada, ni una venta sin vales', () {
      final v = venta(2);
      final anulada = VentaDeLaCaja(
        venta: v,
        anulacion: AnulacionBarra.de(v, motivo: 'error', ahora: ahora),
        vales: [todoJunto(v)],
        esLaUltima: false,
      );
      expect(anulada.porQueNoReimprimeElJefe, 'Anulada: no se reimprime');
      expect(anulada.copiaDelJefe(motivo: 'x', ahora: ahora), isEmpty);
      final sinVales = VentaDeLaCaja(venta: v, esLaUltima: true);
      expect(sinVales.porQueNoReimprimeElJefe, 'No salió ningún vale todavía');
    });

    test('sin vales que hayan salido no hay copia: se imprimen los que faltan', () {
      final v = venta(4);
      final x = VentaDeLaCaja(venta: v, esLaUltima: true);
      expect(x.porQueNoSeReimprime, 'No salió ningún vale todavía');
      expect(x.faltanVales, isTrue);
      expect(x.unidadesSinVale, 12);
    });

    test('por separado: cada vale con su número y lo que llevó, en orden', () {
      final v = venta(4);
      final x = VentaDeLaCaja(
        venta: v,
        vales: [
          salio(v, const [BebidaDelVale(2, 'Fernet con coca')], numero: 3, porSeparado: true),
          salio(v, const [BebidaDelVale(3, 'Cerveza lata')], numero: 1, porSeparado: true),
          salio(v, const [BebidaDelVale(7, 'Cerveza lata')], numero: 2, porSeparado: true),
        ],
        esLaUltima: true,
      );
      final copia = x.copia(motivo: 'perdió los papeles', ahora: ahora);
      expect([for (final c in copia) c.vale.numero], [1, 2, 3]);
      expect([for (final c in copia) c.vale.bebidas.single.cantidad], [3, 7, 2]);
      expect(copia.every((c) => c.vale.porSeparado), isTrue);
      expect(x.faltanVales, isFalse);
    });

    test('una copia cortada a la mitad se termina: el freno es por vale', () {
      final v = venta(4);
      final uno = salio(v, const [BebidaDelVale(10, 'Cerveza lata')], numero: 1, porSeparado: true);
      final dos = salio(v, const [BebidaDelVale(2, 'Fernet con coca')], numero: 2, porSeparado: true);
      final x = VentaDeLaCaja(
        venta: v,
        vales: [uno, dos, salio(v, uno.bebidas, numero: 1, porSeparado: true, copia: 1)],
        esLaUltima: true,
      );
      expect(x.porQueNoSeReimprime, isNull);
      expect([for (final c in x.copia(motivo: 'se cortó', ahora: ahora)) c.vale.numero], [2]);
    });

    test('sin motivo no hay copia', () {
      final v = venta(4);
      final x = VentaDeLaCaja(venta: v, vales: [todoJunto(v)], esLaUltima: true);
      expect(() => x.copia(motivo: '  ', ahora: ahora), throwsArgumentError);
    });
  });

  group('lo que falta imprimir', () {
    test('a la mitad: las unidades que no salieron', () {
      final v = venta(4);
      final x = VentaDeLaCaja(
        venta: v,
        vales: [salio(v, const [BebidaDelVale(3, 'Cerveza lata')], numero: 1, porSeparado: true)],
        esLaUltima: false,
      );
      expect(x.faltanVales, isTrue);
      expect(x.unidadesSinVale, 9);
    });

    test('las copias no cuentan como lo que salió', () {
      final v = venta(4);
      final x = VentaDeLaCaja(
        venta: v,
        vales: [
          salio(v, const [BebidaDelVale(3, 'Cerveza lata')], numero: 1, porSeparado: true),
          salio(v, const [BebidaDelVale(3, 'Cerveza lata')], numero: 1, porSeparado: true, copia: 1),
        ],
        esLaUltima: true,
      );
      expect(x.unidadesSinVale, 9);
    });
  });

  test('anular y el ticket: una anulada no se anula de nuevo ni saca ticket', () {
    final v = venta(4);
    expect(VentaDeLaCaja(venta: v, esLaUltima: false).porQueNoSeAnula, isNull);
    expect(VentaDeLaCaja(venta: v, esLaUltima: false).porQueNoHayTicket, isNull);
    final anulada = VentaDeLaCaja(
      venta: v,
      anulacion: AnulacionBarra.de(v, motivo: 'error', ahora: ahora),
      esLaUltima: true,
    );
    expect(anulada.porQueNoSeAnula, 'Ya está anulada');
    expect(anulada.porQueNoHayTicket, 'Anulada: no hay ticket');
  });

  test('el vale como salió, para la copia', () {
    final v = venta(4);
    final g = salio(v, const [BebidaDelVale(3, 'Cerveza lata')], numero: 2, porSeparado: true);
    final vale = Vale.comoSalio(g);
    expect(vale.bebidas, g.bebidas);
    expect(vale.numero, 2);
    expect(vale.porSeparado, isTrue);
  });
}
