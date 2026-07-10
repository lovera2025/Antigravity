import 'package:arguello_events/features/eventos/utils/evento_presentacion.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/presupuesto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventoPresentacion nombres maestro', () {
    test('nombre suelto compone encabezado 15 años', () {
      final enc = EventoPresentacion.resolverEncabezado(
        nombreFestejado: 'Pauli',
        tipoEvento: '15_años',
      );
      expect(enc, 'LOS 15 DE Pauli');
    });

    test('encabezado personalizado tiene prioridad', () {
      final enc = EventoPresentacion.resolverEncabezado(
        encabezadoPersonalizado: 'Los 15 de Pauli',
        nombreFestejado: 'Pauli',
        tipoEvento: '15_años',
      );
      expect(enc, 'LOS 15 DE PAULI');
    });

    test('frase intro usa nombres explícitos', () {
      final frase = EventoPresentacion.fraseIntroDesdeNombres(
        nombreFestejado: 'Pauli',
        solicitante: 'García',
        paraPresupuesto: true,
      );
      expect(frase, contains('Pauli'));
      expect(frase, contains('García'));
    });

    test('legacy titulo_festejado se divide en migración', () {
      final partes = EventoPresentacion.dividirTituloFestejadoLegacy(
        'Los 15 de Morena',
        '15_años',
      );
      expect(partes.encabezadoEvento, 'LOS 15 DE MORENA');
      expect(partes.nombreFestejado, 'Morena');
    });

    test('evento con campos nuevos', () {
      final evento = Evento(
        id: 'e1',
        clienteId: 'c1',
        tipo: '15_años',
        fechaEvento: DateTime(2026, 12, 1),
        estado: EstadoEvento.planificacion,
        nombreFestejado: 'Pauli',
        encabezadoEvento: 'LOS 15 DE PAULI',
        cliente: Cliente(id: 'c1', nombreCompleto: 'García'),
      );
      expect(EventoPresentacion.tituloPrincipal(evento), 'LOS 15 DE PAULI');
      expect(
        EventoPresentacion.fraseIntroEvento(evento, paraPresupuesto: true),
        'Esta propuesta ha sido diseñada para Pauli, a solicitud de García.',
      );
      expect(EventoPresentacion.necesitaConfiguracionMaestra(evento), isFalse);
    });

    test('subtitulo presupuesto: fecha larga del evento o vacío', () {
      final conFecha = Presupuesto(
        id: 'p1',
        clienteId: 'c1',
        tipoEvento: '15_años',
        fechaVencimiento: DateTime(2026, 7, 15),
        fechaEvento: DateTime(2026, 12, 1),
        createdAt: DateTime(2026, 7, 1),
      );
      expect(
        EventoPresentacion.subtituloDesdePresupuesto(conFecha),
        'Fecha del evento: 1 de diciembre de 2026',
      );

      final sinFecha = Presupuesto(
        id: 'p2',
        clienteId: 'c1',
        tipoEvento: '15_años',
        fechaVencimiento: DateTime(2026, 7, 20),
        createdAt: DateTime(2026, 7, 1),
      );
      expect(EventoPresentacion.subtituloDesdePresupuesto(sinFecha), isEmpty);
    });
  });
}
