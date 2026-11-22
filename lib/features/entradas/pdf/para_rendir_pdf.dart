import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../../models/entradas_retiro.dart' show TramoTalonario;
import '../../barra/cuentas/pesos.dart';
import '../cuentas/para_rendir.dart';
import '../cuentas/pedido_de_entradas.dart' show PedidoDeEntradas;
import 'comprobante_entradas_pdf.dart' show ComprobanteEntradasPdf;

/// Lo que lleva la constancia de unas entradas para rendir, además del bloque.
class DatosDeLaConstancia {
  /// Lo que se llevó, como está en este equipo: de acá sale todo lo que dice.
  final BloqueParaRendir bloque;

  /// La escuela (la institución de la fiesta).
  final String fiesta;
  final DateTime? fechaFiesta;

  /// La división del alumno que se las llevó ("5° A"), si se sabe.
  final String? division;

  /// Desde PARA RENDIR → CONSTANCIA: dice REIMPRESA y cómo está ahora (lo que
  /// vendió, devolvió, no volvió y lo que le queda). Recién dadas, no.
  final bool reimpresa;

  /// Reimpresa: el día en que se saca, en el reloj de Argentina (el de
  /// `hoyEnArgentinaProvider`). "Hoy" va con ese día ("Hoy, 22/11: …"): la
  /// única fecha de la hoja es la de cuando se las dieron, y un "Hoy" solo se
  /// leería como ese día (22-nov-2026).
  final DateTime? alDia;

  const DatosDeLaConstancia({
    required this.bloque,
    required this.fiesta,
    this.fechaFiesta,
    this.division,
    this.reimpresa = false,
    this.alDia,
  }) : assert(!reimpresa || alDia != null, 'la reimpresa lleva el día en que se saca');
}

/// La constancia "ENTRADAS PARA RENDIR" (21-nov-2026,
/// `docs/SPEC_entradas_para_rendir_2026-11-20.md`, sección 6, y la maqueta que
/// aprobó el usuario): el papel que firma quien se lleva entradas para venderlas
/// por su cuenta. **Una hoja A4 con dos copias de media hoja**, una arriba y otra
/// abajo, con la línea de corte en el medio: PARA QUIEN LAS LLEVA y PARA LA
/// OFICINA, las dos con firma y aclaración.
///
/// Dice quién se las lleva, cuántas y qué números, **sin pulseras**, a qué precio
/// (el del día en que se las llevó, que queda fijo), cuánto rinde si las vende
/// todas, quién se las dio y cuándo. Reimpresa, también cómo está ahora.
///
/// **No hace cuentas**: todo sale de `BloqueParaRendir`, y lo que rinde si las
/// vende todas es el renglón de la rendición de todas (`ParaRendir.renglon`),
/// lo mismo que cobraría RENDIR.
class ConstanciaParaRendirPdf {
  ConstanciaParaRendirPdf._();

  /// Una A4 entera, sin márgenes: cada copia lleva los suyos.
  static PdfPageFormat get hoja => PdfPageFormat(
        PdfPageFormat.a4.width,
        PdfPageFormat.a4.height,
        marginAll: 0,
      );

  /// Las dos copias, de arriba hacia abajo.
  static const copias = ['PARA QUIEN LAS LLEVA', 'PARA LA OFICINA'];

  /// Los márgenes de cada copia, adentro de su media hoja.
  static const margenLados = 26.0;
  static const margenArriba = 22.0;
  static const margenAbajo = 20.0;

  /// Hasta cuántas letras de la nota van en el papel: una nota muy larga no
  /// puede dejar afuera la firma (lo que no entra en una hoja no se dibuja, sin
  /// error). Lo de más se corta con "...", a la vista.
  static const kLargoDeLaNota = 240;

  static bool _esAnticipada(BloqueParaRendir b) =>
      b.nombrePrecio == PedidoDeEntradas.nombreAnticipada;

  /// "16/11", en hora de Argentina. Vacío si no se entiende.
  static String _diaYMes(String iso) {
    final t = DateTime.tryParse(iso);
    return t == null ? '' : ArTime.formatFechaCorta(t).substring(0, 5);
  }

  /// "04/12/2026".
  static String _dia(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  /// "PÉREZ, JUAN (de afuera)" o "GÓMEZ, ANA (alumno de la fiesta, 5° A)".
  static String seLleva(BloqueParaRendir b, {String? division}) {
    final d = (division ?? '').trim();
    final quien = b.esDeUnAlumno
        ? (d.isEmpty ? 'alumno de la fiesta' : 'alumno de la fiesta, $d')
        : 'de afuera';
    return '${b.persona} ($quien)';
  }

  /// "20 anticipadas · del 1201 al 1220 · sin pulseras" (o "generales", según el
  /// precio con que se las llevó).
  static String entradas(BloqueParaRendir b) {
    final una = b.cantidad == 1;
    final tipo = _esAnticipada(b)
        ? (una ? 'anticipada' : 'anticipadas')
        : (una ? 'general' : 'generales');
    return '${b.cantidad} $tipo · del ${TramoTalonario.legible(b.tramos)} · sin pulseras';
  }

  /// "$ 8.000 cada una (precio del 16/11, queda fijo)".
  static String precio(BloqueParaRendir b) {
    final dia = _diaYMes(b.dadoAt);
    return '${pesos(b.precioDeCadaUna)} cada una '
        '(${dia.isEmpty ? 'precio del día en que se las llevó' : 'precio del $dia'}, '
        'queda fijo)';
  }

  /// Lo que rinde si las vende todas: el renglón de la rendición de todas, el
  /// mismo que cobraría RENDIR.
  static double siLasVendeTodas(BloqueParaRendir b) =>
      ParaRendir.renglon(b, b.cantidad).subtotal;

  /// El rótulo de [comoEstaHoy]: "Hoy, 22/11" (el día en que se reimprime, ya
  /// en el reloj de Argentina). Sin el día, "Hoy" solo.
  static String rotuloDeHoy(DateTime? alDia) => alDia == null
      ? 'Hoy'
      : 'Hoy, ${ComprobanteEntradasPdf.diaYMesDeArgentina(alDia)}';

  /// Cómo está ahora: "vendió 15 · devolvió 3 · no volvieron 2 · le quedan 0".
  /// Null si todavía no rindió nada (recién dadas, no hay nada que decir).
  static String? comoEstaHoy(BloqueParaRendir b) {
    if (b.vendidas + b.devueltas + b.noVolvieron == 0 && b.rindioDeMas == 0) {
      return null;
    }
    return [
      'vendió ${b.vendidas}',
      'devolvió ${b.devueltas}',
      if (b.noVolvieron > 0) 'no volvieron ${b.noVolvieron}',
      'le quedan ${b.sinRendir}',
      if (b.rindioDeMas > 0) 'rindió ${b.rindioDeMas} de más: revisar',
    ].join(' · ');
  }

  /// "Se las dio: Jefe · el 20/11/2026 10:00 hs".
  static String quienSeLasDio(BloqueParaRendir b) {
    final quien = (b.dio.hechoPor ?? '').trim();
    final cuando = ComprobanteEntradasPdf.cuando(b.dadoAt);
    final elDia = cuando.isEmpty ? '' : ' el $cuando';
    return quien.isEmpty ? 'Se las dieron$elDia' : 'Se las dio: $quien ·$elDia';
  }

  /// La nota, cortada si es muy larga ([kLargoDeLaNota]). Null si no hay.
  static String? nota(BloqueParaRendir b) {
    final n = (b.dio.nota ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return null;
    return n.length <= kLargoDeLaNota ? n : '${n.substring(0, kLargoDeLaNota).trimRight()}...';
  }

  /// [fuentes]: las Outfit de la app (`PdfService.fuentesOutfit`). Sin ellas va
  /// la letra de fábrica del paquete (los tests, para poder leer el texto).
  static Future<Uint8List> armar(
    DatosDeLaConstancia d, {
    (pw.Font, pw.Font)? fuentes,
    pw.ImageProvider? logo,
  }) async {
    final b = d.bloque;
    final doc = pw.Document(
      theme: fuentes == null
          ? null
          : pw.ThemeData.withFont(base: fuentes.$1, bold: fuentes.$2),
    );
    const gris = PdfColor.fromInt(0xFF555555);
    const linea = PdfColor.fromInt(0xFF999999);
    final chico = pw.TextStyle(fontSize: 8.5, color: gris);
    const normal = pw.TextStyle(fontSize: 9.5);
    final fuerte = pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold);

    // "Se lleva: …": lo de la derecha puede ser largo (un nombre, un contacto,
    // dos tramos), así que va en Expanded y baja de renglón en vez de salirse.
    pw.Widget dato(String etiqueta, String valor, {pw.TextStyle? estilo}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 62, child: pw.Text('$etiqueta:', style: normal)),
              pw.Expanded(child: pw.Text(valor, style: estilo ?? fuerte)),
            ],
          ),
        );
    pw.Widget raya() => pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 5),
          height: 0.6,
          color: linea,
        );

    final contacto = (b.contacto ?? '').trim();
    final hoy = d.reimpresa ? comoEstaHoy(b) : null;
    final laNota = nota(b);
    final total = pesos(siLasVendeTodas(b));
    final una = b.cantidad == 1;

    pw.Widget copia(String para) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) ...[
                  pw.Image(logo, width: 24, height: 24),
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
                    'ENTRADAS PARA RENDIR',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                if (d.reimpresa)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    margin: const pw.EdgeInsets.only(right: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: gris, width: 0.8),
                    ),
                    child: pw.Text('REIMPRESA', style: fuerte),
                  ),
                pw.Text(para, style: fuerte),
              ],
            ),
            raya(),
            dato('Se lleva', seLleva(b, division: d.division)),
            if (contacto.isNotEmpty) dato('Contacto', contacto, estilo: normal),
            dato('Entradas', entradas(b)),
            dato('Precio', precio(b), estilo: normal),
            raya(),
            pw.RichText(
              text: pw.TextSpan(
                style: normal,
                children: [
                  pw.TextSpan(text: una ? 'Si la vende, rinde ' : 'Si las vende todas, rinde '),
                  pw.TextSpan(text: total, style: fuerte),
                  pw.TextSpan(
                    text: una
                        ? '. Si no la vende, la devuelve. Rinde toda la plata.'
                        : '. Las que no venda, las devuelve. Rinde toda la plata.',
                  ),
                ],
              ),
            ),
            if (hoy != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text('${rotuloDeHoy(d.alDia)}: $hoy', style: fuerte),
              ),
            if (b.anulado)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text(
                  'ANULADAS el ${ComprobanteEntradasPdf.cuando(b.anulacion!.createdAt)}'
                  '${(b.anulacion!.hechoPor ?? '').isEmpty ? '' : ' por ${b.anulacion!.hechoPor}'}'
                  ' · ${b.anulacion!.motivo ?? ''}: no tiene nada para rendir.',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red800,
                  ),
                ),
              ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(quienSeLasDio(b), style: chico),
            ),
            if (laNota != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text('Nota: $laNota', style: chico),
              ),
            // Lugar para firmar, y la firma abajo de todo.
            pw.SizedBox(height: 24),
            pw.Spacer(),
            pw.Row(
              children: [
                for (final (i, rotulo) in ['Firma de quien se las lleva', 'Aclaración'].indexed) ...[
                  if (i > 0) pw.SizedBox(width: 30),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.only(top: 3),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: PdfColor.fromInt(0xFF333333), width: 0.8),
                        ),
                      ),
                      child: pw.Text(rotulo, style: chico, textAlign: pw.TextAlign.center),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );

    final media = hoja.height / 2;
    doc.addPage(
      pw.Page(
        pageFormat: hoja,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (final (i, para) in copias.indexed)
              pw.Container(
                height: media,
                padding: const pw.EdgeInsets.fromLTRB(
                  margenLados,
                  margenArriba,
                  margenLados,
                  margenAbajo,
                ),
                // La línea de corte, entre las dos copias.
                decoration: i == 0
                    ? const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: linea,
                            width: 0.8,
                            style: pw.BorderStyle.dashed,
                          ),
                        ),
                      )
                    : null,
                child: copia(para),
              ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// Cómo se llama el archivo: "Constancia_para_rendir_PEREZ_JUAN_1201.pdf".
  static String nombreDelArchivo(DatosDeLaConstancia d) {
    final limpio = d.bloque.persona
        .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final tramos = d.bloque.tramos;
    final desde = tramos.isEmpty ? '' : '_${tramos.first.desde}';
    return 'Constancia_para_rendir_$limpio$desde.pdf';
  }
}
