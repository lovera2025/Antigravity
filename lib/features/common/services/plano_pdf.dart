import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart' show Matrix4;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../../models/plano_evento.dart';
import '../../plano/estilos/estilo_plano.dart';
import '../../plano/modelo/armado_salon.dart';
import '../../plano/modelo/estado_plano.dart';
import '../../plano/services/medir_salon.dart';
import '../../plano/services/plano_de_la_fiesta.dart';
import '../../plano/services/plano_papel.dart';
import 'planilla_tema.dart';

/// Los colores del plano en papel. Siempre sobre blanco: los fondos oscuros de
/// Gala y Neón son para la pantalla, en la hoja serían tinta tirada.
///
/// En blanco y negro las divisiones van en gris alternado; en color, en el
/// color de su estilo llevado a papel ([TemaPlano.papel]): el que la fiesta
/// eligió en pantalla es el que sale. En los dos casos la leyenda dice qué
/// mesas tiene cada una: el relleno ayuda, pero no es el único dato.
class _Tinta {
  final bool bn;

  /// El estilo de la fiesta: de él salen los colores de las divisiones.
  final EstiloPlano estilo;

  /// El color de cada división de la leyenda, como índice en la paleta: el
  /// que eligió la fiesta en Personalizar. Así una división lleva en el papel
  /// el mismo lugar de la paleta que en la pantalla.
  final List<int> colores;

  _Tinta(this.bn, {required this.estilo, this.colores = const []});

  late final _rellenos = TemaPlano.de(estilo).papel;
  late final _trazos = TemaPlano.de(estilo).papelNumero;

  int _enPaleta(int division) =>
      division < colores.length ? colores[division] : division;

  static const blanco = PdfColors.white;
  static const negro = PdfColor.fromInt(0xFF1F2328);
  static const _grisDivision = PdfColor.fromInt(0xFFD9D9D9);

  PdfColor get trazoVacia => const PdfColor.fromInt(0xFF8C8C8C);
  PdfColor get numeroVacia => const PdfColor.fromInt(0xFF7A7A7A);
  PdfColor get hormigon => bn
      ? const PdfColor.fromInt(0xFFF5F5F5)
      : const PdfColor.fromInt(0xFFFAF8F3);
  PdfColor get hormigonBorde => const PdfColor.fromInt(0xFF6E6E6E);
  PdfColor get sector => bn
      ? const PdfColor.fromInt(0xFFEDEDED)
      : const PdfColor.fromInt(0xFFECE9E1);
  PdfColor get sectorBorde => const PdfColor.fromInt(0xFFA3A3A3);
  PdfColor get sectorTexto => const PdfColor.fromInt(0xFF4A4A4A);
  PdfColor get escenario => const PdfColor.fromInt(0xFF3D3D3B);
  PdfColor get silla => const PdfColor.fromInt(0xFFDADADA);
  PdfColor get sillaBorde => const PdfColor.fromInt(0xFF8A8A8A);
  PdfColor get pasto => bn
      ? const PdfColor.fromInt(0xFF9A9A9A)
      : const PdfColor.fromInt(0xFF5B9A2E);
  PdfColor get apellido => const PdfColor.fromInt(0xFF2C2C2A);
  PdfColor get marco => const PdfColor.fromInt(0xFFC9C9C9);

  /// El relleno de una mesa con familia.
  PdfColor relleno(int? division) {
    if (division == null || division < 0) return blanco;
    if (bn) return division.isEven ? blanco : _grisDivision;
    final l = _rellenos;
    return PdfColor.fromInt(l[_enPaleta(division) % l.length].toARGB32());
  }

  /// El anillo y el número de una mesa con familia.
  PdfColor trazo(int? division) {
    if (bn || division == null || division < 0) return negro;
    final l = _trazos;
    return PdfColor.fromInt(l[_enPaleta(division) % l.length].toARGB32());
  }
}

/// Lo que ya se decidió de una hoja antes de dibujarla: qué parte va al papel,
/// a qué escala y si entran los apellidos.
class _HojaPapel {
  final HojaPlano hoja;
  final RectPlano marco;

  /// Puntos de papel por unidad del plano.
  final double escala;

  /// Alto de la letra de los apellidos, en puntos. Cero: no se escriben.
  final double tamApellido;

  /// Lo que queda para el dibujo entre el encabezado y el pie.
  final double alto;

  /// Con qué se midieron el encabezado y el pie. Se dibujan con esto mismo:
  /// así ocupan exactamente lo que se midió y el dibujo no pasa de hoja.
  final RectPlano? marcoDelEncabezado;
  final bool avisaSinApellidos;

  const _HojaPapel({
    required this.hoja,
    required this.marco,
    required this.escala,
    required this.tamApellido,
    required this.alto,
    required this.marcoDelEncabezado,
    required this.avisaSinApellidos,
  });
}

/// El plano del salón en papel: una hoja A4 acostada por cada hoja del armado.
///
/// Las cuentas (qué se recorta, la leyenda, dónde va el nombre de cada
/// división) las hace [PlanoPapel], con tests. Acá solo se dibuja.
///
/// - **Siempre sobre blanco**, con el lenguaje de cada estilo: Gala con anillo
///   doble y su serif, Arquitecto con las sillas, Neón con anillo grueso.
/// - El dibujo se escala para entrar entero: nunca se recorta una mesa.
/// - Los apellidos van debajo de la mesa principal de cada familia. Si a ese
///   tamaño no se leen, no se escriben y el pie lo dice.
/// - Lleva la regla en metros y, si el salón se armó a medida, lo que mide el
///   playón.
class PlanoPdf {
  PlanoPdf._();

  static final PdfPageFormat _formato = PdfPageFormat.a4.landscape;

  /// Con la letra más chica que esto un apellido no se lee impreso.
  static const double apellidoMinimoPt = 4.3;
  static const double apellidoMaximoPt = 7.5;

  /// El lugar de la regla en el pie. Es fijo: así el alto del pie no depende
  /// de la escala, que a su vez depende del alto del pie.
  static const double _anchoRegla = 120;
  static const double _altoRegla = 10;

  static String _dos(int n) => n.toString().padLeft(2, '0');

  /// El radio de lo que se dibuja de una mesa, con sus sillas, en unidades
  /// del plano.
  static double ocupa(ArmadoSalon armado, EstiloPlano estilo, double escala) {
    final tema = TemaPlano.de(estilo);
    final r = armado.radio * tema.escalaMesa;
    return r + (_conSillas(estilo, escala) ? 13 : 2);
  }

  /// Arquitecto dibuja las ocho sillas si en el papel se llegan a ver.
  static bool _conSillas(EstiloPlano estilo, double escala) =>
      TemaPlano.de(estilo).sillas && 12 * escala >= 2.6;

  /// El alto de la letra de los apellidos en una hoja, en puntos. Cero si no
  /// entran a un tamaño que se lea: tienen que caber entre una mesa y la de
  /// abajo.
  static double tamApellido({
    required ArmadoSalon armado,
    required String hoja,
    required EstiloPlano estilo,
    required double escala,
  }) {
    final paso = PlanoPapel.pasoVertical(armado, hoja);
    final hueco = paso == null
        ? double.infinity
        : (paso - 2 * ocupa(armado, estilo, escala)) * escala;
    final radioPt = armado.radio * TemaPlano.de(estilo).escalaMesa * escala;
    final tam = [hueco * 0.8, radioPt * 0.52, apellidoMaximoPt].reduce(math.min);
    return tam >= apellidoMinimoPt ? tam : 0;
  }

  static Future<Uint8List> construir({
    required String institucion,
    required PlanoDeLaFiesta plano,
    required EstiloPlano estilo,
    String? lineaSorteo,
    bool blancoYNegro = false,
    pw.Font? regular,
    pw.Font? negrita,

    /// La letra del estilo (la serif de Gala, la de Neón). Null: la de las
    /// planillas.
    pw.Font? letraPlano,
    DateTime? generada,
  }) async {
    final tema = PlanillaTema(blancoYNegro: blancoYNegro);
    final tinta = _Tinta(
      blancoYNegro,
      estilo: estilo,
      colores: plano.colores,
    );
    final theme = regular != null && negrita != null
        ? pw.ThemeData.withFont(base: regular, bold: negrita)
        : null;
    // Los números de Gala no van en su serif: sus cifras son de estilo antiguo
    // y un 1 se lee como una I ("101" parece "IOI"). En pantalla se le piden
    // las cifras alineadas a la letra; el PDF no sabe pedirlas.
    final letraNumeros = estilo == EstiloPlano.gala
        ? regular ?? pw.Font.helvetica()
        : letraPlano ?? negrita ?? pw.Font.helveticaBold();
    final letraApellidos = letraPlano ?? regular ?? pw.Font.helvetica();
    final letraEtiquetas = negrita ?? pw.Font.helveticaBold();

    final armado = plano.armado;
    final estado = plano.estado;
    final cuando = generada ?? ArTime.nowAr();
    final textoGenerada = 'Generado el ${_dos(cuando.day)}/${_dos(cuando.month)}/'
        '${cuando.year} · ${_dos(cuando.hour)}:${_dos(cuando.minute)}';
    final resumen = PlanoPapel.resumen(armado, estado);
    final divisiones = PlanoPapel.divisiones(estado);
    final hojas = armado.hojas;
    final ancho = _formato.width - 2 * PlanillaTema.margen;

    pw.Widget encabezado(HojaPlano hoja, RectPlano? marco) {
      final titulo = plano.config.titulo?.trim() ?? '';
      final subtitulo = plano.config.subtitulo?.trim() ?? '';
      final fuera =
          marco == null ? 0.0 : PlanoPapel.hormigonFueraM(armado, hoja.id, marco);
      return tema.encabezado(
        titulo: hojas.length > 1 && hoja.titulo.trim().isNotEmpty
            ? 'Plano del salón · ${hoja.titulo}'
            : 'Plano del salón',
        institucion: institucion,
        version: armado.nombre.trim().isEmpty ? 'Plano' : armado.nombre,
        generada: textoGenerada,
        extra: lineaSorteo,
        control: [
          if (titulo.isNotEmpty) titulo,
          if (subtitulo.isNotEmpty) subtitulo,
          resumen.texto,
          ?_textoPlayon(armado, hoja, plano.medidas.playon.aproximado),
          if (fuera >= 1)
            'se ve hasta donde hay mesas: el hormigón sigue '
                '${MedirSalon.metros(fuera, decimales: 0)} más hacia el fondo',
        ].join(' · '),
      );
    }

    pw.Widget pie(int numero, {double? escala, required bool sinApellidos}) {
      final letra = tema.estilo(size: 7.5, color: tema.textoSuave);
      pw.Widget item(pw.Widget simbolo, String texto) => pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              simbolo,
              pw.SizedBox(width: 3),
              pw.Text(texto, style: letra),
            ],
          );
      pw.Widget mesa({
        bool llena = false,
        bool libre = false,
        bool fijada = false,
        bool pasto = false,
        bool conflicto = false,
        int sillasExtra = 0,
      }) =>
          pw.CustomPaint(
            size: const PdfPoint(13, 9),
            painter: (g, size) => _mesa(
              g,
              cx: size.x / 2,
              cy: size.y / 2,
              r: 3.4,
              escala: 0,
              estilo: EstiloPlano.arquitecto,
              tinta: tinta,
              llena: llena,
              division: null,
              conflicto: conflicto,
              libre: libre,
              fijada: fijada,
              pasto: pasto,
              sillasExtra: sillasExtra,
              conSillas: false,
              grosor: 0.6,
            ),
          );

      final regla = escala == null
          ? null
          : MedirSalon.reglaPara(
              escala,
              armado.metrosPorUnidad,
              maxPx: _anchoRegla - 34,
            );
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Wrap(
                spacing: 10,
                runSpacing: 2,
                crossAxisAlignment: pw.WrapCrossAlignment.center,
                children: [
                  for (final d in divisiones)
                    item(
                      pw.Container(
                        width: 7,
                        height: 7,
                        decoration: pw.BoxDecoration(
                          color: tinta.relleno(d.indice),
                          shape: pw.BoxShape.circle,
                          border: pw.Border.all(
                            color: tinta.trazo(d.indice),
                            width: 0.6,
                          ),
                        ),
                      ),
                      d.texto,
                    ),
                  if (resumen.pasto > 0)
                    item(mesa(pasto: true), 'Pasto: avisar a la familia'),
                  if (resumen.libres > 0)
                    item(mesa(libre: true), 'Libre: no se usa'),
                  if (estado.mesas.any((i) => i.fijadaPara != null))
                    item(mesa(fijada: true), 'Fijada antes del sorteo'),
                  if (resumen.sillasExtra > 0)
                    item(mesa(llena: true, sillasExtra: 1), 'Lleva sillas extra'),
                  if (resumen.conflictos > 0)
                    item(mesa(conflicto: true), 'Revisar: no cierra'),
                  if (sinApellidos)
                    pw.Text(
                      'A este tamaño los apellidos no se leen: están en la '
                      'planilla del sorteo.',
                      style: letra,
                    ),
                ],
              ),
            ),
            pw.SizedBox(width: 10),
            pw.SizedBox(
              width: _anchoRegla,
              height: _altoRegla,
              child: regla == null
                  ? null
                  : pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Container(
                          width: regla.px,
                          height: 4,
                          margin: const pw.EdgeInsets.only(bottom: 1.5),
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              left: pw.BorderSide(color: tema.texto, width: 0.9),
                              right: pw.BorderSide(color: tema.texto, width: 0.9),
                              bottom: pw.BorderSide(color: tema.texto, width: 0.9),
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 4),
                        pw.Text(
                          MedirSalon.metros(regla.metros),
                          style: tema.estilo(size: 7.5, negrita: true),
                        ),
                      ],
                    ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              hojas.length > 1 ? 'Plano · hoja $numero de ${hojas.length}' : 'Plano',
              style: letra,
            ),
          ],
        ),
      );
    }

    // El dibujo ocupa lo que dejan el encabezado y el pie, y su escala sale de
    // ese alto. Pero lo que dicen el encabezado ("el hormigón sigue…") y el
    // pie ("los apellidos no se leen") sale de la escala: se mide, se decide,
    // y si lo decidido les cambia el texto se vuelve a medir.
    final altoUtil = _formato.height - 2 * PlanillaTema.margen;
    Future<_HojaPapel> decidir(int i) async {
      final hoja = hojas[i];
      final hayApellidos = armado.mesasDeHoja(hoja.id).any((m) {
        final info = estado.info(m.numero);
        return info.principal && (info.ocupante ?? info.fijadaPara) != null;
      });
      RectPlano? marcoMedido;
      var avisa = false;
      late _HojaPapel decidida;
      for (var vuelta = 0; vuelta < 4; vuelta++) {
        final ocupado = await _medirAlto(
          theme,
          ancho,
          () => [
            encabezado(hoja, marcoMedido),
            pie(i + 1, sinApellidos: avisa),
          ],
        );
        // Dos puntos de aire, para que un redondeo no mande el dibujo a la
        // hoja siguiente. Y un piso: con un encabezado desmedido el dibujo
        // sale chico, pero sale.
        final alto = math.max(80.0, altoUtil - ocupado - 2);
        final marco = PlanoPapel.marco(armado, hoja.id, proporcion: ancho / alto);
        final escala = math.min(ancho / marco.ancho, alto / marco.alto);
        final tam = tamApellido(
          armado: armado,
          hoja: hoja.id,
          estilo: estilo,
          escala: escala,
        );
        decidida = _HojaPapel(
          hoja: hoja,
          marco: marco,
          escala: escala,
          tamApellido: tam,
          alto: alto,
          marcoDelEncabezado: marcoMedido,
          avisaSinApellidos: avisa,
        );
        final faltan = tam == 0 && hayApellidos;
        if (marco == marcoMedido && faltan == avisa) break;
        marcoMedido = marco;
        avisa = faltan;
      }
      return decidida;
    }

    final decididas = [
      for (var i = 0; i < hojas.length; i++) await decidir(i),
    ];

    final doc = pw.Document(
      theme: theme,
      title: 'Plano del salón',
      author: 'Junior Eventos',
    );
    for (var i = 0; i < decididas.length; i++) {
      final h = decididas[i];
      doc.addPage(
        pw.MultiPage(
          pageFormat: _formato,
          margin: const pw.EdgeInsets.all(PlanillaTema.margen),
          maxPages: 4,
          header: (_) => encabezado(h.hoja, h.marcoDelEncabezado),
          footer: (_) => pie(
            i + 1,
            escala: h.escala,
            sinApellidos: h.avisaSinApellidos,
          ),
          build: (_) => [
            pw.SizedBox(
              width: double.infinity,
              height: h.alto,
              child: _DibujoPlano(
                armado: armado,
                hoja: h,
                estado: estado,
                estilo: estilo,
                tinta: tinta,
                bloques: plano.config.bloques,
                letraNumeros: letraNumeros,
                letraApellidos: letraApellidos,
                letraEtiquetas: letraEtiquetas,
              ),
            ),
          ],
        ),
      );
    }
    return doc.save();
  }

  /// Cuánto ocupan unos widgets apilados, en puntos: se arman en una página
  /// de alto libre, que el motor recorta al alto exacto del contenido.
  static Future<double> _medirAlto(
    pw.ThemeData? theme,
    double ancho,
    List<pw.Widget> Function() construir,
  ) async {
    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(ancho, double.infinity),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: construir(),
        ),
      ),
    );
    await doc.save();
    return doc.document.pdfPageList.pages.first.pageFormat.height;
  }

  /// "playón de 30 m de frente, 46 m de fondo y 39,8 m de costado". Solo si
  /// el salón se armó a medida en una hoja: es lo que se mide con la cinta.
  static String? _textoPlayon(
    ArmadoSalon armado,
    HojaPlano hoja,
    bool aproximado,
  ) {
    final borde = hoja.contorno;
    if (borde == null || armado.hojas.length != 1) return null;
    final acostados = <({double y, double largo})>[];
    final costados = <double>[];
    for (final (a, b) in borde.lados) {
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final largo = armado.aMetros(math.sqrt(dx * dx + dy * dy));
      if (dx.abs() >= dy.abs()) {
        acostados.add((y: (a.y + b.y) / 2, largo: largo));
      } else {
        costados.add(largo);
      }
    }
    if (acostados.length != 2 || costados.isEmpty) return null;
    acostados.sort((a, b) => a.y.compareTo(b.y));
    final lados = costados.map(MedirSalon.metros).toSet().join(' y ');
    return 'playón de ${MedirSalon.metros(acostados.first.largo)} de frente, '
        '${MedirSalon.metros(acostados.last.largo)} de fondo y $lados de '
        'costado${aproximado ? ' (medidas aproximadas)' : ''}';
  }

  // ── Una mesa ────────────────────────────────────────────────────────────

  /// Dibuja una mesa con centro en ([cx], [cy]) y radio [r], en puntos. La usan
  /// el plano y la leyenda del pie, para que el símbolo sea el mismo.
  ///
  /// El color y el grosor se ponen siempre **antes** de trazar cada figura: en
  /// un PDF no se pueden cambiar a mitad de un trazo.
  static void _mesa(
    PdfGraphics g, {
    required double cx,
    required double cy,
    required double r,
    required double escala,
    required EstiloPlano estilo,
    required _Tinta tinta,
    required bool llena,
    required int? division,
    required bool conflicto,
    required bool libre,
    required bool fijada,
    required bool pasto,
    required int sillasExtra,
    required bool conSillas,
    double? grosor,
  }) {
    // Los trazos acompañan al tamaño de la mesa, sin pasarse.
    final k = grosor ?? (r / 12).clamp(0.55, 1.3);
    final trazo = llena ? tinta.trazo(division) : tinta.trazoVacia;

    if (conSillas) {
      void silla(double angulo) {
        final nx = math.cos(angulo), ny = math.sin(angulo);
        final px = cx + nx * (r + 9 * escala);
        final py = cy + ny * (r + 9 * escala);
        final a = 6 * escala, b = 3.5 * escala;
        g
          ..moveTo(px - ny * a - nx * b, py + nx * a - ny * b)
          ..lineTo(px + ny * a - nx * b, py - nx * a - ny * b)
          ..lineTo(px + ny * a + nx * b, py - nx * a + ny * b)
          ..lineTo(px - ny * a + nx * b, py + nx * a + ny * b)
          ..closePath();
      }

      g
        ..setFillColor(tinta.silla)
        ..setStrokeColor(tinta.sillaBorde)
        ..setLineWidth(0.3 * k);
      for (var i = 0; i < 8; i++) {
        silla(math.pi / 8 + i * math.pi / 4);
        g.fillAndStrokePath();
      }
      // Las de más, en los huecos de los costados, llenas.
      g.setFillColor(_Tinta.negro);
      for (var i = 0; i < sillasExtra.clamp(0, 2); i++) {
        silla(i == 0 ? 0 : math.pi);
        g.fillPath();
      }
    } else {
      // Sin las ocho sillas, las de más se marcan con un punto al costado.
      final rPunto = math.max(1.1, r * 0.17);
      for (var i = 0; i < sillasExtra.clamp(0, 2); i++) {
        final px = cx + (i == 0 ? 1 : -1) * (r + rPunto * 1.3);
        g
          ..setFillColor(_Tinta.blanco)
          ..drawEllipse(px, cy, rPunto * 1.35, rPunto * 1.35)
          ..fillPath()
          ..setFillColor(_Tinta.negro)
          ..drawEllipse(px, cy, rPunto, rPunto)
          ..fillPath();
      }
    }

    g
      ..setFillColor(llena ? tinta.relleno(division) : _Tinta.blanco)
      ..drawEllipse(cx, cy, r, r)
      ..fillPath();

    if (pasto) {
      // Rayada: se lee igual en blanco y negro.
      final paso = math.max(1.6, r * 0.34);
      g
        ..saveContext()
        ..drawEllipse(cx, cy, r, r)
        ..clipPath()
        ..setStrokeColor(tinta.pasto)
        ..setLineWidth(0.45 * k);
      for (var d = -2 * r; d <= 2 * r; d += paso) {
        g.drawLine(cx + d - r, cy - r, cx + d + r, cy + r);
      }
      g
        ..strokePath()
        ..restoreContext();
    }

    final ancho = conflicto
        ? 2.2 * k
        : switch (estilo) {
            EstiloPlano.gala => (llena ? 1.2 : 0.6) * k,
            EstiloPlano.arquitecto => (llena ? 0.9 : 0.6) * k,
            EstiloPlano.neon => (llena ? 1.9 : 0.8) * k,
          };
    g
      ..setStrokeColor(conflicto ? _Tinta.negro : trazo)
      ..setLineWidth(ancho);
    if (libre) g.setLineDashPattern([2.2 * k, 1.6 * k]);
    g
      ..drawEllipse(cx, cy, r, r)
      ..strokePath();
    if (libre) g.setLineDashPattern();

    // Gala: el anillo doble de las mesas con familia.
    if (estilo == EstiloPlano.gala && llena && !conflicto && r > 5) {
      g
        ..setLineWidth(0.4 * k)
        ..drawEllipse(cx, cy, r - 1.9 * k, r - 1.9 * k)
        ..strokePath();
    }

    if (libre) {
      g
        ..setStrokeColor(tinta.trazoVacia)
        ..setLineWidth(0.8 * k)
        ..drawLine(cx - r * 0.62, cy - r * 0.62, cx + r * 0.62, cy + r * 0.62)
        ..strokePath();
    }

    if (fijada) {
      // El candado, a las once.
      final x = cx - r * 0.72, y = cy + r * 0.72;
      final a = math.max(1.5, r * 0.2);
      g
        ..setFillColor(_Tinta.blanco)
        ..drawEllipse(x, y, a * 1.75, a * 1.75)
        ..fillPath()
        ..setStrokeColor(_Tinta.negro)
        ..setLineWidth(a * 0.34)
        ..moveTo(x - a * 0.55, y)
        ..curveTo(x - a * 0.55, y + a * 1.35, x + a * 0.55, y + a * 1.35,
            x + a * 0.55, y)
        ..strokePath()
        ..setFillColor(_Tinta.negro)
        ..drawRect(x - a, y - a * 0.95, a * 2, a * 1.2)
        ..fillPath();
    }

    if (conflicto) {
      // Un signo de admiración, a la una.
      final x = cx + r * 0.72, y = cy + r * 0.72;
      final a = math.max(1.6, r * 0.24);
      g
        ..setFillColor(_Tinta.negro)
        ..drawEllipse(x, y, a * 1.5, a * 1.5)
        ..fillPath()
        ..setFillColor(_Tinta.blanco)
        ..drawRect(x - a * 0.2, y - a * 0.25, a * 0.4, a * 1.1)
        ..fillPath()
        ..drawRect(x - a * 0.2, y - a * 0.9, a * 0.4, a * 0.4)
        ..fillPath();
    }
  }
}

/// Texto que la letra puede escribir: lo que no tiene se cambia por "?". Sin
/// esto, un apellido con un signo raro frenaría el PDF entero.
String _seguro(PdfFont f, String texto) {
  final b = StringBuffer();
  for (final r in texto.runes) {
    b.writeCharCode(f.isRuneSupported(r) ? r : 0x3F);
  }
  return b.toString();
}

/// Una hoja del plano, dibujada. Ocupa todo el lugar que le dan y encuadra
/// adentro lo que decidió [_HojaPapel].
class _DibujoPlano extends pw.Widget {
  _DibujoPlano({
    required this.armado,
    required this.hoja,
    required this.estado,
    required this.estilo,
    required this.tinta,
    required this.bloques,
    required this.letraNumeros,
    required this.letraApellidos,
    required this.letraEtiquetas,
  });

  final ArmadoSalon armado;
  final _HojaPapel hoja;
  final EstadoPlano estado;
  final EstiloPlano estilo;
  final _Tinta tinta;
  final List<BloqueDivision> bloques;
  final pw.Font letraNumeros;
  final pw.Font letraApellidos;
  final pw.Font letraEtiquetas;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    final ancho = constraints.hasBoundedWidth ? constraints.maxWidth : 800.0;
    final alto =
        constraints.hasBoundedHeight ? constraints.maxHeight : ancho / 1.6;
    box = PdfRect(0, 0, ancho, alto);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final g = context.canvas;
    final caja = box!;
    final marco = hoja.marco;
    // La escala se vuelve a sacar del lugar real: si el dibujo recibiera
    // menos lugar del previsto, se achica en vez de recortarse.
    final s = math.min(caja.width / marco.ancho, caja.height / marco.alto);
    // Centrado a lo ancho y pegado arriba: una hoja con pocas filas no queda
    // flotando en el medio del papel.
    final ox = caja.left + (caja.width - marco.ancho * s) / 2 - marco.x * s;
    final oy = caja.top + marco.y * s;
    double px(double x) => ox + x * s;
    double py(double y) => oy - y * s;

    final fNumeros = letraNumeros.getFont(context);
    final fApellidos = letraApellidos.getFont(context);
    final fEtiquetas = letraEtiquetas.getFont(context);
    final tema = TemaPlano.de(estilo);
    final conSillas = PlanoPdf._conSillas(estilo, s);
    final r = armado.radio * tema.escalaMesa * s;
    final ocupa = PlanoPdf.ocupa(armado, estilo, s);
    final paso = PlanoPapel.pasoHorizontal(armado, hoja.hoja.id);
    // Entre el apellido de una mesa y el de la de al lado queda aire.
    final anchoApellido = (paso ?? armado.radio * 3) * 0.86;
    // Una sola medida de letra para toda la hoja: la que deja entrar un
    // apellido de nueve letras, sin pasar de la que entra a lo alto.
    final tamApellido = hoja.tamApellido == 0
        ? 0.0
        : math.max(
            hoja.tamApellido * 0.8,
            math.min(
              hoja.tamApellido,
              anchoApellido *
                  s /
                  fApellidos.stringMetrics('DOMINGUEZ').advanceWidth,
            ),
          );

    g
      ..saveContext()
      ..drawRect(px(marco.x), py(marco.abajo), marco.ancho * s, marco.alto * s)
      ..clipPath();

    // ── El hormigón ─────────────────────────────────────────────────────
    final borde = hoja.hoja.contorno;
    if (borde != null) {
      g
        ..setFillColor(tinta.hormigon)
        ..setStrokeColor(tinta.hormigonBorde)
        ..setLineWidth(0.9);
      for (final (i, p) in borde.puntos.indexed) {
        if (i == 0) {
          g.moveTo(px(p.x), py(p.y));
        } else {
          g.lineTo(px(p.x), py(p.y));
        }
      }
      g
        ..closePath()
        ..fillAndStrokePath();
    }

    // ── Sectores ────────────────────────────────────────────────────────
    final sectores = armado.sectoresDeHoja(hoja.hoja.id);
    bool esEscena(SectorPlano x) =>
        x.tipo == TipoSector.escenario || x.tipo == TipoSector.pasarela;
    for (final sec in sectores) {
      final c = sec.caja;
      final radio = math.min(
        (esEscena(sec) ? 6 : 14) * s,
        math.min(c.ancho, c.alto) * s / 2,
      );
      if (esEscena(sec)) {
        // Sin borde: el escenario y la pasarela quedan como una sola figura.
        g
          ..setFillColor(tinta.escenario)
          ..drawRRect(px(c.x), py(c.abajo), c.ancho * s, c.alto * s, radio, radio)
          ..fillPath();
      } else {
        g
          ..setFillColor(tinta.sector)
          ..setStrokeColor(tinta.sectorBorde)
          ..setLineWidth(0.5)
          ..drawRRect(px(c.x), py(c.abajo), c.ancho * s, c.alto * s, radio, radio)
          ..fillAndStrokePath();
      }
    }
    for (final sec in sectores) {
      _rotulo(g, fApellidos, sec, s, px, py,
          esEscena(sec) ? _Tinta.blanco : tinta.sectorTexto);
    }

    // ── Mesas ───────────────────────────────────────────────────────────
    final mesas = armado.mesasDeHoja(hoja.hoja.id);
    bool llevaApellido(int n) {
      final i = estado.info(n);
      return i.principal && (i.ocupante ?? i.fijadaPara) != null;
    }

    for (final m in mesas) {
      final info = estado.info(m.numero);
      final llena = info.estado == EstadoMesa.ocupada ||
          info.estado == EstadoMesa.fijada ||
          info.estado == EstadoMesa.conflicto;
      final cx = px(m.x), cy = py(m.y);
      PlanoPdf._mesa(
        g,
        cx: cx,
        cy: cy,
        r: r,
        escala: s,
        estilo: estilo,
        tinta: tinta,
        llena: llena,
        division: info.division,
        conflicto: info.estado == EstadoMesa.conflicto,
        libre: info.libre,
        fijada: info.fijadaPara != null,
        pasto: m.pasto,
        sillasExtra: info.sillasExtra,
        conSillas: conSillas,
      );

      // El número, lo más grande que entra.
      final texto = '${m.numero}';
      final ancho = fNumeros.stringMetrics(texto).advanceWidth;
      var tam = r;
      if (ancho * tam > r * 1.42) tam = r * 1.42 / ancho;
      final color = llena ? tinta.trazo(info.division) : tinta.numeroVacia;
      if (m.pasto) {
        // Sobre el rayado, un fondo blanco para que el número se lea.
        final w = ancho * tam + tam * 0.3, h = tam * 0.95;
        g
          ..setFillColor(_Tinta.blanco)
          ..drawRRect(cx - w / 2, cy - h / 2, w, h, tam * 0.2, tam * 0.2)
          ..fillPath();
      }
      _escribir(g, fNumeros, texto, tam, cx, cy, color, referencia: '0');

      if (tamApellido > 0 && llevaApellido(m.numero)) {
        final familia = info.ocupante ?? info.fijadaPara!;
        final franja = PlanoPapel.franjaApellido(
          m,
          ocupa: ocupa,
          ancho: anchoApellido,
          alto: tamApellido / s,
        );
        var apellido = _seguro(fApellidos, familia.apellido);
        var tamEste = tamApellido;
        final maximo = franja.ancho * s;
        final medido = fApellidos.stringMetrics(apellido).advanceWidth * tamEste;
        // Si no entra, primero se achica (hasta el 85 %) y después se corta.
        if (medido > maximo) {
          tamEste = math.max(tamApellido * 0.85, tamEste * maximo / medido);
          apellido = _recortar(fApellidos, apellido, tamEste, maximo);
        }
        // Sin salirse de lo que se ve.
        final mitad =
            fApellidos.stringMetrics(apellido).advanceWidth * tamEste / 2;
        final desde = px(marco.x) + mitad + 1;
        final hasta = math.max(desde, px(marco.derecha) - mitad - 1);
        _escribir(
          g,
          fApellidos,
          apellido,
          tamEste,
          cx.clamp(desde, hasta).toDouble(),
          py(franja.centroY),
          tinta.apellido,
          referencia: 'H',
        );
      }
    }

    // ── El nombre de cada división, sobre su bloque ─────────────────────
    final tamEtiqueta = math.max(5.5, math.min(7.5, r * 0.55));
    final etiquetas = PlanoPapel.etiquetas(
      armado: armado,
      hoja: hoja.hoja.id,
      estado: estado,
      bloques: bloques,
      marco: marco,
      ocupa: ocupa,
      // Puede tapar la punta de una silla, no la mesa.
      despeje: armado.radio * tema.escalaMesa + 4,
      alto: tamEtiqueta * 1.35 / s,
      ancho: (t) =>
          (fEtiquetas.stringMetrics(_seguro(fEtiquetas, t)).advanceWidth *
                  tamEtiqueta +
              tamEtiqueta * 1.1) /
          s,
      llevaApellido: llevaApellido,
      anchoApellido: anchoApellido,
      altoApellido: tamApellido / s,
    );
    for (final e in etiquetas) {
      final c = e.caja;
      final radio = c.alto * s / 2;
      g
        ..setFillColor(_Tinta.negro)
        ..setStrokeColor(_Tinta.blanco)
        ..setLineWidth(0.8)
        ..drawRRect(px(c.x), py(c.abajo), c.ancho * s, c.alto * s, radio, radio)
        ..fillAndStrokePath();
      _escribir(g, fEtiquetas, _seguro(fEtiquetas, e.texto), tamEtiqueta,
          px(c.centroX), py(c.centroY), _Tinta.blanco,
          referencia: 'H');
    }

    // ── Lo que mide cada lado, si el hormigón entra entero ──────────────
    if (borde != null) _cotas(g, fEtiquetas, borde, marco, sectores, s, px, py);

    g.restoreContext();

    // El borde de lo que se ve.
    g
      ..setStrokeColor(tinta.marco)
      ..setLineWidth(0.4)
      ..drawRect(px(marco.x), py(marco.abajo), marco.ancho * s, marco.alto * s)
      ..strokePath();
  }

  /// Escribe [texto] centrado en ([cx], [cy]). [referencia] es con qué se
  /// centra a lo alto ("0" para números, "H" para mayúsculas): así todos los
  /// renglones quedan a la misma altura, tengan tilde o no.
  void _escribir(
    PdfGraphics g,
    PdfFont f,
    String texto,
    double tam,
    double cx,
    double cy,
    PdfColor color, {
    required String referencia,
    double espaciado = 0,
  }) {
    if (texto.isEmpty || tam <= 0) return;
    final m = f.stringMetrics(texto);
    final ref = f.stringMetrics(referencia);
    final ancho = m.advanceWidth * tam + espaciado * (texto.runes.length - 1);
    g
      ..setFillColor(color)
      ..drawString(
        f,
        tam,
        texto,
        cx - ancho / 2,
        cy - (ref.top + ref.bottom) / 2 * tam,
        charSpace: espaciado == 0 ? null : espaciado,
      );
  }

  /// Corta [texto] con "…" hasta que entre en [maximo] puntos.
  String _recortar(PdfFont f, String texto, double tam, double maximo) {
    if (f.stringMetrics(texto).advanceWidth * tam <= maximo) return texto;
    final puntos = f.isRuneSupported(0x2026) ? '…' : '.';
    final runas = texto.runes.toList();
    while (runas.length > 1) {
      runas.removeLast();
      final corto = '${String.fromCharCodes(runas).trimRight()}$puntos';
      if (f.stringMetrics(corto).advanceWidth * tam <= maximo) return corto;
    }
    return String.fromCharCodes(runas);
  }

  void _rotulo(
    PdfGraphics g,
    PdfFont f,
    SectorPlano sec,
    double s,
    double Function(double) px,
    double Function(double) py,
    PdfColor color,
  ) {
    if (sec.texto.trim().isEmpty) return;
    final texto = _seguro(
      f,
      estilo == EstiloPlano.neon ? sec.texto : sec.texto.toUpperCase(),
    );
    final alto = (sec.vertical ? sec.caja.ancho : sec.caja.alto) * s;
    final largo = (sec.vertical ? sec.caja.alto : sec.caja.ancho) * s;
    var tam = math.min(11.0, alto * 0.5);
    final letras = texto.runes.length;
    double anchoCon(double t) =>
        f.stringMetrics(texto).advanceWidth * t + t * 0.1 * (letras - 1);
    final entra = largo * 0.9;
    if (anchoCon(tam) > entra) tam *= entra / anchoCon(tam);
    if (tam < 3.2) return;
    final cx = px(sec.caja.centroX), cy = py(sec.caja.centroY);
    if (!sec.vertical) {
      _escribir(g, f, texto, tam, cx, cy, color,
          referencia: 'H', espaciado: tam * 0.1);
      return;
    }
    g
      ..saveContext()
      ..setTransform(
        Matrix4.identity()
          ..translateByDouble(cx, cy, 0, 1)
          ..rotateZ(math.pi / 2),
      );
    _escribir(g, f, texto, tam, 0, 0, color,
        referencia: 'H', espaciado: tam * 0.1);
    g.restoreContext();
  }

  /// El largo de cada lado del hormigón, del lado de afuera. Un lado que el
  /// recorte corta, o cuyo número no entra en lo que se ve, no lleva nada: lo
  /// dice el encabezado.
  void _cotas(
    PdfGraphics g,
    PdfFont f,
    ContornoPlano borde,
    RectPlano marco,
    List<SectorPlano> sectores,
    double s,
    double Function(double) px,
    double Function(double) py,
  ) {
    const tam = 7.0;
    final altoU = tam / s;
    var cx = 0.0, cy = 0.0;
    for (final p in borde.puntos) {
      cx += p.x / borde.puntos.length;
      cy += p.y / borde.puntos.length;
    }
    bool adentro(({double x, double y}) p) =>
        p.x >= marco.x - 0.5 &&
        p.x <= marco.derecha + 0.5 &&
        p.y >= marco.y - 0.5 &&
        p.y <= marco.abajo + 0.5;
    for (final (a, b) in borde.lados) {
      final dx = b.x - a.x, dy = b.y - a.y;
      final largo = math.sqrt(dx * dx + dy * dy);
      if (largo < 1 || !adentro(a) || !adentro(b)) continue;
      var nx = -dy / largo, ny = dx / largo;
      final mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
      // La normal que se aleja del centro.
      if ((mx - cx) * nx + (my - cy) * ny < 0) {
        nx = -nx;
        ny = -ny;
      }
      final texto = MedirSalon.metros(armado.aMetros(largo));
      final ancho = f.stringMetrics(texto).advanceWidth * tam / s;
      final x = mx + nx * (altoU * 0.9 + ancho / 2 * nx.abs());
      var y = my + ny * altoU * 0.9;
      // Si cae sobre un sector (el escenario está pegado al frente), va del
      // otro lado del sector.
      for (final sec in sectores) {
        final c = sec.caja;
        if (x < c.x - 4 || x > c.derecha + 4 || y < c.y - 4 || y > c.abajo + 4) {
          continue;
        }
        if (ny < -0.9) y = c.y - altoU * 0.9;
        if (ny > 0.9) y = c.abajo + altoU * 0.9;
      }
      if (x - ancho / 2 < marco.x ||
          x + ancho / 2 > marco.derecha ||
          y - altoU / 2 < marco.y ||
          y + altoU / 2 > marco.abajo) {
        continue;
      }
      _escribir(g, f, texto, tam, px(x), py(y), tinta.sectorTexto,
          referencia: '0');
    }
  }
}
