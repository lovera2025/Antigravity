// Arnés manual: el recibo de un evento particular (RECIBO DE CUENTA), con datos
// inventados, para mirar el papel sin levantar la app ni tocar la base.
//
//   flutter test tool/recibo_particular_muestra_test.dart
//   flutter test tool/recibo_particular_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen tres PDF: corto (5 filas entre pagos y servicios), medio (15) y largo
// (30). Lo que se mira:
//   • el encabezado entero adentro de la hoja: la etiqueta "RECIBO DE CUENTA",
//     "Emitido", el título del evento y la frase "Este evento fue diseñado
//     para …, a solicitud de …", que con dos nombres largos baja de renglón;
//   • el margen: nada pegado al borde del papel;
//   • el corto y el medio, en una sola hoja; el largo sigue en otra con los
//     títulos de las columnas repetidos, sin cortar ninguna fila;
//   • el total y el pie, siempre.
//
// El 10-nov-2026 el usuario contó que el recibo de los particulares salía
// recortado: "el encabezado es como que no sale bien". La columna derecha del
// encabezado no tenía tope de ancho y se salía de la hoja.
//
// Los nombres son inventados: la muestra nunca usa datos reales.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/servicio.dart';
import 'package:arguello_events/models/transaccion.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

const _servicios = [
  'Salón Costa Surubí, viernes',
  'Catering de tres pasos',
  'Barra libre de tragos',
  'Mesa dulce',
  'DJ y sonido',
  'Iluminación de pista',
  'Pantalla y proyector',
  'Fotografía y video',
  'Cabina de fotos',
  'Ambientación y centros de mesa',
  'Mozos',
  'Seguridad',
  'Torta de tres pisos',
  'Souvenirs',
  'Carioca y cotillón',
  'Show de fuegos fríos',
  'Maquillaje y peinado',
  'Traslado de invitados',
];

Evento eventoDeMuestra() => Evento(
      id: 'muestra',
      clienteId: 'c',
      tipo: 'Cumpleaños de 15',
      fechaEvento: DateTime(2026, 12, 19),
      estado: EstadoEvento.confirmado,
      nombreFestejado: 'María Fernanda Villalba Benítez',
      cliente: Cliente(id: 'c', nombreCompleto: 'JUAN CARLOS VILLALBA GONZÁLEZ'),
    );

List<EventosServicios> serviciosDeMuestra(int cuantos) => [
      for (var i = 0; i < cuantos; i++)
        EventosServicios(
          id: 's$i',
          eventoId: 'muestra',
          servicioId: 'srv$i',
          precioFinalAcordado: 120000.0 + 35000 * (i % 5),
          cantidad: i % 4 == 0 ? 2 : 1,
          servicio: Servicio(
            id: 'srv$i',
            nombre: _servicios[i % _servicios.length],
            categoria: 'General',
          ),
        ),
    ];

List<Transaccion> pagosDeMuestra(int cuantos) => [
      for (var i = 0; i < cuantos; i++)
        Transaccion(
          id: 't$i',
          eventoId: 'muestra',
          monto: 150000.0 + 25000 * (i % 3),
          concepto: i == 0 ? 'Seña' : 'Pago ${i + 1}',
          fechaPago: DateTime.utc(2026, 6 + i ~/ 3, 5 + i * 2, 15, 30),
          medioPago: i.isEven ? 'Efectivo' : 'Transferencia',
        ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final destino = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('recibo_particular').path;

  for (final (nombre, pagos, servicios) in [
    ('corto', 2, 3),
    ('medio', 6, 9),
    ('largo', 12, 18),
  ]) {
    test('recibo de un particular — $nombre', () async {
      final lista = serviciosDeMuestra(servicios);
      final cobros = pagosDeMuestra(pagos);
      final total = lista.fold<double>(
        0,
        (s, x) => s + x.precioFinalAcordado * x.cantidad,
      );
      final pagado = cobros.fold<double>(0, (s, t) => s + t.monto);
      final bytes = await PdfService.construirReciboParticularPdf(
        evento: eventoDeMuestra(),
        saldoActual: total - pagado,
        transacciones: cobros,
        servicios: lista,
        titulo: 'RECIBO DE CUENTA',
        emitido: DateTime.utc(2026, 11, 10, 15),
      );
      final archivo = File(
        '$destino${Platform.pathSeparator}Recibo_particular_MUESTRA_$nombre.pdf',
      )..writeAsBytesSync(bytes);
      stdout.writeln('── PDF en: ${archivo.path}');
      expect(archivo.lengthSync(), greaterThan(1000));
    });
  }
}
