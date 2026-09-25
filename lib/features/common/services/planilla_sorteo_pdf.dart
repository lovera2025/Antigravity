import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/evento.dart';
import '../../../models/nota_operativa_contrato.dart';
import '../../../models/sillas_reparto.dart';
import '../../eventos/services/pago_para_sorteo.dart';
import '../../eventos/services/planilla_sorteo.dart';
import '../../eventos/services/salon_mesas.dart';
import 'planilla_tema.dart';

/// Una parte del documento con su propio encabezado y su numeración: el
/// resumen, o una división.
typedef _Seccion = ({
  String nombre,
  pw.Widget Function() encabezado,
  List<pw.Widget> Function() contenido,
});

/// El papel de la planilla del sorteo de mesas.
///
/// Las filas las arma [PlanillaSorteo] (lógica pura, con tests). Acá solo se
/// ponen en la hoja:
/// - **primera hoja, el resumen del salón:** totales, divisiones con sus
///   números y, en la interna, a quién llamar por el reparto de sillas;
/// - **después, una hoja por división**, A4 acostada, para repartirlas por
///   separado. Si una división no entra, sigue en la hoja siguiente con los
///   títulos de las columnas repetidos, y el pie dice "5° A · hoja 2 de 2".
///
/// Respeta la planilla que ya usa el jefe: primero sus columnas y en su orden
/// (egresado, acompañante, mesa principal, adicional, sillas), la mesa principal
/// en verde y la fila roja cuando no tiene mesa. Cada color lleva su palabra,
/// así que en blanco y negro se lee igual.
///
/// No hay fila amarilla: se pintaba con cualquier nota sin resolver, que suelen
/// ser de cobro y no de la fiesta. La nota sigue en Observaciones (interna).
class PlanillaSorteoPdf {
  PlanillaSorteoPdf._();

  static final PdfPageFormat _formato = PdfPageFormat.a4.landscape;

  /// Hasta cuántos para llamar entran en dos columnas en la hoja de resumen.
  /// Con más, va una sola tabla que puede seguir en la hoja siguiente.
  static const _maxLlamarEnDosColumnas = 28;

  /// Títulos de las columnas de cada división según la versión.
  static List<String> columnas(VersionPlanillaSorteo version) {
    final interna = version == VersionPlanillaSorteo.interna;
    return [
      'Egresado',
      'Acompañantes',
      'Mesa principal',
      'Adicional',
      'Sillas',
      'Reparto',
      if (interna) 'Teléfono',
      'Música',
      if (interna) 'Observaciones',
    ];
  }

  static List<double> _anchos(VersionPlanillaSorteo version) =>
      version == VersionPlanillaSorteo.interna
          ? const [2.2, 2.1, 1.45, 1.3, 0.85, 1.05, 1.2, 1.1, 2.1]
          : const [2.6, 2.6, 1.55, 1.5, 1.0, 1.15, 1.6];

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static Future<Uint8List> construir({
    required Evento evento,
    required List<ContratoAlumno> alumnos,
    Map<String, PagoAlumno>? pagos,
    Map<String, NotaOperativaContrato> notas = const {},
    Map<String, SillasReparto> repartos = const {},
    String? lineaSorteo,
    VersionPlanillaSorteo version = VersionPlanillaSorteo.interna,
    bool blancoYNegro = false,
    pw.Font? regular,
    pw.Font? negrita,
    DateTime? generada,
  }) async {
    final tema = PlanillaTema(blancoYNegro: blancoYNegro);
    final interna = version == VersionPlanillaSorteo.interna;
    final theme = regular != null && negrita != null
        ? pw.ThemeData.withFont(base: regular, bold: negrita)
        : null;

    final institucion = evento.cliente?.nombreCompleto ?? 'EVENTO';
    final cuando = generada ?? ArTime.nowAr();
    final textoGenerada = 'Generada el ${_dos(cuando.day)}/${_dos(cuando.month)}/'
        '${cuando.year} · ${_dos(cuando.hour)}:${_dos(cuando.minute)}';
    final textoVersion = interna ? 'Versión interna' : 'Para repartir';
    final leyenda = <(PdfColor?, String)>[
      if (!blancoYNegro) ...[
        (tema.verdeMesa, 'Mesa principal'),
        (tema.rojoSinMesa, 'Sin mesa'),
      ],
      (null, 'Sillas: P en la principal, A en la adicional'),
    ];

    final resumen = PlanillaSorteo.resumen(
      alumnos,
      pagos: pagos,
      notas: notas,
      repartos: repartos,
    );
    final divisiones = PlanillaSorteo.porDivision(
      alumnos,
      pagos: pagos,
      notas: notas,
      repartos: repartos,
    );

    final secciones = <_Seccion>[
      (
        nombre: 'Resumen',
        encabezado: () => tema.encabezado(
              titulo: 'Planilla del sorteo · Resumen del salón',
              institucion: institucion,
              version: textoVersion,
              generada: textoGenerada,
              extra: lineaSorteo,
            ),
        contenido: () => _resumen(tema, resumen, interna),
      ),
      for (final entrada in divisiones.entries)
        (
          nombre: entrada.key,
          encabezado: () => tema.encabezado(
                titulo: 'Planilla del sorteo · ${entrada.key}',
                institucion: institucion,
                version: textoVersion,
                generada: textoGenerada,
                extra: lineaSorteo,
                control: _control(
                  resumen.divisiones.firstWhere((d) => d.division == entrada.key),
                ),
              ),
          contenido: () => [_tablaDivision(tema, entrada.value, version)],
        ),
    ];

    pw.MultiPage pagina(_Seccion s, {required int inicio, int? total}) =>
        pw.MultiPage(
          pageFormat: _formato,
          margin: const pw.EdgeInsets.all(PlanillaTema.margen),
          maxPages: 200,
          header: (_) => s.encabezado(),
          footer: (context) => tema.pie(
            leyenda: leyenda,
            paginacion: '${s.nombre} · hoja ${context.pageNumber - inicio + 1} '
                'de ${total ?? '-'}',
          ),
          build: (_) => s.contenido(),
        );

    // La numeración va por sección, y el contexto no sabe cuántas hojas va a
    // tener cada una: primero se arma cada sección sola para contarlas. Los
    // widgets del paquete guardan estado de layout, así que cada pasada los
    // construye de nuevo.
    final hojas = <int>[];
    for (final s in secciones) {
      final prueba = pw.Document(theme: theme);
      prueba.addPage(pagina(s, inicio: 1));
      await prueba.save();
      hojas.add(prueba.document.pdfPageList.pages.length);
    }

    final doc = pw.Document(
      theme: theme,
      title: 'Planilla del sorteo',
      author: 'Junior Eventos',
    );
    var inicio = 1;
    for (var i = 0; i < secciones.length; i++) {
      doc.addPage(pagina(secciones[i], inicio: inicio, total: hojas[i]));
      inicio += hojas[i];
    }
    return doc.save();
  }

  static int _tramos(String numeros) =>
      numeros == '-' ? 0 : '·'.allMatches(numeros).length + 1;

  /// Los números de una división para el resumen. Con el sorteo por bloques
  /// son uno o dos tramos ("1-24"); mientras se sortee la institución entera
  /// quedan salpicados, y una lista de veinte tramos no le dice nada a nadie.
  static String _numerosCortos(String numeros) {
    final n = _tramos(numeros);
    return n <= 4 ? numeros : 'en $n tramos (ver cada división)';
  }

  /// La línea de totales de una división. Los números van solo si son pocos
  /// tramos.
  static String _control(ResumenDivision r) {
    final n = _tramos(r.numeros);
    return '${r.egresados} egresados · ${r.mesas} mesas'
        '${n > 0 && n <= 4 ? ' (${r.numeros})' : ''}'
        ' · ${r.sillasExtra} sillas extra · ${r.conCena} con cena';
  }

  // ── Resumen del salón ──────────────────────────────────────────────────

  static pw.Widget _num(PlanillaTema t, String s) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: pw.Text(s, textAlign: pw.TextAlign.right, style: t.estilo()),
      );

  static pw.Widget _txt(PlanillaTema t, String s, {bool negrita = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: pw.Text(s, style: t.estilo(negrita: negrita)),
      );

  static pw.BoxDecoration? _alterna(PlanillaTema t, int i) =>
      i.isOdd && t.filaAlterna != null
          ? pw.BoxDecoration(color: t.filaAlterna)
          : null;

  static List<pw.Widget> _resumen(
    PlanillaTema t,
    ResumenPlanillaSorteo r,
    bool interna,
  ) {
    final tarjetas = <pw.Widget>[
      t.tarjeta('Egresados', '${r.egresados}'),
      t.tarjeta(
        'Mesas',
        '${r.mesas}',
        detalle: r.mesasAsignadas < r.mesas
            ? '${r.mesasAsignadas} asignadas'
            : 'todas asignadas',
      ),
      t.tarjeta(
        'Sillas',
        '${SalonMesas.sillasPorMesa * r.mesas}',
        detalle: '${SalonMesas.sillasPorMesa} por mesa',
      ),
      t.tarjeta(
        'Sillas extra',
        '${r.sillasExtra - r.sillasSinPagar}',
        detalle: r.sillasSinPagar > 0 ? '+${r.sillasSinPagar} sin pagar' : null,
      ),
      t.tarjeta('Con cena', '${r.conCena}', detalle: 'egresados y acompañantes'),
      t.tarjeta('Sin mesa', '${r.sinMesa}', detalle: 'sin pagar la cuota base'),
      t.tarjeta(
        'Sillas a confirmar',
        '${r.repartosPendientes}',
        detalle: 'la familia tiene que elegir',
      ),
    ];

    return [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tarjetas.length; i++) ...[
            if (i > 0) pw.SizedBox(width: 6),
            pw.Expanded(child: tarjetas[i]),
          ],
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Text('Divisiones', style: t.estilo(size: 11, negrita: true)),
      pw.SizedBox(height: 5),
      if (r.divisiones.isEmpty)
        pw.Text('Todavía no hay egresados cargados.', style: t.estilo())
      else
        pw.Table(
          border: t.bordeTabla,
          columnWidths: const {
            0: pw.FlexColumnWidth(2.2),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(0.9),
            3: pw.FlexColumnWidth(2.6),
            4: pw.FlexColumnWidth(1),
            5: pw.FlexColumnWidth(1),
            6: pw.FlexColumnWidth(1.2),
            7: pw.FlexColumnWidth(0.9),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(color: t.fondoEncabezadoTabla),
              children: [
                t.celdaTitulo('División'),
                t.celdaTitulo('Egresados', align: pw.TextAlign.right),
                t.celdaTitulo('Mesas', align: pw.TextAlign.right),
                t.celdaTitulo('Números'),
                t.celdaTitulo('Sillas extra', align: pw.TextAlign.right),
                t.celdaTitulo('Con cena', align: pw.TextAlign.right),
                t.celdaTitulo('Reparto pendiente', align: pw.TextAlign.right),
                t.celdaTitulo('Sin mesa', align: pw.TextAlign.right),
              ],
            ),
            for (var i = 0; i < r.divisiones.length; i++)
              pw.TableRow(
                decoration: _alterna(t, i),
                children: [
                  _txt(t, r.divisiones[i].division, negrita: true),
                  _num(t, '${r.divisiones[i].egresados}'),
                  _num(t, '${r.divisiones[i].mesas}'),
                  _txt(t, _numerosCortos(r.divisiones[i].numeros)),
                  _num(t, '${r.divisiones[i].sillasExtra}'),
                  _num(t, '${r.divisiones[i].conCena}'),
                  _num(t, '${r.divisiones[i].repartosPendientes}'),
                  _num(t, '${r.divisiones[i].sinMesa}'),
                ],
              ),
          ],
        ),
      if (interna && r.aLlamar.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        // En dos columnas va todo junto (título, aclaración y tablas), así el
        // título nunca queda solo al pie de una hoja. Si son muchos, una sola
        // tabla que puede seguir en la hoja siguiente.
        if (r.aLlamar.length <= _maxLlamarEnDosColumnas)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              ..._tituloLlamar(t, r.aLlamar.length),
              () {
                final mitad = (r.aLlamar.length + 1) ~/ 2;
                return pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: _tablaLlamar(t, r.aLlamar.sublist(0, mitad)),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: mitad < r.aLlamar.length
                          ? _tablaLlamar(t, r.aLlamar.sublist(mitad))
                          : pw.SizedBox(),
                    ),
                  ],
                );
              }(),
            ],
          )
        else ...[
          ..._tituloLlamar(t, r.aLlamar.length),
          _tablaLlamar(t, r.aLlamar),
        ],
      ],
    ];
  }

  static List<pw.Widget> _tituloLlamar(PlanillaTema t, int cantidad) => [
        pw.Text(
          'A quién llamar por el reparto de sillas ($cantidad)',
          style: t.estilo(size: 11, negrita: true),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Tienen sillas extra y todavía no eligieron en qué mesa van. Hasta '
          'que elijan, la planilla las pone de a 2 por mesa, la principal '
          'primero.',
          style: t.estilo(color: t.textoSuave),
        ),
        pw.SizedBox(height: 5),
      ];

  static pw.Widget _tablaLlamar(
    PlanillaTema t,
    List<({FilaPlanillaSorteo fila, String division})> filas,
  ) {
    String mesas(FilaPlanillaSorteo f) =>
        f.adicional == '-' ? f.mesaPrincipal : '${f.mesaPrincipal} + ${f.adicional}';
    return pw.Table(
      border: t.bordeTabla,
      columnWidths: const {
        0: pw.FlexColumnWidth(2.2),
        1: pw.FlexColumnWidth(0.7),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(1.1),
        4: pw.FlexColumnWidth(1.3),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: t.fondoEncabezadoTabla),
          children: [
            t.celdaTitulo('Egresado'),
            t.celdaTitulo('Div.'),
            t.celdaTitulo('Sillas'),
            t.celdaTitulo('Mesas'),
            t.celdaTitulo('Teléfono'),
          ],
        ),
        for (var i = 0; i < filas.length; i++)
          pw.TableRow(
            decoration: _alterna(t, i),
            children: [
              _txt(t, filas[i].fila.egresado, negrita: true),
              _txt(t, filas[i].division),
              _txt(t, filas[i].fila.sillas),
              _txt(t, mesas(filas[i].fila)),
              _txt(t, filas[i].fila.telefono),
            ],
          ),
      ],
    );
  }

  // ── Una división ───────────────────────────────────────────────────────

  static pw.Widget _tablaDivision(
    PlanillaTema t,
    List<FilaPlanillaSorteo> filas,
    VersionPlanillaSorteo version,
  ) {
    final anchos = _anchos(version);
    final titulos = columnas(version);
    final interna = version == VersionPlanillaSorteo.interna;
    return pw.Table(
      border: t.bordeTabla,
      columnWidths: {
        for (var i = 0; i < anchos.length; i++) i: pw.FlexColumnWidth(anchos[i]),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: t.fondoEncabezadoTabla),
          children: [
            for (final c in titulos)
              t.celdaTitulo(
                c,
                align: c == 'Mesa principal' || c == 'Sillas'
                    ? pw.TextAlign.center
                    : pw.TextAlign.left,
              ),
          ],
        ),
        for (var i = 0; i < filas.length; i++) _fila(t, filas[i], i, interna),
      ],
    );
  }

  /// La celda de la mesa principal: el número grande y, al lado, en dos
  /// renglones chicos, cuántos tienen cena y cuántas generales.
  static pw.Widget _celdaMesa(PlanillaTema t, FilaPlanillaSorteo f) {
    if (int.tryParse(f.mesaPrincipal) == null) {
      if (f.sinMesa) {
        return pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              'SIN MESA',
              style: t.estilo(size: 8.5, negrita: true, color: t.rojo),
            ),
            pw.Text('sin pagar', style: t.estilo(size: 7.5, color: t.rojo)),
          ],
        );
      }
      return pw.Text(
        f.mesaPrincipal,
        textAlign: pw.TextAlign.center,
        style: t.estilo(size: 8.5, color: t.textoSuave),
      );
    }
    final g = f.generalesPrincipal;
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(f.mesaPrincipal, style: t.estilo(size: 12, negrita: true)),
        if (g != null) ...[
          pw.SizedBox(width: 5),
          pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${f.conCena} con cena',
                style: t.estilo(size: 7.5, color: t.textoSuave),
              ),
              pw.Text(
                g >= 0 ? '$g ${g == 1 ? 'general' : 'generales'}' : '(!) faltan ${-g}',
                style: t.estilo(
                  size: 7.5,
                  negrita: g < 0,
                  color: g >= 0 ? t.textoSuave : t.rojo,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static pw.TableRow _fila(
    PlanillaTema t,
    FilaPlanillaSorteo f,
    int indice,
    bool interna,
  ) {
    final fondo = f.sinMesa
        ? t.rojoSinMesa
        : indice.isOdd
            ? t.filaAlterna
            : null;

    pw.Widget celda(
      pw.Widget child, {
      PdfColor? color,
      pw.Alignment alineacion = pw.Alignment.topLeft,
    }) =>
        pw.Container(
          color: color,
          alignment: alineacion,
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
          child: child,
        );

    final reparto = switch (f.reparto) {
      RepartoSillas.noAplica => pw.Text('-', style: t.estilo(color: t.textoSuave)),
      RepartoSillas.pendiente => _marca(t, 'A confirmar', t.naranja),
      RepartoSillas.confirmado => _marca(t, 'Confirmado', t.verde),
    };

    return pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.full,
      decoration: fondo == null ? null : pw.BoxDecoration(color: fondo),
      children: [
        celda(pw.Text(f.egresado, style: t.estilo(negrita: true))),
        celda(
          f.acompanantes.isEmpty
              ? pw.Text(
                  'sin acompañantes cargados',
                  style: t.estilo(size: 8.5, color: t.textoSuave),
                )
              : pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (final n in f.acompanantes)
                      pw.Text(n, style: t.estilo()),
                  ],
                ),
        ),
        celda(
          _celdaMesa(t, f),
          color: int.tryParse(f.mesaPrincipal) != null ? t.verdeMesa : null,
          alineacion: pw.Alignment.center,
        ),
        celda(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(f.adicional, style: t.estilo()),
              if (f.alertaMesas != null)
                pw.Text(
                  f.alertaMesas!,
                  style: t.estilo(
                    size: PlanillaTema.secundario,
                    negrita: true,
                    color: t.naranja,
                  ),
                ),
            ],
          ),
        ),
        celda(
          pw.Text(
            f.sillas,
            textAlign: pw.TextAlign.center,
            style: t.estilo(negrita: f.sillas != '-'),
          ),
          alineacion: pw.Alignment.topCenter,
        ),
        celda(reparto),
        if (interna) celda(pw.Text(f.telefono, style: t.estilo())),
        celda(pw.Text(f.musica, style: t.estilo())),
        if (interna)
          celda(
            f.observaciones.isNotEmpty
                ? pw.Text(f.observaciones, style: t.estilo())
                : pw.Text('-', style: t.estilo(color: t.textoSuave)),
          ),
      ],
    );
  }

  /// Un estado con su punto de color y su palabra: en blanco y negro manda la
  /// palabra.
  static pw.Widget _marca(PlanillaTema t, String texto, PdfColor color) => pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 6,
            height: 6,
            decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
          ),
          pw.SizedBox(width: 4),
          pw.Text(texto, style: t.estilo(negrita: true, color: color)),
        ],
      );
}
