// El comprobante de una venta de entradas (sección 7.4 del spec del 13-nov):
// entra en media hoja A4, con 1 y con 6 renglones, sin que nada se salga, y
// dice lo que la venta tiene guardado.
//
// Se arma con la letra de fábrica del paquete: con las de la app el texto va en
// códigos de glifo y no se puede leer. En un PDF el texto sale palabra por
// palabra: se busca cada palabra, no la frase.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/comprobante_entradas_pdf.dart';

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

Future<Uint8List> _pdf(
  VentaEntradas v, {
  bool copia = false,
  AnulacionEntradas? anulacion,
  String fiesta = 'INSTITUTO SAN LORENZO',
}) =>
    ComprobanteEntradasPdf.armar(DatosDelComprobante(
      venta: v,
      fiesta: fiesta,
      fechaFiesta: DateTime(2026, 12, 4),
      alumno: 'GOMEZ, LUCIA',
      mesa: '14 y 15',
      copia: copia,
      anulacion: anulacion,
    ));

Set<String> _palabras(Uint8List bytes) =>
    {for (final p in palabrasDelPdf(bytes)) p.texto};

void main() {
  final hoja = ComprobanteEntradasPdf.hoja;

  test('la hoja es media A4', () {
    expect(hoja.width, closeTo(595.28, 0.01));
    expect(hoja.height, closeTo(841.89 / 2, 0.01));
  });

  for (final n in [1, 6]) {
    test('con $n renglones entra en una sola media hoja, y nada se sale', () async {
      final bytes = await _pdf(_venta(renglones: n, numeros: '1043-1050,1101-1102'));
      expect(paginasDelPdf(bytes), 1);
      final palabras = palabrasDelPdf(bytes);
      expect(palabras, isNotEmpty);
      for (final p in palabras) {
        expect(p.x, greaterThanOrEqualTo(hoja.marginLeft - 0.5),
            reason: '"${p.texto}" empieza antes del margen');
        expect(p.x + p.ancho, lessThanOrEqualTo(hoja.width - hoja.marginRight + 0.5),
            reason: '"${p.texto}" termina fuera de la hoja');
        expect(p.y, greaterThanOrEqualTo(hoja.marginBottom - 0.5),
            reason: '"${p.texto}" queda debajo del margen');
        expect(p.y, lessThanOrEqualTo(hoja.height - hoja.marginTop + 0.5),
            reason: '"${p.texto}" queda arriba del margen');
      }
    });
  }

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
    for (final p in palabrasDelPdf(bytes)) {
      expect(p.x + p.ancho, lessThanOrEqualTo(hoja.width - hoja.marginRight + 0.5),
          reason: '"${p.texto}" termina fuera de la hoja');
      expect(p.y, greaterThanOrEqualTo(hoja.marginBottom - 0.5),
          reason: '"${p.texto}" queda debajo del margen');
    }
  });

  test('dice lo que la venta tiene guardado', () async {
    final v = _venta(numeros: '1043-1050,1101-1102');
    final palabras = _palabras(await _pdf(v));
    for (final esperada in [
      'INSTITUTO', 'LORENZO', '04/12/2026',
      'COMPROBANTE', 'ENTRADAS', '0017',
      '14/11/2026', '11:32', 'Romi',
      'GOMEZ,', 'CARLA', '30111222', 'LUCIA', 'mesa', '15',
      'adicional', 'TOTAL', 'Efectivo', 'Pulseras', '10', 'Talonario',
      '1043', '1050', '1101', '1102',
    ]) {
      expect(palabras, contains(esperada), reason: 'falta "$esperada"');
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
    final palabras = _palabras(await _pdf(v));
    expect(palabras, contains('60.500'));
    expect(palabras, contains('Recargo'));
    expect(palabras, contains('Mixto'));
    expect(ComprobanteEntradasPdf.comoPago(_venta()), 'Efectivo');
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
    final palabras = _palabras(await _pdf(v));
    expect(palabras, contains('talonario'));
    expect(palabras, isNot(contains('Talonario')));
  });

  test('reimpreso dice COPIA; anulado, ANULADA con el motivo', () async {
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
    final palabras = _palabras(bytes);
    expect(palabras, contains('ANULADA'));
    expect(palabras, contains('equivoco'));
    expect(palabras, contains('NO'));
    expect(palabras, contains('15/11/2026'));
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
