import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../barra/cuentas/pesos.dart';
import '../cuentas/historial_de_entradas.dart';
import '../datos/entradas_repositorio.dart';

/// Lo que lleva el historial de ventas impreso.
class DatosDelHistorial {
  final HistorialDeEntradas historial;
  final String fiesta;
  final DateTime? fechaFiesta;

  /// "Todas las cajas", o "La caja de Carla".
  final String alcance;
  final DateTime emitido;

  /// Con las sumas de plata (efectivo, transferencia, total). **Quien vende
  /// no las ve** (revisión del 14-nov): con el total de su caja abierta sabría
  /// cuánto efectivo tiene que haber, y el cierre se cuenta a ciegas. El
  /// monto de cada venta sí va, como en la barra.
  final bool conPlata;

  /// La familia de cada venta, por el id del alumno: "PÉREZ, JUAN m.12-13".
  final Map<String, String> familias;

  /// Las hojas que salen, de 1 a [HistorialEntradasPdf.hojas] (pedido del
  /// usuario, 15-nov: con 1.000 entradas, imprimir por tandas). Null: todas.
  final int? desdeHoja;
  final int? hastaHoja;

  const DatosDelHistorial({
    required this.historial,
    required this.fiesta,
    this.fechaFiesta,
    required this.alcance,
    required this.emitido,
    this.conPlata = true,
    this.familias = const {},
    this.desdeHoja,
    this.hastaHoja,
  });

  /// El mismo historial, pero solo las hojas de [desde] a [hasta].
  DatosDelHistorial soloLasHojas(int desde, int hasta) => DatosDelHistorial(
        historial: historial,
        fiesta: fiesta,
        fechaFiesta: fechaFiesta,
        alcance: alcance,
        emitido: emitido,
        conPlata: conPlata,
        familias: familias,
        desdeHoja: desde,
        hastaHoja: hasta,
      );
}

/// Una venta en el papel: su renglón y, solo si hay algo que explicar, un
/// segundo renglón más chico ([abajo]).
class FilaDelHistorial {
  final VentaDelHistorial venta;

  /// La familia en el mismo renglón que el comprador; null si no hay, o si es
  /// largo y va abajo.
  final String? familia;

  /// El segundo renglón: la familia (si no entró arriba), el talonario largo,
  /// cómo se pagó un mixto, el recargo, el descuento a mano o la anulación.
  final String? abajo;

  /// Cuántos renglones ocupa [abajo] (0, 1 o 2).
  final int renglonesAbajo;

  const FilaDelHistorial({
    required this.venta,
    this.familia,
    this.abajo,
    this.renglonesAbajo = 0,
  });

  double get alto =>
      HistorialEntradasPdf.altoVenta + renglonesAbajo * HistorialEntradasPdf.altoAbajo;
}

/// El historial de ventas de entradas de una fiesta, en A4 parada (la forma C
/// que eligió el usuario el 15-nov): **un renglón por venta**, con quién
/// compró y su familia, qué entradas, el talonario, el total, cómo pagó,
/// quién vendió y la tilde de "Pago verificado"; **y un segundo renglón solo
/// cuando hay algo que explicar** (un mixto, un recargo, un descuento a mano,
/// una anulación). Los totales van al final, en la última hoja.
///
/// **Las hojas se arman acá, con medidas fijas** (cada renglón mide lo mismo
/// y un texto que no entra se corta en su renglón): así se sabe de antemano
/// qué ventas van en cada hoja, y se puede imprimir solo un tramo ("de la hoja
/// 11 a la 20") con la misma numeración que el papel entero.
class HistorialEntradasPdf {
  HistorialEntradasPdf._();

  static PdfPageFormat get hoja => PdfPageFormat.a4.copyWith(
        marginLeft: 28,
        marginRight: 28,
        marginTop: 26,
        marginBottom: 26,
      );

  // ── Las medidas (en puntos) ───────────────────────────────────────────────

  static const altoVenta = 13.5;
  static const altoAbajo = 9.5;
  static const _altoEncabezado = 44.0;
  static const _altoEncabezadoCorto = 18.0;
  static const _altoCabezaDeTabla = 14.0;
  static const _altoPie = 16.0;
  static const _altoRenglonTotal = 12.5;
  static const _seguridad = 8.0;

  static const _letraVenta = 7.8;
  static const _letraAbajo = 7.0;

  /// El ancho de cada columna, menos el del comprador (lo que queda).
  static const _anchos = (
    numero: 24.0,
    cuando: 46.0,
    entradas: 80.0,
    talonario: 58.0,
    total: 48.0,
    pago: 38.0,
    vendio: 36.0,
    verif: 24.0,
  );

  /// Hasta cuántas letras entran el comprador y su familia en un renglón (con
  /// un poco de margen); más largo, la familia baja al segundo renglón.
  static const _letrasArriba = 44;

  /// Hasta cuántas letras entran en un segundo renglón; más, ocupa dos.
  static const _letrasAbajo = 118;

  /// Hasta cuántas letras entra el talonario en su columna; más, va abajo.
  static const _letrasTalonario = 13;

  static double get _alto => hoja.height - hoja.marginTop - hoja.marginBottom;

  static String _dia(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  /// "20/11 21:40", en hora de Argentina: el año ya está arriba (la fiesta y
  /// cuándo se imprimió), y con el año y el "hs" la columna partía cada fecha en
  /// dos renglones.
  static String cuandoEnLaTabla(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final ar = ArTime.toAr(t);
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(ar.day)}/${dos(ar.month)} ${dos(ar.hour)}:${dos(ar.minute)}';
  }

  static String _medio(VentaEntradas v) => switch (v.medio) {
        MedioBarra.efectivo => 'Efectivo',
        MedioBarra.transferencia => 'Transf.',
        MedioBarra.mixto => 'Mixto',
        MedioBarra.otro => '—',
      };

  static String _porcentaje(double p) =>
      p == p.roundToDouble() ? '${p.toInt()} %' : '${p.toStringAsFixed(1)} %';

  /// Qué entradas llevó, corto: "2 anticip.", "3 lugar 50 %", "1 anticip. + 2
  /// lugar". El porcentaje del lugar es **lo que paga** del valor, como en el
  /// comprobante.
  static String entradasCorto(VentaEntradas v) {
    final partes = <String>[];
    final soloUno = v.renglones.length == 1;
    for (final r in v.renglones) {
      final n = r.cantidad;
      switch (r.tipo) {
        case TipoRenglonEntradas.suelta:
          final anticipada = r.nombre.toLowerCase().contains('anticipada');
          partes.add(anticipada
              ? '$n anticip.'
              : '$n ${n == 1 ? 'entrada' : 'entradas'}');
        case TipoRenglonEntradas.lugar:
          partes.add(soloUno
              ? '$n lugar ${_porcentaje(100 - r.descuentoPct)}'
              : '$n lugar');
        case TipoRenglonEntradas.otro:
          partes.add('$n ${n == 1 ? 'otra' : 'otras'}');
      }
    }
    return partes.join(' + ');
  }

  /// Los números del talonario, para leer: "1043-1058, 1101-1108".
  static String talonario(VentaEntradas v) =>
      (v.numeros ?? '').split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).join(', ');

  /// El segundo renglón de una venta, sin la familia: lo que no entra en las
  /// columnas. Vacío si no hay nada que explicar.
  static List<String> detalleAbajo(VentaDelHistorial v) {
    final venta = v.venta;
    final a = v.anulacion;
    if (a != null) {
      final quien = (a.hechoPor ?? '').trim();
      return [
        'ANULADA${quien.isEmpty ? '' : ' por $quien'} ${cuandoEnLaTabla(a.createdAt)}',
        a.motivo,
        a.devueltas ? 'devolvieron las entradas y pulseras' : 'NO devolvieron las entradas',
      ];
    }
    final partes = <String>[];
    if (venta.medio == MedioBarra.mixto) {
      partes.add('efectivo ${pesos(venta.efectivo)} + transf. ${pesos(venta.transferencia)}');
    }
    if (venta.recargo > 0.005) {
      partes.add(
        'recargo por transferencia ${pesos(venta.recargo)}'
        '${venta.recargoPct == null ? '' : ' (${_porcentaje(venta.recargoPct!)})'}',
      );
    }
    if (venta.descuento > 0.005) {
      final pcts = {
        for (final r in venta.renglones)
          if (r.tipo == TipoRenglonEntradas.suelta && r.descuentoPct > 0) r.descuentoPct,
      };
      partes.add(
        'desc. a mano${pcts.length == 1 ? ' ${_porcentaje(pcts.first)}' : ''} '
        '(${pesos(venta.descuento)})',
      );
    }
    return partes;
  }

  /// Cómo queda cada venta en el papel (sin las hojas todavía).
  static List<FilaDelHistorial> filas(DatosDelHistorial d) {
    final out = <FilaDelHistorial>[];
    // En el papel, en el orden en que se vendieron.
    for (final v in d.historial.ventas.reversed) {
      final venta = v.venta;
      final id = venta.contratoAlumnoId;
      final fam = id == null ? null : d.familias[id];
      final arriba = fam == null
          ? null
          : (venta.compradorNombre.length + fam.length + 8 <= _letrasArriba ? fam : null);
      final tal = talonario(venta);
      final abajo = [
        if (fam != null && arriba == null) 'fam. $fam',
        if (tal.length > _letrasTalonario) 'talonario $tal',
        ...detalleAbajo(v),
      ];
      final texto = abajo.join(' · ');
      out.add(FilaDelHistorial(
        venta: v,
        familia: arriba,
        abajo: texto.isEmpty ? null : texto,
        renglonesAbajo: texto.isEmpty ? 0 : (texto.length > _letrasAbajo ? 2 : 1),
      ));
    }
    return out;
  }

  /// Los renglones de los totales del final (cuántos, para medirlos).
  static int _renglonesDeTotales(DatosDelHistorial d) {
    final t = d.historial.totales;
    return 1 +
        (d.conPlata
            ? 3 + (t.recargos > 0 ? 1 : 0) + (t.descuentos > 0 ? 1 : 0)
            : 0) +
        1 +
        (t.anuladas > 0 ? 1 : 0) +
        1 +
        d.historial.repetidos.length * 2;
  }

  /// Qué ventas van en cada hoja. **La última hoja lleva los totales**; si no
  /// entran después de la última venta, van solos en una hoja más.
  static List<List<FilaDelHistorial>> paginar(DatosDelHistorial d) {
    final todas = filas(d);
    final disponible = _alto - _altoPie - _seguridad;
    final hojas = <List<FilaDelHistorial>>[];
    var actual = <FilaDelHistorial>[];
    var usado = _altoEncabezado + _altoCabezaDeTabla;
    for (final f in todas) {
      if (actual.isNotEmpty && usado + f.alto > disponible) {
        hojas.add(actual);
        actual = [];
        usado = _altoEncabezadoCorto + _altoCabezaDeTabla;
      }
      actual.add(f);
      usado += f.alto;
    }
    final totales = 14 + _renglonesDeTotales(d) * _altoRenglonTotal;
    if (actual.isNotEmpty && usado + totales > disponible) {
      hojas.add(actual);
      actual = [];
    }
    hojas.add(actual);
    return hojas;
  }

  /// Cuántas hojas tiene el historial entero.
  static int hojas(DatosDelHistorial d) => paginar(d).length;

  /// La casilla de "Pago verificado": dibujada, no escrita (la letra de la app
  /// no trae el signo de la tilde).
  static pw.Widget _tilde(bool si) => pw.Container(
        width: 8.5,
        height: 8.5,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.8),
        ),
        child: !si
            ? null
            : pw.CustomPaint(
                size: const PdfPoint(8.5, 8.5),
                painter: (canvas, size) {
                  canvas
                    ..setStrokeColor(PdfColors.black)
                    ..setLineWidth(1.2)
                    ..moveTo(1.7, 4.4)
                    ..lineTo(3.6, 2.1)
                    ..lineTo(7.0, 6.8)
                    ..strokePath();
                },
              ),
      );

  static Future<Uint8List> armar(
    DatosDelHistorial d, {
    (pw.Font, pw.Font)? fuentes,
    pw.ImageProvider? logo,
  }) async {
    final h = d.historial;
    final t = h.totales;
    final doc = pw.Document(
      theme: fuentes == null
          ? null
          : pw.ThemeData.withFont(base: fuentes.$1, bold: fuentes.$2),
    );
    const gris = PdfColor.fromInt(0xFF555555);
    const linea = PdfColor.fromInt(0xFF999999);
    const fina = PdfColor.fromInt(0xFFCCCCCC);
    const rojo = PdfColor.fromInt(0xFFA32D2D);
    final chico = pw.TextStyle(fontSize: 8, color: gris);
    const normal = pw.TextStyle(fontSize: 8.5);
    final fuerte = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);
    const venta = pw.TextStyle(fontSize: _letraVenta);
    final ventaFuerte = venta.copyWith(fontWeight: pw.FontWeight.bold);
    final cabeza = pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold, color: gris);

    final paginas = paginar(d);
    final total = paginas.length;
    final desde = (d.desdeHoja ?? 1).clamp(1, total);
    final hasta = (d.hastaHoja ?? total).clamp(desde, total);

    pw.Widget celda(
      double? ancho,
      String texto, {
      pw.TextStyle? estilo,
      bool derecha = false,
      bool tachada = false,
    }) {
      final t = pw.Text(
        texto,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        textAlign: derecha ? pw.TextAlign.right : pw.TextAlign.left,
        style: (estilo ?? venta).copyWith(
          decoration: tachada ? pw.TextDecoration.lineThrough : null,
          color: tachada ? gris : null,
        ),
      );
      final adentro = pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2.5), child: t);
      return ancho == null
          ? pw.Expanded(child: adentro)
          : pw.SizedBox(width: ancho, child: adentro);
    }

    final a = _anchos;
    pw.Widget cabezaDeTabla() => pw.Container(
          height: _altoCabezaDeTabla,
          alignment: pw.Alignment.bottomLeft,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: linea, width: 0.9)),
          ),
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            children: [
              celda(a.numero, 'N°', estilo: cabeza),
              celda(a.cuando, 'CUÁNDO', estilo: cabeza),
              celda(null, 'COMPRADOR · FAMILIA', estilo: cabeza),
              celda(a.entradas, 'ENTRADAS', estilo: cabeza),
              celda(a.talonario, 'TALONARIO', estilo: cabeza),
              celda(a.total, 'TOTAL', estilo: cabeza, derecha: true),
              celda(a.pago, 'PAGÓ', estilo: cabeza),
              celda(a.vendio, 'VEND.', estilo: cabeza),
              celda(a.verif, 'VERIF.', estilo: cabeza),
            ],
          ),
        );

    pw.Widget renglon(FilaDelHistorial f) {
      final v = f.venta;
      final x = v.venta;
      final tachada = v.anulada;
      final tal = talonario(x);
      final comprador = pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 2.5),
          child: pw.RichText(
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            text: pw.TextSpan(
              style: venta.copyWith(
                decoration: tachada ? pw.TextDecoration.lineThrough : null,
                color: tachada ? gris : null,
              ),
              children: [
                pw.TextSpan(
                  text: x.compradorNombre,
                  style: tachada ? null : pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                if (f.familia != null)
                  pw.TextSpan(
                    text: ' · fam. ${f.familia}',
                    style: const pw.TextStyle(color: gris),
                  ),
              ],
            ),
          ),
        ),
      );
      return pw.Container(
        height: f.alto,
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: fina, width: 0.4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.SizedBox(
              height: altoVenta,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  celda(a.numero, x.numero.toString().padLeft(4, '0'), tachada: tachada),
                  celda(a.cuando, cuandoEnLaTabla(x.createdAt), tachada: tachada),
                  comprador,
                  celda(a.entradas, entradasCorto(x), tachada: tachada),
                  celda(
                    a.talonario,
                    tal.isEmpty ? '—' : (tal.length > _letrasTalonario ? 'abajo' : tal),
                    tachada: tachada,
                  ),
                  celda(a.total, pesos(x.cobrado),
                      estilo: ventaFuerte, derecha: true, tachada: tachada),
                  celda(a.pago, _medio(x), tachada: tachada),
                  celda(a.vendio, v.vendio, tachada: tachada),
                  pw.SizedBox(
                    width: a.verif,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 4),
                      child: tachada
                          ? pw.Text('Anul.',
                              style: pw.TextStyle(
                                fontSize: 7,
                                fontWeight: pw.FontWeight.bold,
                                color: rojo,
                              ))
                          : pw.Align(
                              alignment: pw.Alignment.centerLeft,
                              child: _tilde(v.verificada),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (f.abajo != null)
              pw.SizedBox(
                height: f.renglonesAbajo * altoAbajo,
                child: pw.Padding(
                  padding: pw.EdgeInsets.only(left: a.numero + a.cuando + 2.5),
                  child: pw.Text(
                    f.abajo!,
                    maxLines: f.renglonesAbajo,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      fontSize: _letraAbajo,
                      color: tachada ? rojo : gris,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    pw.Widget renglonTotal(String a, String b, {bool grande = false}) => pw.SizedBox(
          height: _altoRenglonTotal,
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(a, maxLines: 1, style: grande ? fuerte : normal),
              ),
              pw.SizedBox(width: 10),
              pw.Text(b, style: fuerte),
            ],
          ),
        );

    List<pw.Widget> totales() => [
          pw.SizedBox(height: 6),
          pw.Container(height: 0.8, color: linea),
          pw.SizedBox(height: 7),
          renglonTotal(
            'Entradas vendidas: ${t.entradas} (${t.sueltas} sueltas y ${t.deLugar} '
            'de lugares adicionales${t.otras > 0 ? ', ${t.otras} otras' : ''})',
            d.conPlata ? pesos(t.vendido) : '',
            grande: true,
          ),
          if (d.conPlata) ...[
            renglonTotal('Efectivo', pesos(t.efectivo)),
            renglonTotal('Transferencia (con los recargos)', pesos(t.transferencia)),
            if (t.recargos > 0) renglonTotal('Recargos por transferencia', pesos(t.recargos)),
            if (t.descuentos > 0)
              renglonTotal('Descuentos a mano (${t.conDescuento})', pesos(t.descuentos)),
            renglonTotal('Total cobrado', pesos(t.total), grande: true),
          ],
          renglonTotal('Ventas', '${t.ventas}'),
          if (t.anuladas > 0) renglonTotal('Anuladas (no cuentan)', '${t.anuladas}'),
          renglonTotal('Pago verificado', '${h.verificadas} de ${h.verificadas + h.sinVerificar}'),
          for (final r in h.repetidos)
            pw.SizedBox(
              height: _altoRenglonTotal * 2,
              child: pw.Text(r.texto, maxLines: 2, style: fuerte),
            ),
        ];

    pw.Widget encabezado() => pw.SizedBox(
          height: _altoEncabezado,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logo != null) ...[
                    pw.Image(logo, width: 22, height: 22),
                    pw.SizedBox(width: 8),
                  ],
                  pw.Expanded(
                    child: pw.Text(
                      d.fiesta.toUpperCase(),
                      maxLines: 1,
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  if (d.fechaFiesta != null)
                    pw.Text('Fiesta: ${_dia(d.fechaFiesta!)}', style: const pw.TextStyle(fontSize: 9.5)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'HISTORIAL DE VENTAS DE ENTRADAS · ${d.alcance}',
                      maxLines: 1,
                      style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Text(
                    'Emitido: ${ArTime.formatFechaCorta(d.emitido)} ${ArTime.formatHora(d.emitido)}',
                    style: chico,
                  ),
                ],
              ),
            ],
          ),
        );

    // Las hojas que siguen dicen de qué son: impresas por tandas, cada una se
    // entiende sola.
    pw.Widget encabezadoCorto() => pw.SizedBox(
          height: _altoEncabezadoCorto,
          child: pw.Text(
            '${d.fiesta.toUpperCase()} · HISTORIAL DE VENTAS DE ENTRADAS · ${d.alcance}',
            maxLines: 1,
            style: chico,
          ),
        );

    pw.Widget pie(int numero) => pw.SizedBox(
          height: _altoPie,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Text(
                  numero < total ? 'Sigue en la hoja ${numero + 1} · los totales van en la última' : '',
                  style: chico,
                ),
              ),
              pw.Text('Hoja $numero de $total', style: chico),
            ],
          ),
        );

    for (var i = desde; i <= hasta; i++) {
      final filasDeLaHoja = paginas[i - 1];
      final ultima = i == total;
      doc.addPage(
        pw.Page(
          pageFormat: hoja,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (i == 1) encabezado() else encabezadoCorto(),
              if (h.ventas.isEmpty)
                pw.Text('Todavía no hay ventas.', style: normal)
              else if (filasDeLaHoja.isNotEmpty) ...[
                cabezaDeTabla(),
                for (final f in filasDeLaHoja) renglon(f),
              ],
              if (ultima) ...totales(),
              pw.Spacer(),
              pie(i),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  static String nombreDelArchivo(DatosDelHistorial d) {
    final limpio = d.fiesta
        .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final tramo = d.desdeHoja == null && d.hastaHoja == null
        ? ''
        : '_hojas_${d.desdeHoja ?? 1}_a_${d.hastaHoja ?? ''}';
    return 'Ventas_de_entradas_$limpio$tramo.pdf';
  }
}
