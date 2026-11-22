// El comprobante de una venta de entradas (sección 7.4 del spec del 13-nov),
// **con la forma del "RECIBO DE PAGO" de las cuotas, tal cual** (el usuario,
// 22-nov-2026: "hacelo como un recibo tal cual"): media hoja A4 con lo común
// (1 y 6 renglones, también con las letras de la app), la hoja que crece en vez
// de recortar, nada que se salga, y lo que la venta tiene guardado en el lugar
// del recibo. Sin pulseras: la pulsera no se vende. El de una rendición está en
// `comprobante_rendicion_test.dart`.
//
// Se arma con la letra de fábrica del paquete: con las de la app el texto va en
// códigos de glifo y no se puede leer. En un PDF el texto sale palabra por
// palabra: se busca cada palabra, no la frase.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:arguello_events/features/common/services/emisor_del_recibo.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/comprobante_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/pdf/recibo_de_entradas_pdf.dart';

import 'helpers/leer_pdf.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
final _ahora = DateTime.utc(2026, 11, 14, 14, 32); // 11:32 en Argentina

VentaEntradas _venta({
  int renglones = 2,
  MedioBarra medio = MedioBarra.efectivo,
  String? numeros,
  String comprador = 'GOMEZ, CARLA',
  double descuento = 0,
}) {
  // Sin acentos: con la letra de fábrica van escapados y no se leen.
  final lista = [
    RenglonEntradas.lugar(
      nombre: 'Entrada de lugar adicional (50 %)',
      precioLista: 10000,
      descuentoPct: 50,
      cantidad: 8,
    ),
    for (var i = 1; i < renglones; i++)
      RenglonEntradas.suelta(
        nombre: i == 1 ? 'Entrada' : 'Entrada tanda $i',
        precioLista: 10000,
        descuentoPct: descuento,
        cantidad: 2,
      ),
  ];
  final total = lista.fold<double>(0, (s, r) => s + r.subtotal);
  final recargo = medio == MedioBarra.efectivo ? 0.0 : 500.0;
  final efectivo = switch (medio) {
    MedioBarra.efectivo => total,
    MedioBarra.mixto => 10000.0,
    _ => 0.0,
  };
  return VentaEntradas.nueva(
    cajaEntradasId: 'caja',
    eventoId: _fiesta,
    numero: 17,
    contratoAlumnoId: 'c0000000-0000-4000-8000-000000000001',
    compradorNombre: comprador,
    compradorDni: '30111222',
    renglones: lista,
    medio: medio,
    efectivo: efectivo,
    transferencia: total - efectivo + recargo,
    recibe: medio == MedioBarra.efectivo ? total + 5000 : null,
    recargo: recargo,
    recargoPct: recargo > 0 ? 5 : null,
    numeros: numeros,
    hechoPor: 'Romi',
    ahora: _ahora,
  );
}

DatosDelComprobante _datos(
  VentaEntradas v, {
  bool copia = false,
  AnulacionEntradas? anulacion,
  String fiesta = 'INSTITUTO SAN LORENZO',
}) =>
    DatosDelComprobante(
      venta: v,
      fiesta: fiesta,
      fechaFiesta: DateTime(2026, 12, 4),
      alumno: 'GOMEZ, LUCIA',
      mesa: '14 y 15',
      copia: copia,
      anulacion: anulacion,
    );

Future<Uint8List> _pdf(
  VentaEntradas v, {
  bool copia = false,
  AnulacionEntradas? anulacion,
  String fiesta = 'INSTITUTO SAN LORENZO',
}) =>
    ComprobanteEntradasPdf.armar(
      _datos(v, copia: copia, anulacion: anulacion, fiesta: fiesta),
    );

Set<String> _palabras(Uint8List bytes) =>
    {for (final p in palabrasDelPdf(bytes)) p.texto};

/// Todo lo que escribe, palabra por palabra y separado por un espacio.
String _texto(Uint8List bytes) => palabrasDelPdf(bytes).map((p) => p.texto).join(' ');

/// Nada se sale: ni de los costados del recibo (22 pt, como el de las cuotas)
/// ni de la hoja, que mide lo que mide lo escrito.
void _nadaSeSale(Uint8List bytes) {
  final ancho = PdfPageFormat.a4.width;
  const costado = ReciboDeEntradasPdf.costado;
  final alto = altoDeLaHoja(bytes);
  final palabras = palabrasDelPdf(bytes);
  expect(palabras, isNotEmpty);
  for (final p in palabras) {
    expect(p.x, greaterThanOrEqualTo(costado - 0.5),
        reason: '"${p.texto}" empieza antes del margen');
    expect(p.x + p.ancho, lessThanOrEqualTo(ancho - costado + 0.5),
        reason: '"${p.texto}" termina fuera de la hoja');
    expect(p.y, greaterThanOrEqualTo(0), reason: '"${p.texto}" se sale por abajo');
    expect(p.y, lessThanOrEqualTo(alto), reason: '"${p.texto}" se sale por arriba');
  }
}

void main() {
  // Para leer las letras de la app (Outfit) y el logo de los assets.
  TestWidgetsFlutterBinding.ensureInitialized();

  final media = ReciboDeEntradasPdf.mediaA4;

  test('la hoja es la del recibo de las cuotas: el ancho de una A4, el alto libre y '
      'un piso de media hoja', () {
    expect(ReciboDeEntradasPdf.formato.width, closeTo(595.28, 0.01));
    expect(ReciboDeEntradasPdf.formato.height, double.infinity);
    expect(media, closeTo(841.89 / 2, 0.01));
  });

  for (final n in [1, 6]) {
    test('con $n renglones entra justo en media hoja, y nada se sale', () async {
      final bytes = await _pdf(_venta(renglones: n, numeros: '1043-1050,1101-1102'));
      expect(paginasDelPdf(bytes), 1);
      expect(altoDeLaHoja(bytes), closeTo(media, 0.5));
      _nadaSeSale(bytes);
    });
  }

  // Lo que se imprime sale con Outfit, que mide distinto que la letra de
  // fábrica: lo común tiene que entrar en media hoja con la letra de verdad.
  test('con las letras de la app y el logo, una venta de 6 renglones, mixta, anulada '
      'y reimpresa, entra justo en media hoja', () async {
    final fuentes = (await PdfService.fuentesOutfit())!;
    final logo = await isotipoDeLosPapeles();
    expect(logo, isNotNull);
    final v = _venta(renglones: 6, medio: MedioBarra.mixto, numeros: '1043-1050,1101-1110');
    final anulacion = AnulacionEntradas.de(
      v,
      motivo: 'se equivoco de familia y la cargo a otra',
      devueltas: false,
      hechoPor: 'Jefe',
      ahora: _ahora.add(const Duration(days: 1)),
    );
    for (final d in [_datos(v), _datos(v, copia: true, anulacion: anulacion)]) {
      final bytes = await ComprobanteEntradasPdf.armar(d, fuentes: fuentes, logo: logo);
      expect(paginasDelPdf(bytes), 1);
      expect(altoDeLaHoja(bytes), closeTo(media, 0.5));
    }
  });

  test('con muchos renglones la hoja crece: nunca recorta ni pierde uno', () async {
    final bytes = await _pdf(_venta(renglones: 60, numeros: '1043-1050'));
    expect(paginasDelPdf(bytes), 1);
    expect(altoDeLaHoja(bytes), greaterThan(media + 1));
    final palabras = _palabras(bytes);
    // El último renglón, el total y el pie están.
    expect(palabras, contains('59'));
    expect(_texto(bytes), contains('Entrada tanda 59'));
    expect(palabras, containsAll(['TOTAL', 'RECIBO', 'Vendió:', 'Romi']));
    _nadaSeSale(bytes);
  });

  test('un comprador y una escuela de nombres largos bajan de renglón, no se salen',
      () async {
    final bytes = await _pdf(
      _venta(
        renglones: 6,
        comprador: 'FERNANDEZ DE LA FUENTE ALVARENGA, MARIA DE LOS ANGELES GUADALUPE',
      ),
      fiesta: 'ESCUELA DE EDUCACION TECNICA NUMERO UNO BRIGADIER GENERAL PEDRO FERRE '
          'PROMOCION 2026',
    );
    expect(paginasDelPdf(bytes), 1);
    expect(_palabras(bytes), containsAll(['GUADALUPE', 'PROMOCION']));
    _nadaSeSale(bytes);
  });

  test('tiene la forma del recibo: el dueño, RECIBO DE PAGO, Fecha, Recibí de, La suma '
      'de pesos, Concepto y TOTAL DE ESTE RECIBO con el medio de pago', () async {
    final bytes = await _pdf(_venta(numeros: '1043-1050,1101-1102'));
    final texto = _texto(bytes);
    for (final frase in [
      // El dueño, del mismo lugar que el recibo de las cuotas.
      EmisorDelRecibo.nombre,
      EmisorDelRecibo.cargo,
      EmisorDelRecibo.cuit,
      EmisorDelRecibo.condicion,
      'RECIBO DE PAGO',
      'N° 0017',
      'Fecha: 14/11/2026 11:32 hs',
      'Recibí de: GOMEZ, CARLA · DNI 30111222',
      'La suma de pesos: SESENTA MIL PESOS',
      'Concepto: Entradas · INSTITUTO SAN LORENZO · fiesta 04/12/2026',
      'Familia: GOMEZ, LUCIA · mesa 14 y 15',
      r'8 × Entrada de lugar adicional (50 %) · $ 5.000 c/u $ 40.000',
      r'2 × Entrada · $ 10.000 c/u $ 20.000',
      '10 entradas · Talonario: 1043 al 1050 y 1101 al 1102',
      r'TOTAL DE ESTE RECIBO $ 60.000',
      'Medio de pago: Efectivo',
      r'Entregó $ 65.000 · Vuelto $ 5.000',
      'Vendió: Romi',
    ]) {
      expect(texto, contains(frase), reason: 'falta "$frase"');
    }
    // El total va una sola vez, en su recuadro, como en el recibo de las cuotas.
    expect('TOTAL'.allMatches(texto), hasLength(1));
  });

  test('dice lo que la venta tiene guardado, sin pulseras', () async {
    final v = _venta(numeros: '1043-1050,1101-1102');
    final palabras = _palabras(await _pdf(v));
    for (final esperada in [
      'INSTITUTO', 'LORENZO', '04/12/2026',
      'RECIBO', 'PAGO', '0017',
      '14/11/2026', '11:32', 'Romi',
      'GOMEZ,', 'CARLA', '30111222', 'LUCIA', 'mesa', '15',
      'adicional', 'TOTAL', 'Efectivo', 'Entradas', '10', 'Talonario:',
      '1043', '1050', '1101', '1102',
    ]) {
      expect(palabras, contains(esperada), reason: 'falta "$esperada"');
    }
    // La pulsera no se vende (20-nov-2026): el comprobante no habla de pulseras.
    for (final p in palabras) {
      expect(p.toLowerCase(), isNot(contains('pulsera')), reason: 'dice "$p"');
    }
    expect(v.cantidad, 10);
    expect(palabras, isNot(contains('COPIA')));
    expect(palabras, isNot(contains('ANULADA')));
  });

  test('el total es lo cobrado, con el recargo, y dice cómo pagó', () async {
    final v = _venta(medio: MedioBarra.mixto);
    expect(v.cobrado, 60500);
    expect(ComprobanteEntradasPdf.comoPago(v),
        r'Mixto · efectivo $ 10.000 · transferencia $ 50.500');
    expect(ComprobanteEntradasPdf.medioDePago(v),
        r'Medio de pago: Mixto (efectivo $ 10.000 · transferencia $ 50.500)');
    final bytes = await _pdf(v);
    final palabras = _palabras(bytes);
    expect(palabras, contains('60.500'));
    expect(palabras, contains('Recargo'));
    expect(palabras, contains('Mixto'));
    final texto = _texto(bytes);
    expect(texto, contains('La suma de pesos: SESENTA MIL QUINIENTOS PESOS'));
    expect(texto, contains(r'Recargo por transferencia (5 %) $ 500'));
    expect(texto, contains(r'TOTAL DE ESTE RECIBO $ 60.500'));
    expect(texto, contains(r'Medio de pago: Mixto (efectivo $ 10.000 · transferencia $ 50.500)'));
    // Sin efectivo entregado no hay vuelto.
    expect(palabras, isNot(contains('Vuelto')));
    expect(ComprobanteEntradasPdf.comoPago(_venta()), 'Efectivo');
    expect(ComprobanteEntradasPdf.medioDePago(_venta()), 'Medio de pago: Efectivo');
    expect(
      ComprobanteEntradasPdf.comoPago(_venta(medio: MedioBarra.transferencia)),
      'Transferencia',
    );
  });

  test('cada renglón dice cuántas, cada una y el descuento a mano si lo hubo', () {
    final v = _venta(descuento: 10);
    expect(ComprobanteEntradasPdf.renglon(v.renglones.first),
        r'8 × Entrada de lugar adicional (50 %) · $ 5.000 c/u',
        reason: 'el 50 % de los lugares ya está en el nombre: no es un descuento a mano');
    expect(ComprobanteEntradasPdf.renglon(v.renglones.last),
        r'2 × Entrada · $ 9.000 c/u · descuento 10 %');
  });

  test('sin números del talonario lo dice, sin inventar ninguno', () async {
    final v = _venta();
    expect(ComprobanteEntradasPdf.talonario(v), isNull);
    final bytes = await _pdf(v);
    final palabras = _palabras(bytes);
    expect(palabras, contains('talonario'));
    expect(palabras, isNot(contains('Talonario:')));
    expect(_texto(bytes), contains('10 entradas · Sin números del talonario anotados'));
  });

  test('reimpreso dice COPIA; anulado, ANULADA con el motivo, y sigue en media hoja',
      () async {
    final v = _venta();
    expect(_palabras(await _pdf(v, copia: true)), contains('COPIA'));

    final anulacion = AnulacionEntradas.de(
      v,
      motivo: 'se equivoco de familia',
      devueltas: false,
      hechoPor: 'Jefe',
      ahora: _ahora.add(const Duration(days: 1)),
    );
    final bytes = await _pdf(v, anulacion: anulacion);
    expect(paginasDelPdf(bytes), 1);
    expect(altoDeLaHoja(bytes), closeTo(media, 0.5));
    final palabras = _palabras(bytes);
    expect(palabras, contains('ANULADA'));
    expect(palabras, contains('equivoco'));
    expect(palabras, contains('NO'));
    expect(palabras, contains('15/11/2026'));
    expect(_texto(bytes), contains('por Jefe · se equivoco de familia · NO devolvieron las '
        'entradas'));
  });

  test('el archivo se llama por su número y quién compró', () {
    expect(
      ComprobanteEntradasPdf.nombreDelArchivo(DatosDelComprobante(
        venta: _venta(),
        fiesta: 'X',
      )),
      'Entradas_0017_GOMEZ_CARLA.pdf',
    );
  });
}
