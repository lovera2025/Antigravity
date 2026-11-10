// El recibo de un evento particular ("RECIBO DE CUENTA") sale entero.
//
// El 10-nov-2026 el usuario contó que salía recortado: "el encabezado es como
// que no sale bien". Reproducido con `tool/recibo_particular_muestra_test.dart`:
//  - la columna derecha del encabezado no tenía tope de ancho: la frase "Este
//    evento fue diseñado para …, a solicitud de …" se salía de la hoja, y se
//    llevaba afuera la etiqueta "RECIBO DE CUENTA" y "Emitido";
//  - todo el cuerpo era un solo bloque: con 15 filas entre pagos y servicios el
//    encabezado quedaba solo en la hoja 1, y con 30 el recibo no se podía armar
//    (`TooManyPagesException`; en la app instalada, sin fin);
//  - la hoja iba sin margen.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/servicio.dart';
import 'package:arguello_events/models/transaccion.dart';

import 'helpers/leer_pdf.dart';

Evento _evento({
  String? festejado = 'María Fernanda Villalba Benítez',
  String solicitante = 'JUAN CARLOS VILLALBA GONZÁLEZ',
}) =>
    Evento(
      id: 'e',
      clienteId: 'c',
      tipo: 'Cumpleaños de 15',
      fechaEvento: DateTime(2026, 12, 19),
      estado: EstadoEvento.confirmado,
      nombreFestejado: festejado,
      cliente: Cliente(id: 'c', nombreCompleto: solicitante),
    );

List<EventosServicios> _servicios(int cuantos) => [
      for (var i = 0; i < cuantos; i++)
        EventosServicios(
          id: 's$i',
          eventoId: 'e',
          servicioId: 'srv$i',
          precioFinalAcordado: 120000.0 + 1000 * i,
          servicio: Servicio(id: 'srv$i', nombre: 'SERVICIO$i', categoria: 'G'),
        ),
    ];

List<Transaccion> _pagos(int cuantos) => [
      for (var i = 0; i < cuantos; i++)
        Transaccion(
          id: 't$i',
          eventoId: 'e',
          monto: 150000.0 + i,
          concepto: 'PAGO$i',
          fechaPago: DateTime.utc(2026, 6, 1 + i, 15, 30),
          medioPago: 'Efectivo',
        ),
    ];

Future<Uint8List> _recibo({
  required int pagos,
  required int servicios,
  Evento? evento,
  bool letrasDeLaApp = false,
}) =>
    PdfService.construirReciboParticularPdf(
      evento: evento ?? _evento(),
      saldoActual: 100000,
      transacciones: _pagos(pagos),
      servicios: _servicios(servicios),
      titulo: 'RECIBO DE CUENTA',
      emitido: DateTime.utc(2026, 11, 10, 15),
      letrasDeLaApp: letrasDeLaApp,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ancho = 595.28; // A4
  const margen = 28.0;

  group('el encabezado', () {
    test('con festejado y solicitante de nombres largos, nada pasa del margen',
        () async {
      final palabras = palabrasDelPdf(await _recibo(pagos: 2, servicios: 3));
      expect(palabras, isNotEmpty);
      for (final p in palabras) {
        expect(
          p.x,
          greaterThanOrEqualTo(margen - 0.5),
          reason: '"${p.texto}" empieza antes del margen',
        );
        expect(
          p.x + p.ancho,
          lessThanOrEqualTo(ancho - margen + 0.5),
          reason: '"${p.texto}" termina en ${p.x + p.ancho}, fuera de la hoja',
        );
      }
      // Y está todo lo del encabezado.
      final texto = palabras.map((p) => p.texto).join(' ');
      for (final parte in [
        'RECIBO DE CUENTA',
        'Emitido:',
        'CUMPLEAÑOS DE 15 DE',
        'Este evento fue diseñado para',
        'a solicitud de',
        'GONZÁLEZ.',
      ]) {
        expect(texto, contains(parte));
      }
    });

    test('un nombre de sesenta letras tampoco se sale', () async {
      final largo = List.filled(6, 'ABCDEFGHIJ').join(' ');
      final palabras = palabrasDelPdf(await _recibo(
        pagos: 1,
        servicios: 1,
        evento: _evento(festejado: largo, solicitante: largo),
      ));
      for (final p in palabras) {
        expect(
          p.x + p.ancho,
          lessThanOrEqualTo(ancho - margen + 0.5),
          reason: '"${p.texto}" termina en ${p.x + p.ancho}',
        );
      }
    });

    test('sin festejado no lleva la frase, y sale igual', () async {
      final palabras = palabrasDelPdf(await _recibo(
        pagos: 1,
        servicios: 1,
        evento: _evento(festejado: null),
      ));
      final texto = palabras.map((p) => p.texto).join(' ');
      expect(texto, contains('RECIBO DE CUENTA'));
      expect(texto, isNot(contains('a solicitud de')));
    });
  });

  group('las hojas', () {
    test('es A4, con margen arriba y abajo', () async {
      final bytes = await _recibo(pagos: 2, servicios: 3);
      expect(paginasDelPdf(bytes), 1);
      for (final p in palabrasDelPdf(bytes)) {
        expect(p.y, greaterThanOrEqualTo(24 - 0.5), reason: p.texto);
        expect(
          p.y,
          lessThanOrEqualTo(PdfPageFormat.a4.height - 24 + 0.5),
          reason: p.texto,
        );
      }
    });

    test('con 15 filas entra en una hoja (antes, el encabezado quedaba solo en '
        'la primera)', () async {
      final bytes = await _recibo(pagos: 6, servicios: 9);
      expect(paginasDelPdf(bytes), 1);
      final texto = contenidoDelPdf(bytes);
      for (var i = 0; i < 6; i++) {
        expect(texto.contains('(PAGO$i)'), isTrue, reason: 'PAGO$i');
      }
      for (var i = 0; i < 9; i++) {
        expect(texto.contains('(SERVICIO$i)'), isTrue, reason: 'SERVICIO$i');
      }
      expect(texto.contains('(PRESUPUESTADO)'), isTrue);
      expect(texto.contains('(COMPROMISO)'), isTrue, reason: 'el pie');
    });

    test('con 30 filas se arma (antes no terminaba nunca)', () async {
      final bytes = await _recibo(pagos: 12, servicios: 18);
      expect(paginasDelPdf(bytes), lessThanOrEqualTo(2));
      final texto = contenidoDelPdf(bytes);
      for (var i = 0; i < 12; i++) {
        expect(texto.contains('(PAGO$i)'), isTrue, reason: 'PAGO$i');
      }
      for (var i = 0; i < 18; i++) {
        expect(texto.contains('(SERVICIO$i)'), isTrue, reason: 'SERVICIO$i');
      }
      expect(texto.contains('(PRESUPUESTADO)'), isTrue);
    });

    test('con 120 filas sigue en otras hojas, con los títulos repetidos y sin '
        'perder ninguna', () async {
      final bytes = await _recibo(pagos: 40, servicios: 80);
      final hojas = paginasDelPdf(bytes);
      expect(hojas, greaterThan(1));
      final texto = contenidoDelPdf(bytes);
      for (var i = 0; i < 40; i++) {
        expect(texto.contains('(PAGO$i)'), isTrue, reason: 'PAGO$i');
      }
      for (var i = 0; i < 80; i++) {
        expect(texto.contains('(SERVICIO$i)'), isTrue, reason: 'SERVICIO$i');
      }
      // "SUBTOTAL" es título de columna de los servicios: una vez por hoja en
      // la que la tabla sigue.
      expect('(SUBTOTAL)'.allMatches(texto).length, greaterThan(1));
      expect(texto.contains('(PRESUPUESTADO)'), isTrue);
      expect(texto.contains('(COMPROMISO)'), isTrue, reason: 'el pie');
    });

    test('sin pagos ni servicios, también', () async {
      final bytes = await _recibo(pagos: 0, servicios: 0);
      expect(paginasDelPdf(bytes), 1);
      expect(contenidoDelPdf(bytes).contains('(COMPROMISO)'), isTrue);
    });
  });

  test('se arma con las letras de la app, sin internet', () async {
    // `flutter test` no tiene red: si volviera `PdfGoogleFonts`, esto fallaría
    // o saldría con otra letra.
    for (final (pagos, servicios) in [(2, 3), (6, 9), (12, 18)]) {
      final bytes = await _recibo(
        pagos: pagos,
        servicios: servicios,
        letrasDeLaApp: true,
      );
      expect(bytes.length, greaterThan(1000));
      expect(paginasDelPdf(bytes), 1, reason: '$pagos pagos, $servicios servicios');
    }
  });
}
