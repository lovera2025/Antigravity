import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../eventos/services/caja_de_entregas.dart';
import 'planilla_tema.dart';

/// El papel de la caja de entregas (IMPRIMIR en Cierre de caja → ENTRADAS,
/// 20-nov-2026): **lo que se entregó sin cargo, por quién**, en A4 parado. Arriba
/// la fiesta y cuántas pulseras y generales se dieron de las que tienen que
/// llegar; después, por cada persona, una tabla con cada entrega (cuándo,
/// familia, qué, cuántas, quién retiró, números), con las anuladas marcadas.
/// **Sin plata**: lo sin cargo no se cobra.
///
/// Las tablas van como hijas directas del `pw.MultiPage`: así se parten entre
/// hojas (ver la trampa de los PDF en CLAUDE.md).
class EntregasSinCargoPdf {
  EntregasSinCargoPdf._();

  static const columnas = [
    'Cuándo',
    'Familia',
    'Qué',
    'Cant.',
    'Quién retiró',
    'Números',
  ];

  /// [soloDe]: una sola persona (la elegida en la pantalla); null, todas.
  static Future<Uint8List> construir({
    required CajaDeEntregas caja,
    required String fiesta,
    DateTime? fechaFiesta,
    String? soloDe,
    pw.Font? regular,
    pw.Font? negrita,
    DateTime? generada,
  }) {
    const tema = PlanillaTema();
    final theme = regular != null && negrita != null
        ? pw.ThemeData.withFont(base: regular, bold: negrita)
        : null;
    final r = caja.resumen;
    final personas = [
      for (final p in caja.personas)
        if (soloDe == null || p.quien == soloDe) p,
    ];
    final cuando = ArTime.formatFechaHora(generada ?? ArTime.nowAr());

    pw.Widget celda(String texto, {bool negrita = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(
            texto,
            style: pw.TextStyle(
              fontSize: PlanillaTema.cuerpo,
              fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? tema.texto,
            ),
          ),
        );

    pw.Widget tabla(PersonaDeLaCaja p) => pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: tema.linea, width: 0.5),
            bottom: pw.BorderSide(color: tema.linea, width: 0.5),
          ),
          columnWidths: const {
            0: pw.FixedColumnWidth(62),
            1: pw.FlexColumnWidth(2.2),
            2: pw.FlexColumnWidth(1.4),
            3: pw.FixedColumnWidth(34),
            4: pw.FlexColumnWidth(3),
            5: pw.FlexColumnWidth(1.6),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: tema.fondoEncabezadoTabla),
              children: [for (final c in columnas) celda(c, negrita: true)],
            ),
            for (final e in p.entregas)
              pw.TableRow(children: [
                celda(ArTime.formatFechaHora(e.cuando).replaceFirst(RegExp(r'/\d{4}'), '')),
                celda(e.familia, negrita: true),
                celda(e.deLasOchoJuntas ? '${e.que} (las 8 juntas)' : e.que),
                celda(e.cantidad),
                e.anulada
                    ? celda(
                        'ANULADA'
                        '${e.anuladaAt == null ? '' : ' el ${ArTime.formatFechaHora(e.anuladaAt!)}'}'
                        '${(e.anuladaPor ?? '').isEmpty ? '' : ' por ${e.anuladaPor}'}'
                        '${(e.motivoAnulacion ?? '').isEmpty ? '' : ': ${e.motivoAnulacion}'}',
                        color: tema.textoSuave,
                      )
                    : celda(e.quienRetiro),
                celda(e.numeros, color: e.anulada ? tema.textoSuave : null),
              ]),
          ],
        );

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(PlanillaTema.margen),
        maxPages: 200,
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Entregas sin cargo · $fiesta'
              '${fechaFiesta == null ? '' : ' · ${ArTime.formatFechaCorta(fechaFiesta)}'}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: tema.texto),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Impreso el $cuando · Pulseras VIP ${r.pulserasEntregadas} de ${r.pulserasTotales}'
              ' · Generales ${r.generalesEntregadas} de ${r.generalesTotales}'
              ' · Familias con todo ${r.familiasConTodo} de ${r.familias}'
              ' · Anuladas ${caja.anuladas}',
              style: pw.TextStyle(fontSize: PlanillaTema.secundario, color: tema.textoSuave),
            ),
            if (soloDe != null)
              pw.Text(
                'Solo lo que entregó $soloDe.',
                style: pw.TextStyle(fontSize: PlanillaTema.secundario, color: tema.textoSuave),
              ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Hoja ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: PlanillaTema.secundario, color: tema.textoSuave),
          ),
        ),
        build: (_) => [
          if (personas.isEmpty)
            pw.Text(
              'Todavía no se entregó nada sin cargo en esta fiesta.',
              style: pw.TextStyle(fontSize: PlanillaTema.cuerpo, color: tema.textoSuave),
            ),
          for (final p in personas) ...[
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
              child: pw.Text(
                '${p.quien} · ${p.pulseras == 1 ? '1 pulsera' : '${p.pulseras} pulseras'}'
                ' · ${p.generales == 1 ? '1 general' : '${p.generales} generales'}'
                ' · ${p.familias == 1 ? '1 familia' : '${p.familias} familias'}'
                '${p.anuladas == 0 ? '' : ' · ${p.anuladas == 1 ? '1 anulada' : '${p.anuladas} anuladas'}'}',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: tema.acento,
                ),
              ),
            ),
            tabla(p),
          ],
        ],
      ),
    );
    return doc.save();
  }
}
