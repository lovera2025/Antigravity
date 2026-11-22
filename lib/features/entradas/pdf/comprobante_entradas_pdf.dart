import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../../models/entradas_retiro.dart';
import '../../barra/cuentas/pesos.dart';
import '../cuentas/para_rendir.dart' show BloqueParaRendir;
import '../datos/entradas_repositorio.dart';

/// Lo que el comprobante de una **rendición** de entradas para rendir dice de
/// lo que se llevó quien rinde (21-nov-2026,
/// `docs/SPEC_entradas_para_rendir_2026-11-20.md`, sección 6). La plata es la
/// venta de siempre; esto es solo el renglón "Se llevó 20 (1201 al 1220) ·
/// vendió 15 · devolvió 5 (1216 al 1220) · le quedan 0", y **todo sale de
/// `BloqueParaRendir`**: acá no hay cuentas.
class RendicionDelComprobante {
  /// Quién rinde.
  final String persona;

  /// Lo que se llevó: recién rendida, cómo quedó en ese acto; reimpresa, cómo
  /// está en este equipo el día [alDia]. Null: todavía no bajó (o no se pudo
  /// leer); el papel sale con quién rinde y lo vendido, sin el renglón del
  /// bloque.
  final BloqueParaRendir? bloque;

  /// Cuántas devolvió **en esta misma rendición**, con sus números. Null: no se
  /// sabe con certeza (al reimprimir): el renglón no lo dice.
  final int? devolvio;
  final List<TramoTalonario> numerosDevueltos;

  /// Reimpresa: el día en que se saca la copia, en el reloj de Argentina (el
  /// de `hoyEnArgentinaProvider`). Lo que le queda es de ese día, y el papel lo
  /// dice con la fecha ("al 22/11 le quedan 0"): la única fecha de arriba es
  /// la de la rendición, y un "hoy" solo se leería como ese día (22-nov-2026).
  /// Null: recién rendida.
  final DateTime? alDia;

  /// Reimpresa: lo que le queda es del día [alDia], no del de la rendición.
  bool get leQuedanDeHoy => alDia != null;

  /// Recién rendida: lo que devolvió en ese acto se sabe, y "le quedan" es lo
  /// que quedó después. [bloque] es **cómo quedó en ese acto** (lo lee VENDER
  /// una vez, al guardar), no cómo está cuando se saca el papel.
  const RendicionDelComprobante.alRendir({
    required this.persona,
    required this.bloque,
    required int this.devolvio,
    this.numerosDevueltos = const [],
  }) : alDia = null;

  /// Reimpresa desde VENTAS: no se sabe con certeza qué devolvió en ese mismo
  /// acto, así que dice solo lo seguro (se llevó, lo que vendió en esta
  /// rendición y lo que le queda el día [alDia], en que se reimprime).
  const RendicionDelComprobante.reimpresa({
    required this.persona,
    this.bloque,
    required DateTime this.alDia,
  })  : devolvio = null,
        numerosDevueltos = const [];
}

/// Lo que lleva el comprobante de una venta de entradas, además de la venta.
class DatosDelComprobante {
  final VentaEntradas venta;

  /// La escuela (la institución de la fiesta).
  final String fiesta;
  final DateTime? fechaFiesta;

  /// Si compra una familia de la fiesta: el alumno y su mesa ("14 y 15").
  final String? alumno;
  final String? mesa;

  /// Reimpreso: dice COPIA.
  final bool copia;

  /// Anulada: va ANULADA cruzado, con el motivo.
  final AnulacionEntradas? anulacion;

  /// La venta es la plata de una rendición de entradas para rendir: el papel es
  /// el de la rendición ("RENDICIÓN DE ENTRADAS", "Recibió" y "Rinde").
  final RendicionDelComprobante? rendicion;

  const DatosDelComprobante({
    required this.venta,
    required this.fiesta,
    this.fechaFiesta,
    this.alumno,
    this.mesa,
    this.copia = false,
    this.anulacion,
    this.rendicion,
  });
}

/// El comprobante de una venta de entradas: **media hoja A4**, con lo vendido y
/// los números del talonario (sección 7.4 del spec del 13-nov). **No habla de
/// pulseras**: la pulsera no se vende (el usuario, 20-nov-2026); las VIP se
/// entregan sin cargo, aparte.
///
/// Con [DatosDelComprobante.rendicion] es el de una **rendición** de entradas
/// para rendir: "RENDICIÓN DE ENTRADAS", quién recibió la plata, quién rinde y
/// cómo quedó lo que se llevó (21-nov-2026).
///
/// Todo lo que dice sale de la venta como quedó guardada: no hace ninguna
/// cuenta (el total, el recargo y el vuelto ya están en la fila).
class ComprobanteEntradasPdf {
  ComprobanteEntradasPdf._();

  /// Media A4, para cortar dos por hoja.
  static PdfPageFormat get hoja => PdfPageFormat(
        PdfPageFormat.a4.width,
        PdfPageFormat.a4.height / 2,
        marginAll: 26,
      );

  static String numero(VentaEntradas v) =>
      'N° ${v.numero.toString().padLeft(4, '0')}';

  /// "14/11/2026 11:32 hs", en hora de Argentina. Vacío si no se entiende.
  static String cuando(String iso) {
    final t = DateTime.tryParse(iso);
    return t == null
        ? ''
        : '${ArTime.formatFechaCorta(t)} ${ArTime.formatHora(t)}';
  }

  static String _dia(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  static String _pct(double v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',');

  /// Lo que dice un renglón a la izquierda: "8 × Entrada · $ 10.000 c/u".
  static String renglon(RenglonEntradas r) {
    final descuento = r.tipo == TipoRenglonEntradas.suelta && r.descuentoPct > 0
        ? ' · descuento ${_pct(r.descuentoPct)} %'
        : '';
    return '${r.cantidad} × ${r.nombre} · ${pesos(r.precio)} c/u$descuento';
  }

  /// Cómo pagó, en palabras. En el mixto, cuánto de cada uno.
  static String comoPago(VentaEntradas v) => switch (v.medio) {
        MedioBarra.efectivo => 'Efectivo',
        MedioBarra.transferencia => 'Transferencia',
        MedioBarra.mixto =>
          'Mixto · efectivo ${pesos(v.efectivo)} · transferencia ${pesos(v.transferencia)}',
        MedioBarra.otro => '—',
      };

  /// Los números del talonario, o null si no se anotaron.
  static String? talonario(VentaEntradas v) {
    final tramos = TramoTalonario.deTexto(v.numeros);
    return tramos.isEmpty ? null : TramoTalonario.legible(tramos);
  }

  /// "16/11", en hora de Argentina. Vacío si no se entiende.
  static String _diaYMes(String iso) {
    final t = DateTime.tryParse(iso);
    return t == null ? '' : ArTime.formatFechaCorta(t).substring(0, 5);
  }

  /// "22/11", de un momento que ya viene en el reloj de Argentina (el de
  /// `hoyEnArgentinaProvider`): se leen sus números, sin volver a correrlo.
  static String diaYMesDeArgentina(DateTime ar) =>
      '${ar.day.toString().padLeft(2, '0')}/${ar.month.toString().padLeft(2, '0')}';

  /// El renglón de cómo quedó lo que se llevó quien rinde: "Se llevó 20 (1201
  /// al 1220) el 16/11 · vendió 15 · devolvió 5 (1216 al 1220) · le quedan 0".
  /// [vendio]: lo de esta rendición (la cantidad de su venta). Reimpresa, sin
  /// lo devuelto (no se sabe con certeza) y con el día de la copia: "al 22/11
  /// le quedan 0". Null si el bloque todavía no está en este equipo: no se
  /// inventa.
  static String? lineaDeLaRendicion(RendicionDelComprobante r, int vendio) {
    final b = r.bloque;
    if (b == null) return null;
    final dia = _diaYMes(b.dadoAt);
    final devolvio = r.devolvio;
    final alDia = r.alDia;
    return [
      'Se llevó ${b.cantidad} (${TramoTalonario.legible(b.tramos)})'
          '${dia.isEmpty ? '' : ' el $dia'}',
      alDia != null ? 'vendió $vendio en esta rendición' : 'vendió $vendio',
      if (devolvio != null && devolvio > 0)
        r.numerosDevueltos.isEmpty
            ? 'devolvió $devolvio'
            : 'devolvió $devolvio (${TramoTalonario.legible(r.numerosDevueltos)})',
      alDia != null
          ? 'al ${diaYMesDeArgentina(alDia)} le quedan ${b.sinRendir}'
          : 'le quedan ${b.sinRendir}',
    ].join(' · ');
  }

  /// Lo que dice el papel de una rendición anulada: la plata se devolvió y
  /// esas entradas dejaron de contar como vendidas (vuelven a quedar a cargo
  /// de quien las llevó). Nunca "devolvieron las entradas": no volvió nada a
  /// la oficina.
  static String _rendicionAnulada(int cantidad) => cantidad == 1
      ? 'la entrada dejó de contar como vendida'
      : 'las $cantidad dejaron de contar como vendidas';

  /// [fuentes]: las Outfit de la app (`PdfService.fuentesOutfit`). Sin ellas va
  /// la letra de fábrica del paquete (los tests, para poder leer el texto).
  static Future<Uint8List> armar(
    DatosDelComprobante d, {
    (pw.Font, pw.Font)? fuentes,
    pw.ImageProvider? logo,
  }) async {
    final v = d.venta;
    final doc = pw.Document(
      theme: fuentes == null
          ? null
          : pw.ThemeData.withFont(base: fuentes.$1, bold: fuentes.$2),
    );
    const gris = PdfColor.fromInt(0xFF555555);
    const linea = PdfColor.fromInt(0xFF999999);
    final chico = pw.TextStyle(fontSize: 8.5, color: gris);
    final normal = const pw.TextStyle(fontSize: 9.5);
    final fuerte = pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold);

    // Lo de la izquierda puede ser largo: va en Expanded para que baje de
    // renglón en vez de salirse de la hoja.
    pw.Widget fila(String a, String b, {pw.TextStyle? estilo}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: pw.Text(a, style: estilo ?? normal)),
              pw.SizedBox(width: 10),
              pw.Text(b, style: estilo ?? fuerte),
            ],
          ),
        );
    // "Recibió: Carla", "Rinde: PÉREZ, JUAN": el nombre puede ser largo, así
    // que va en Expanded (baja de renglón en vez de salirse de la hoja).
    pw.Widget dato(String etiqueta, String valor) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('$etiqueta:', style: normal),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Text(valor, style: fuerte, textAlign: pw.TextAlign.right),
              ),
            ],
          ),
        );
    pw.Widget raya() => pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 5),
          height: 0.6,
          color: linea,
        );

    final numeros = talonario(v);
    final rinde = d.rendicion;
    final quienRinde = rinde == null
        ? ''
        : (rinde.persona.trim().isEmpty ? v.compradorNombre : rinde.persona.trim());
    final delBloque = rinde == null ? null : lineaDeLaRendicion(rinde, v.cantidad);
    final cuerpo = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[
              pw.Image(logo, width: 26, height: 26),
              pw.SizedBox(width: 8),
            ],
            pw.Expanded(
              child: pw.Text(
                d.fiesta.toUpperCase(),
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            ),
            if (d.fechaFiesta != null)
              pw.Text('Fiesta: ${_dia(d.fechaFiesta!)}', style: normal),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                rinde == null
                    ? 'COMPROBANTE DE ENTRADAS · ${numero(v)}'
                    : 'RENDICIÓN DE ENTRADAS · ${numero(v)}',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ),
            if (d.copia)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                margin: const pw.EdgeInsets.only(right: 8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: gris, width: 0.8),
                ),
                child: pw.Text('COPIA', style: fuerte),
              ),
            pw.Text(cuando(v.createdAt), style: normal),
          ],
        ),
        if (rinde == null && (v.hechoPor ?? '').isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text('Vendió: ${v.hechoPor}', style: chico),
          ),
        raya(),
        if (rinde == null) ...[
          fila(
            'Compra',
            v.compradorDni == null
                ? v.compradorNombre
                : '${v.compradorNombre} · DNI ${v.compradorDni}',
          ),
          if ((d.alumno ?? '').isNotEmpty)
            fila(
              'Familia',
              (d.mesa ?? '').isEmpty ? d.alumno! : '${d.alumno} · mesa ${d.mesa}',
            ),
        ] else ...[
          // La plata la recibió quien cobró (el que anotó la venta) y la rinde
          // quien se llevó las entradas.
          if ((v.hechoPor ?? '').trim().isNotEmpty) dato('Recibió', v.hechoPor!.trim()),
          dato('Rinde', quienRinde),
          if (delBloque != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(delBloque, style: normal),
            ),
        ],
        raya(),
        for (final r in v.renglones)
          fila(
            rinde == null ? renglon(r) : '${renglon(r)} · precio fijo',
            pesos(r.subtotal),
          ),
        if (v.renglones.isEmpty)
          fila('${v.cantidad} entradas', pesos(v.total)),
        if (v.recargo > 0)
          fila(
            v.recargoPct == null
                ? 'Recargo por transferencia'
                : 'Recargo por transferencia (${_pct(v.recargoPct!)} %)',
            pesos(v.recargo),
          ),
        raya(),
        fila(
          'TOTAL',
          pesos(v.cobrado),
          estilo: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        fila('Pagó', comoPago(v)),
        if (v.recibe != null && v.vuelto > 0)
          fila('Entregó ${pesos(v.recibe!)}', 'Vuelto ${pesos(v.vuelto)}'),
        // Lo vendido son solo entradas: la pulsera no se vende (20-nov-2026).
        // En una rendición los números son los del bloque, que ya están arriba:
        // la venta no los lleva.
        if (rinde == null) ...[
          raya(),
          fila('Entradas', '${v.cantidad}'),
          numeros == null
              ? pw.Text('Sin números del talonario anotados', style: chico)
              : fila('Talonario', numeros),
        ],
        if (d.anulacion != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text(
              'ANULADA el ${cuando(d.anulacion!.createdAt)}'
              '${(d.anulacion!.hechoPor ?? '').isEmpty ? '' : ' por ${d.anulacion!.hechoPor}'}'
              ' · ${d.anulacion!.motivo} · '
              '${rinde != null ? _rendicionAnulada(v.cantidad) : d.anulacion!.devueltas ? 'devolvieron las entradas' : 'NO devolvieron las entradas'}',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red800,
              ),
            ),
          ),
      ],
    );

    doc.addPage(
      pw.Page(
        pageFormat: hoja,
        build: (_) => d.anulacion == null
            ? cuerpo
            : pw.Stack(
                children: [
                  cuerpo,
                  pw.Positioned.fill(
                    child: pw.Center(
                      child: pw.Transform.rotate(
                        angle: math.pi / 9,
                        child: pw.Opacity(
                          opacity: 0.22,
                          child: pw.Text(
                            'ANULADA',
                            style: pw.TextStyle(
                              fontSize: 64,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
    return doc.save();
  }

  /// Cómo se llama el archivo. El de una rendición, "Rendicion_0007_…".
  static String nombreDelArchivo(DatosDelComprobante d) {
    final limpio = d.venta.compradorNombre
        .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final que = d.rendicion == null ? 'Entradas' : 'Rendicion';
    return '${que}_${d.venta.numero.toString().padLeft(4, '0')}_$limpio.pdf';
  }
}
