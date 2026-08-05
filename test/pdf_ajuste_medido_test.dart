import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:arguello_events/features/common/services/ajuste_pdf.dart';

/// El resumen a abonar usaba `pw.Page` con A4 fijo: lo que no entraba en los
/// 842 pt se caía del MediaBox **sin error ni aviso**, y como el total va al
/// final del layout, el papel podía salir con el detalle y sin el total.
///
/// La solución no es dejar crecer la hoja sino **compactar hasta que entre**:
/// se mide cuánto ocupa de verdad y se sube un escalón solo si hace falta.
/// Estos tests fijan las dos piezas: que se pueda medir, y que la escalera
/// efectivamente meta contenido pesado en media hoja.
void main() {
  /// Mismo mecanismo que usa `PdfService._medirAlto`: con alto libre, el motor
  /// recorta la página al alto real del contenido, así que la altura resultante
  /// **es** la medida.
  Future<double> medirAlto(pw.Widget contenido) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(PdfPageFormat.a4.width, double.infinity),
        margin: const pw.EdgeInsets.all(0),
        build: (_) => contenido,
      ),
    );
    await doc.save();
    return doc.document.pdfPageList.pages.first.pageFormat.height;
  }

  /// Papel de prueba equivalente en estructura al resumen a abonar.
  pw.Widget cuerpo(AjustePdf a, int lineas) => pw.Padding(
    padding: pw.EdgeInsets.all(a.sp(22)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lineas; i++)
          pw.Padding(
            padding: pw.EdgeInsets.only(bottom: a.sp(4)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Cuota Base ($i/$lineas)',
                  style: pw.TextStyle(fontSize: a.fs(9)),
                ),
                if (a.subtextos)
                  pw.Text(
                    'venció el 31/05/2026 · nom. \$10.000',
                    style: pw.TextStyle(fontSize: a.fs(7, piso: 6.5)),
                  ),
              ],
            ),
          ),
        pw.SizedBox(height: a.sp(10)),
        pw.Text('TOTAL A PAGAR AHORA', style: pw.TextStyle(fontSize: a.fs(12))),
      ],
    ),
  );

  final mediaA4 = PdfPageFormat.a4.height / 2;

  /// Réplica de `PdfService._ajustarParaEntrar`.
  Future<AjustePdf> ajustar(int lineas, {double? objetivo}) async {
    for (final a in AjustePdf.escalera) {
      if (await medirAlto(cuerpo(a, lineas)) <= (objetivo ?? mediaA4) + 0.5) {
        return a;
      }
    }
    return AjustePdf.escalera.last;
  }

  test('la altura del contenido se puede medir', () async {
    final corto = await medirAlto(cuerpo(AjustePdf.intacto, 3));
    final largo = await medirAlto(cuerpo(AjustePdf.intacto, 30));
    expect(largo, greaterThan(corto));
  });

  test('un cobro común no necesita compactarse: sale intacto', () async {
    final a = await ajustar(4);
    expect(
      a.esIntacto,
      isTrue,
      reason: 'el papel de todos los días tiene que salir igual que siempre',
    );
  });

  test('un cobro cargado se compacta lo justo, no al máximo', () async {
    final a = await ajustar(16);
    expect(a.esIntacto, isFalse, reason: 'algo tuvo que ceder');
    expect(
      a.nivel,
      lessThan(AjustePdf.escalera.last.nivel),
      reason: 'no hace falta llegar al escalón más agresivo',
    );
  });

  test('a más contenido, no menos compactación', () async {
    final liviano = await ajustar(14);
    final pesado = await ajustar(26);
    expect(pesado.nivel, greaterThanOrEqualTo(liviano.nivel));
  });

  test('9 cuotas con subtextos entran en media hoja A4', () async {
    final a = await ajustar(9);
    final alto = await medirAlto(cuerpo(a, 9));
    expect(
      alto,
      lessThanOrEqualTo(mediaA4 + 0.5),
      reason: 'es el caso que motivó el cambio: no puede desbordar',
    );
  });

  test('la escalera gana altura de verdad en cada escalón', () async {
    double? anterior;
    for (final a in AjustePdf.escalera) {
      final alto = await medirAlto(cuerpo(a, 30));
      if (anterior != null) {
        expect(
          alto,
          lessThanOrEqualTo(anterior),
          reason: 'el nivel ${a.nivel} tiene que ocupar igual o menos',
        );
      }
      anterior = alto;
    }
  });

  test('el nivel más compacto achica de forma significativa', () async {
    final intacto = await medirAlto(cuerpo(AjustePdf.intacto, 30));
    final maximo = await medirAlto(cuerpo(AjustePdf.escalera.last, 30));
    expect(
      maximo,
      lessThan(intacto * 0.6),
      reason: 'la escalera completa tiene que ganar al menos un 40%',
    );
  });
}
