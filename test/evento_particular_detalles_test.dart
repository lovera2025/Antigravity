// El evento particular muestra todo lo que se cargó en su presupuesto (6.2.1).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/utils/evento_presentacion.dart';
import 'package:arguello_events/features/eventos/utils/presupuesto_desde_evento.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/presupuesto.dart';

Evento _evento({Cliente? cliente}) => Evento(
      id: 'e0000000-0000-4000-8000-000000000001',
      clienteId: 'c',
      tipo: '15_años',
      fechaEvento: DateTime(2026, 11, 14),
      estado: EstadoEvento.planificacion,
      cliente: cliente,
      presupuestoId: 'p',
    );

Presupuesto _origen({String? lugar, String? telefono, String? instagram}) => Presupuesto(
      id: 'p',
      clienteId: 'c',
      tipoEvento: '15_años',
      lugar: lugar,
      telefono: telefono,
      instagram: instagram,
      fechaVencimiento: DateTime(2026, 12, 1),
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  group('el PDF que se regenera desde el evento', () {
    test('lleva el lugar, el WhatsApp y el Instagram del presupuesto', () {
      final p = presupuestoVirtualDesdeEvento(
        evento: _evento(),
        servicios: const [],
        origen: _origen(lugar: 'Quinta Los Aromos', telefono: '379 400-0000', instagram: 'otra_cuenta'),
      );
      expect(p.lugar, 'Quinta Los Aromos');
      expect(p.telefono, '379 400-0000');
      expect(p.instagram, 'otra_cuenta');
    });

    test('sin presupuesto (o vacío) usa los de la casa', () {
      final sin = presupuestoVirtualDesdeEvento(evento: _evento(), servicios: const []);
      expect(sin.lugar, isNull);
      expect(sin.telefono, kTelefonoPieDeLaCasa);
      expect(sin.instagram, kInstagramDeLaCasa);
      final vacio = presupuestoVirtualDesdeEvento(
        evento: _evento(),
        servicios: const [],
        origen: _origen(telefono: '  ', instagram: ''),
      );
      expect(vacio.telefono, kTelefonoPieDeLaCasa);
      expect(vacio.instagram, kInstagramDeLaCasa);
    });
  });

  test('el solicitante va con teléfono y email', () {
    final e = _evento(
      cliente: Cliente(id: 'c', nombreCompleto: 'Laura Gómez', telefono: '379 412-0000', email: 'laura@correo.com'),
    );
    expect(EventoPresentacion.lineaSolicitante(e), 'Solicitante: Laura Gómez · 379 412-0000 · laura@correo.com');
    final soloNombre = _evento(cliente: Cliente(id: 'c', nombreCompleto: 'Laura Gómez'));
    expect(EventoPresentacion.lineaSolicitante(soloNombre), 'Solicitante: Laura Gómez');
  });

  group('la pantalla del evento', () {
    final fuente = File('lib/features/eventos/detalle_evento_particular_screen.dart').readAsStringSync();

    test('DETALLES DEL EVENTO no desaparece vacía', () {
      final i = fuente.indexOf('Widget _buildSeccionInformacionEvento()');
      final cuerpo = fuente.substring(i, fuente.indexOf("'DETALLES DEL EVENTO'", i));
      expect(cuerpo, isNot(contains('SizedBox.shrink()')));
      expect(fuente, contains("'Sin detalles cargados.'"));
    });

    test('el lugar sale del presupuesto vinculado', () {
      expect(fuente, contains('presupuestosRepositoryProvider).getById(origenId)'));
      expect(fuente, contains("'Lugar: \${_presupuestoOrigen!.lugar!.trim()}'"));
    });

    test('la lista de servicios es ServiciosDelEvento, y editar ve los del presupuesto', () {
      expect(fuente, contains('ServiciosDelEvento(servicios: _servicios'));
      expect(fuente, contains('presupuestoOrigenId: _eventoActual.presupuestoId'));
      expect(fuente, contains('origen: _presupuestoOrigen'));
    });
  });
}
