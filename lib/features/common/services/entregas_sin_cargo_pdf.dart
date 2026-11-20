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
/// familia, qué, cuántas, quién retiró, números), con lo que no cuenta marcado
/// con su motivo: lo mismo que la pantalla (`EntregaDeLaCaja.estado`). Al final,
/// las anulaciones de una entrega anterior. **Sin plata**: lo sin cargo no se
/// cobra.
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
  /// [generada]: **un instante** (UTC o local, da igual): el papel lo escribe
  /// en la hora de Argentina. Sin él, ahora.
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
    // `formatFechaHora` ya pasa a la hora de Argentina: recibe el instante.
    // Con `nowAr()` salía 3 horas antes (revisión del 20-nov-2026).
    final cuando = ArTime.formatFechaHora(generada ?? ArTime.nowUtc());
    String sinAnio(DateTime d) =>
        ArTime.formatFechaHora(d).replaceFirst(RegExp(r'/\d{4}'), '');

    pw.TextStyle estilo({bool negrita = false, PdfColor? color, bool tachado = false}) =>
        pw.TextStyle(
          fontSize: PlanillaTema.cuerpo,
          fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? tema.texto,
          decoration: tachado ? pw.TextDecoration.lineThrough : null,
        );

    pw.Widget celda(String texto, {bool negrita = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(texto, style: estilo(negrita: negrita, color: color)),
        );

    PdfColor colorDe(TonoDeLaLinea t) => switch (t) {
          TonoDeLaLinea.normal => tema.texto,
          TonoDeLaLinea.apagado => tema.textoSuave,
          TonoDeLaLinea.anulada => tema.rojo,
          TonoDeLaLinea.noCuenta => tema.naranja,
        };

    // Qué y cuántas, con la parte que no cuenta tachada.
    pw.Widget que(EntregaDeLaCaja e) {
      final pw.InlineSpan span;
      if (!e.partida) {
        final texto = e.deLasOchoJuntas ? '${e.que} (las 8 juntas)' : e.que;
        span = pw.TextSpan(
          text: texto,
          style: estilo(tachado: !e.vigente, color: e.vigente ? null : tema.textoSuave),
        );
      } else {
        span = pw.TextSpan(children: [
          pw.TextSpan(text: 'Pulseras', style: estilo(tachado: !e.pulserasVigentes)),
          pw.TextSpan(text: ' y ', style: estilo()),
          pw.TextSpan(text: 'generales', style: estilo(tachado: !e.generalesVigentes)),
          pw.TextSpan(text: ' (las 8 juntas)', style: estilo()),
        ]);
      }
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.RichText(text: span),
      );
    }

    pw.Widget cantidad(EntregaDeLaCaja e) {
      final pw.InlineSpan span = !e.partida
          ? pw.TextSpan(
              text: e.cantidad,
              style: estilo(tachado: !e.vigente, color: e.vigente ? null : tema.textoSuave),
            )
          : pw.TextSpan(children: [
              pw.TextSpan(text: '${e.pulseras}', style: estilo(tachado: !e.pulserasVigentes)),
              pw.TextSpan(text: ' + ', style: estilo()),
              pw.TextSpan(text: '${e.generales}', style: estilo(tachado: !e.generalesVigentes)),
            ]);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.RichText(text: span),
      );
    }

    // Quién retiró y por qué no cuenta: un renglón cada cosa. `AltoLibre`: en
    // una celda de tabla, una columna de renglones puede perder el último.
    pw.Widget retiro(EntregaDeLaCaja e) => AltoLibre(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final l in e.estado(ArTime.formatFechaHora))
                  pw.Text(
                    l.texto,
                    style: estilo(
                      color: colorDe(l.tono),
                      negrita: l.tono == TonoDeLaLinea.anulada ||
                          l.tono == TonoDeLaLinea.noCuenta,
                    ),
                  ),
              ],
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
                celda(sinAnio(e.cuando)),
                celda(e.deBaja ? '${e.familia} (hoy de baja)' : e.familia, negrita: true),
                que(e),
                cantidad(e),
                retiro(e),
                celda(e.numeros, color: e.numerosApagados ? tema.textoSuave : null),
              ]),
          ],
        );

    final bajas = soloDe == null ? caja.textoDeLasBajas : null;
    final anteriores = soloDe == null ? caja.anulacionesAnteriores : const <AnulacionAnterior>[];

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
            if (bajas != null)
              pw.Text(
                bajas,
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
                '${p.anuladas == 0 ? '' : ' · ${p.anuladas == 1 ? '1 anulada' : '${p.anuladas} anuladas'}'}'
                '${p.sinEfecto == 0 ? '' : ' · ${p.sinEfecto == 1 ? '1 que no cuenta' : '${p.sinEfecto} que no cuentan'}'}',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: tema.acento,
                ),
              ),
            ),
            tabla(p),
          ],
          if (anteriores.isNotEmpty) ...[
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 12, bottom: 2),
              child: pw.Text(
                'Anulaciones de una entrega anterior',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: tema.acento),
              ),
            ),
            pw.Text(
              'Cada una anuló una entrega que ya no está en la lista: quedó reescrita al '
              'volver a entregar, o ya estaba anulada.',
              style: pw.TextStyle(fontSize: PlanillaTema.secundario, color: tema.textoSuave),
            ),
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: tema.linea, width: 0.5),
                bottom: pw.BorderSide(color: tema.linea, width: 0.5),
              ),
              columnWidths: const {
                0: pw.FixedColumnWidth(62),
                1: pw.FlexColumnWidth(2.2),
                2: pw.FlexColumnWidth(5),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: tema.fondoEncabezadoTabla),
                  children: [
                    celda('Cuándo', negrita: true),
                    celda('Familia', negrita: true),
                    celda('Qué pasó', negrita: true),
                  ],
                ),
                for (final x in anteriores)
                  pw.TableRow(children: [
                    celda(sinAnio(x.cuando)),
                    celda(x.deBaja ? '${x.familia} (hoy de baja)' : x.familia, negrita: true),
                    celda(x.texto, color: tema.rojo),
                  ]),
              ],
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }
}
