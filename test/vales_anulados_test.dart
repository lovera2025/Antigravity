// Los vales de la barra cuya venta se anuló (6.4.0): con ellos Recepción marca en
// rojo la silla que se sumó con ese vale. Sin pantalla ni base.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/recepcion/services/vales_anulados.dart';
import 'package:arguello_events/models/silla_puerta.dart';

import 'helpers/puerta_en_memoria.dart' show alumnoDePrueba, eventoMasivo;

final _ahora = DateTime.utc(2026, 12, 5, 2);

CajaBarra _caja(int numero) =>
    CajaBarra.abrir(eventoId: eventoMasivo, numeroCaja: numero, ahora: _ahora);

VentaBarra _venta(CajaBarra caja, int numero) => VentaBarra.nueva(
      cajaBarraId: caja.id,
      eventoId: eventoMasivo,
      numero: numero,
      renglones: const [
        RenglonVenta(productoId: 's', nombre: 'Silla extra', precio: 8000, cantidad: 1),
      ],
      medio: MedioBarra.efectivo,
      efectivo: 8000,
      ahora: _ahora,
    );

AnulacionBarra _anular(VentaBarra v) =>
    AnulacionBarra.de(v, motivo: 'se arrepintió', ahora: _ahora);

void main() {
  final caja2 = _caja(2);
  final caja3 = _caja(3);
  final v17 = _venta(caja2, 17);
  final v18 = _venta(caja2, 18);
  final v17deLa3 = _venta(caja3, 17);

  group('qué vale está anulado', () {
    final anulados = ValesAnulados.de(
      cajas: [caja2, caja3],
      ventas: [v17, v18, v17deLa3],
      anulaciones: [_anular(v17)],
    );

    test('la venta anulada, escrita como sea', () {
      for (final vale in ['2-17', '2 0017', 'Caja 2 · N° 0017', '2-17-1']) {
        expect(anulados.estaAnulado(vale), isTrue, reason: vale);
      }
    });

    test('las que no se anularon, no', () {
      expect(anulados.estaAnulado('2-18'), isFalse);
      expect(anulados.estaAnulado('3-17'), isFalse, reason: 'otra caja, mismo número');
    });

    test('un vale sin la caja nunca: no se sabe de cuál es', () {
      expect(anulados.estaAnulado('17'), isFalse);
      expect(anulados.estaAnulado(null), isFalse);
    });
  });

  test('dos cajas con el mismo número, una anulada y otra no: no se acusa', () {
    final otraDos = _caja(2);
    final otra17 = _venta(otraDos, 17);
    final anulados = ValesAnulados.de(
      cajas: [caja2, otraDos],
      ventas: [v17, otra17],
      anulaciones: [_anular(v17)],
    );
    expect(anulados.estaAnulado('2-17'), isFalse);
  });

  test('una venta de una caja que esta PC no conoce no cuenta', () {
    final anulados = ValesAnulados.de(
      cajas: const [],
      ventas: [v17],
      anulaciones: [_anular(v17)],
    );
    expect(anulados.vacio, isTrue);
  });

  test('ida y vuelta por JSON', () {
    final anulados = ValesAnulados.de(
      cajas: [caja2],
      ventas: [v17],
      anulaciones: [_anular(v17)],
    );
    final vuelta = ValesAnulados.fromJson(anulados.toJson());
    expect(vuelta.estaAnulado('2-17'), isTrue);
    expect(ValesAnulados.fromJson('cualquier cosa').vacio, isTrue);
  });

  group('en la puerta', () {
    const ana = 'c1000000-0000-4000-8000-000000000001';
    final anulados = ValesAnulados.de(
      cajas: [caja2],
      ventas: [v17, v18],
      anulaciones: [_anular(v17)],
    );
    SillaPuerta silla(String id, String vale) => SillaPuerta(
          id: id,
          eventoId: eventoMasivo,
          contratoAlumnoId: ana,
          mesa: 13,
          vale: vale,
          anotadoPor: 'Juli',
          createdAt: _ahora,
          updatedAt: _ahora,
        );
    final puerta = PuertaDelEvento.masivo(
      alumnos: [alumnoDePrueba(ana, 'GÓMEZ, ANA', mesas: [13])],
      invitados: const [],
      sillasPuerta: [silla('s1', '2-17'), silla('s2', '2-18')],
      valesAnulados: anulados,
    );
    final grupo = puerta.grupos.single;

    test('la silla con el vale anulado se marca; la otra no', () {
      expect(grupo.valeAnulado(grupo.movimientos.first), isTrue);
      expect(grupo.valeAnulado(grupo.movimientos.last), isFalse);
    });

    test('la silla sigue ocupando lugar hasta que se quite con motivo', () {
      expect(grupo.sillasPorMesa.mesas.single.sumadas, 2);
      expect(grupo.puedeSumarSilla, isFalse);
    });

    test('el conteo de la noche lo dice', () {
      expect(puerta.conteoDeLaNoche.texto,
          'Esta noche: 2 sillas sumadas · vales 2-17, 2-18 · 1 con el vale anulado');
    });

    test('una quitada con el vale anulado ya no se marca', () {
      final p = PuertaDelEvento.masivo(
        alumnos: [alumnoDePrueba(ana, 'GÓMEZ, ANA', mesas: [13])],
        invitados: const [],
        sillasPuerta: [
          silla('s1', '2-17').quitada(por: 'Juli', motivo: 'vale anulado', ahora: _ahora),
        ],
        valesAnulados: anulados,
      );
      expect(p.grupos.single.conValeAnulado, isEmpty);
      expect(p.conteoDeLaNoche.conValeAnulado, 0);
    });

    test('llega igual al celular', () {
      // Por la red, como texto.
      final llego = PuertaDelEvento.fromJson(
        jsonDecode(jsonEncode(puerta.toJson())) as Map<String, dynamic>,
        eventoId: eventoMasivo,
      );
      final g = llego.grupos.single;
      expect(g.valeAnulado(g.movimientos.first), isTrue);
      expect(llego.conteoDeLaNoche.texto, puerta.conteoDeLaNoche.texto);
      expect(llego.valesAnulados.estaAnulado('2-17'), isTrue);
    });

    test('sumar con un vale anulado no entra', () {
      final d = decidirSilla(
        pedido: PedidoPuerta(
          id: 'x',
          que: QuePide.sumarSilla,
          personaId: grupo.titular.id,
          silla: const DatosSilla(vale: '2 0017'),
        ),
        grupo: grupo,
        deLaNoche: const [],
        valesAnulados: anulados,
      );
      expect(d.haceAlgo, isFalse);
      expect(d.aviso, 'El vale 2-17 está anulado en la barra.');
    });
  });
}
