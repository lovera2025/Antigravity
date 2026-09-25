import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/reparto_de_sillas.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sillas_reparto.dart';

ContratoAlumno _alumno({
  int extras = 0,
  int sillas = 0,
  double precioSillas = -1,
  List<int> mesas = const [],
}) =>
    ContratoAlumno(
      id: 'a',
      eventoId: 'e',
      nombreAlumno: 'PÉREZ, JUAN',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: precioSillas >= 0 ? precioSillas : 8000.0 * sillas,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
    );

SillasReparto _guardado({
  required int principal,
  required int sillas,
  required int mesas,
}) =>
    SillasReparto(
      id: 'r',
      contratoAlumnoId: 'a',
      sillasPrincipal: principal,
      sillasExtra: sillas,
      mesas: mesas,
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );

List<String> _textos(List<OpcionReparto> ops) => [for (final o in ops) o.texto];

void main() {
  group('opciones', () {
    test('con una mesa extra', () {
      expect(_textos(RepartoDeSillas.opciones(sillas: 1, mesas: 2)), ['1P', '1A']);
      expect(
        _textos(RepartoDeSillas.opciones(sillas: 2, mesas: 2)),
        ['2P', '1P · 1A', '2A'],
      );
      expect(
        _textos(RepartoDeSillas.opciones(sillas: 3, mesas: 2)),
        ['2P · 1A', '1P · 2A'],
      );
      expect(_textos(RepartoDeSillas.opciones(sillas: 4, mesas: 2)), ['2P · 2A']);
    });

    test('con una sola mesa, todo va a la principal', () {
      expect(_textos(RepartoDeSillas.opciones(sillas: 1, mesas: 1)), ['1P']);
      expect(_textos(RepartoDeSillas.opciones(sillas: 2, mesas: 1)), ['2P']);
    });

    test('con dos mesas extra, las adicionales suman hasta 4', () {
      expect(
        _textos(RepartoDeSillas.opciones(sillas: 2, mesas: 3)),
        ['2P', '1P · 1A', '2A'],
      );
      expect(
        _textos(RepartoDeSillas.opciones(sillas: 5, mesas: 3)),
        ['2P · 3A', '1P · 4A'],
      );
      expect(_textos(RepartoDeSillas.opciones(sillas: 6, mesas: 3)), ['2P · 4A']);
    });

    test('si no entran, no hay ninguna', () {
      expect(RepartoDeSillas.opciones(sillas: 3, mesas: 1), isEmpty);
      expect(RepartoDeSillas.opciones(sillas: 5, mesas: 2), isEmpty);
    });

    test('sin sillas o sin mesas, ninguna', () {
      expect(RepartoDeSillas.opciones(sillas: 0, mesas: 2), isEmpty);
      expect(RepartoDeSillas.opciones(sillas: 2, mesas: 0), isEmpty);
    });
  });

  group('estado', () {
    test('sin sillas extra: no aplica', () {
      expect(
        RepartoDeSillas.estado(_alumno(extras: 1), null),
        EstadoRepartoSillas.noAplica,
      );
    });

    test('las sillas sin precio no cuentan, igual que en la cuenta', () {
      expect(
        RepartoDeSillas.estado(_alumno(extras: 1, sillas: 3, precioSillas: 0), null),
        EstadoRepartoSillas.noAplica,
      );
    });

    test('una sola forma: no hay que llamar', () {
      final a = _alumno(sillas: 2);
      expect(RepartoDeSillas.estado(a, null), EstadoRepartoSillas.unicaOpcion);
      expect(RepartoDeSillas.faltaElegir(a, null), isFalse);
      expect(RepartoDeSillas.vigente(a, null), const OpcionReparto(2, 0));
    });

    test('varias formas y nada elegido: a confirmar, con el reparto de siempre',
        () {
      final a = _alumno(extras: 1, sillas: 3);
      expect(RepartoDeSillas.estado(a, null), EstadoRepartoSillas.aConfirmar);
      expect(RepartoDeSillas.faltaElegir(a, null), isTrue);
      expect(RepartoDeSillas.vigente(a, null), const OpcionReparto(2, 1));
    });

    test('eligió para esta cuenta: elegido', () {
      final a = _alumno(extras: 1, sillas: 3);
      final g = _guardado(principal: 1, sillas: 3, mesas: 2);
      expect(RepartoDeSillas.estado(a, g), EstadoRepartoSillas.elegido);
      expect(RepartoDeSillas.vigente(a, g), const OpcionReparto(1, 2));
    });

    test('si después compró otra silla, la elección deja de valer', () {
      final a = _alumno(extras: 1, sillas: 2);
      final g = _guardado(principal: 1, sillas: 3, mesas: 2);
      expect(RepartoDeSillas.estado(a, g), EstadoRepartoSillas.aConfirmar);
      expect(RepartoDeSillas.elegidoVigente(a, g), isNull);
    });

    test('si cambiaron sus mesas, también', () {
      final a = _alumno(extras: 2, sillas: 3);
      final g = _guardado(principal: 1, sillas: 3, mesas: 2);
      expect(RepartoDeSillas.estado(a, g), EstadoRepartoSillas.aConfirmar);
    });

    test('una elección que ya no es posible no se usa', () {
      final a = _alumno(extras: 1, sillas: 3);
      final g = _guardado(principal: 0, sillas: 3, mesas: 2);
      expect(RepartoDeSillas.elegidoVigente(a, g), isNull);
      expect(RepartoDeSillas.estado(a, g), EstadoRepartoSillas.aConfirmar);
    });

    test('más sillas de las que entran: revisar', () {
      final a = _alumno(sillas: 3);
      expect(RepartoDeSillas.estado(a, null), EstadoRepartoSillas.revisar);
      expect(RepartoDeSillas.vigente(a, null), isNull);
      expect(RepartoDeSillas.faltaElegir(a, null), isFalse);
    });
  });

  group('en las mesas', () {
    test('sin elección, el reparto de siempre (no cambió nada)', () {
      final a = _alumno(extras: 1, sillas: 3, mesas: [12, 13]);
      expect(SalonMesas.repartoSillas(a), [(12, 2), (13, 1)]);
      expect(SalonMesas.textoRepartoSillas(a), '12 (+2) · 13 (+1)');
    });

    test('con la elección, la principal lleva lo elegido', () {
      final a = _alumno(extras: 1, sillas: 3, mesas: [12, 13]);
      expect(SalonMesas.repartoSillas(a, sillasPrincipal: 1), [(12, 1), (13, 2)]);
      expect(
        SalonMesas.textoRepartoSillas(a, sillasPrincipal: 1),
        '12 (+1) · 13 (+2)',
      );
    });

    test('todo a la adicional: la principal no aparece', () {
      final a = _alumno(extras: 1, sillas: 2, mesas: [12, 13]);
      expect(SalonMesas.repartoSillas(a, sillasPrincipal: 0), [(13, 2)]);
    });
  });
}
