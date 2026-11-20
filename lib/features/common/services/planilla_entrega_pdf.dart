import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/entrega_entradas.dart';
import '../../../models/evento.dart';
import '../../eventos/services/entrega_por_partes.dart';
import '../../eventos/services/planilla_sorteo.dart';
import '../../eventos/services/retiro_entradas.dart';
import 'planilla_tema.dart';

typedef _Seccion = ({
  String nombre,
  pw.Widget Function() encabezado,
  List<pw.Widget> Function(double altoRenglon) contenido,
});

/// La planilla de entrega **de un material**: una hoja A4 acostada por
/// división, para tener en el mostrador el día que se entrega.
///
/// Desde el 20-nov-2026 la entrega sin cargo va en dos partes, cada una cuando
/// llega su material, y cada una con su planilla:
/// - **Pulseras VIP con cena** (el egresado y sus acompañantes): cuántas, los
///   menores de 10, quién retira y "Retiró".
/// - **Entradas generales** (las que completan las 8 de la mesa del contrato):
///   cuántas, "del … al …" (o "-" si vinieron sin número), quién retira y
///   "Retiró".
///
/// Es el registro en papel que acompaña al de la app. Quien retira **escribe su
/// nombre y apellido** en su renglón: no se firma, porque una firma la dibuja
/// cualquiera. A quien no se le puede entregar se le imprime por qué ("Debe: no
/// entregar") en ese mismo lugar.
///
/// Las filas las arma [EntregaPorPartes.filaPlanilla] (lógica pura, con tests).
class PlanillaEntregaPdf {
  PlanillaEntregaPdf._();

  static final PdfPageFormat _formato = PdfPageFormat.a4.landscape;

  /// Las columnas de cada material.
  static List<String> columnas(ParteEntrega material) =>
      material == ParteEntrega.pulseras
          ? const [
              'Egresado',
              'Mesa',
              'VIP',
              'Menores de 10',
              'Parentesco',
              'Nombre y apellido de quien retira',
              'Retiró',
            ]
          : const [
              'Egresado',
              'Mesa',
              'Generales',
              'Del … al …',
              'Parentesco',
              'Nombre y apellido de quien retira',
              'Retiró',
            ];

  /// Cuánto de ancho le toca a cada columna (en proporción). La del nombre es
  /// la más ancha, para que no se partan dos cosas:
  /// - "RETIRÓ" necesita ~30 pt de ancho útil (con 0.55 de 11.2 salía
  ///   "RETIR / Ó"; acá hay menos columnas y le toca más);
  /// - "Hermano/a mayor" necesita ~75 pt: en dos líneas el renglón crecía y una
  ///   división de 26 ya no entraba en una hoja.
  ///
  /// En las generales, "GENERALES" con 0.75 salía "GENERALE / S" (revisión del
  /// 20-nov-2026): le toca 0.95, que salen de "Del … al …". Ningún título parte
  /// una palabra: `test/retiro_entradas_test.dart` lo mide con las letras de la
  /// app.
  static List<double> anchos(ParteEntrega material) =>
      material == ParteEntrega.pulseras
          ? const [2.6, 0.8, 0.55, 0.85, 1.3, 3.2, 0.6]
          : const [2.6, 0.8, 0.95, 1.55, 1.3, 2.6, 0.6];

  /// El margen de la hoja, a cada lado.
  static const double margenDeLaHoja = PlanillaTema.margen;

  /// El ancho de la hoja (A4 acostada).
  static double get anchoDeLaHoja => _formato.width;

  /// Alto mínimo de cada renglón: tiene que entrar un nombre escrito a mano.
  static const double altoRenglon = 19;

  /// El renglón justo, que se usa solo si con él la división ocupa una hoja
  /// menos (ver [altoParaDivision]). Sigue alcanzando para escribir.
  static const double altoRenglonJusto = 17;

  /// Se ahorra papel sin quitarle lugar a la escritura cuando no hace falta: el
  /// renglón se achica solo si así la división entra en menos hojas.
  static double altoParaDivision({
    required int hojasNormal,
    required int hojasJusto,
  }) =>
      hojasJusto < hojasNormal ? altoRenglonJusto : altoRenglon;

  /// "Pulseras VIP" o "Generales": cómo se nombra cada planilla.
  static String nombreDelMaterial(ParteEntrega material) =>
      material == ParteEntrega.pulseras ? 'Pulseras VIP' : 'Generales';

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static Future<Uint8List> construir({
    required Evento evento,
    required List<ContratoAlumno> alumnos,
    required ParteEntrega material,
    required Map<String, EntradasRetiro> retiros,
    List<EntregaEntradas> renglones = const [],
    required Map<String, DeudaAlumno> deudas,
    bool blancoYNegro = false,
    pw.Font? regular,
    pw.Font? negrita,
    DateTime? generada,
  }) async {
    final tema = PlanillaTema(blancoYNegro: blancoYNegro);
    final theme = regular != null && negrita != null
        ? pw.ThemeData.withFont(base: regular, bold: negrita)
        : null;
    final pulseras = material == ParteEntrega.pulseras;
    final queEs = nombreDelMaterial(material);

    final institucion = evento.cliente?.nombreCompleto ?? 'EVENTO';
    final cuando = generada ?? ArTime.nowAr();
    final textoGenerada = 'Generada el ${_dos(cuando.day)}/${_dos(cuando.month)}/'
        '${cuando.year} · ${_dos(cuando.hour)}:${_dos(cuando.minute)}';
    final leyenda = <(PdfColor?, String)>[
      if (pulseras) ...[
        (null, 'VIP: el egresado y sus acompañantes, con cena'),
        (null, 'Menores de 10: no llevan entrada'),
      ] else ...[
        (null, 'Generales: las que completan las 8 de la mesa del contrato'),
        (null, 'Del … al …: los números, si vienen numeradas ("-": sin número)'),
      ],
    ];
    final porAlumno = EntregaEntradas.porAlumno(renglones);

    // Las mismas divisiones y el mismo orden que la planilla del sorteo.
    final grupos = <String, List<ContratoAlumno>>{};
    for (final a in PlanillaSorteo.activos(alumnos)) {
      grupos.putIfAbsent(PlanillaSorteo.division(a), () => []).add(a);
    }
    final claves = grupos.keys.toList()
      ..sort((x, y) {
        if (x == PlanillaSorteo.sinDivision) return 1;
        if (y == PlanillaSorteo.sinDivision) return -1;
        return x.compareTo(y);
      });

    final secciones = <_Seccion>[
      for (final d in claves)
        () {
          final lista = grupos[d]!
            ..sort((x, y) => x.nombreAlumno.compareTo(y.nombreAlumno));
          final filas = [
            for (final a in lista)
              EntregaPorPartes.filaPlanilla(
                a,
                material: material,
                retiro: retiros[a.id],
                renglones: porAlumno[a.id] ?? const [],
                deuda: deudas[a.id] ??
                    const DeudaAlumno(saldoFicha: 0, saldoPagos: 0, mora: 0),
              ),
          ];
          final total = filas.fold<int>(0, (s, f) => s + f.cantidad);
          final retiraron = filas.where((f) => f.entregado).length;
          return (
            nombre: d,
            encabezado: () => tema.encabezado(
                  titulo: 'Planilla de entrega · $queEs · $d',
                  institucion: institucion,
                  version: pulseras ? 'Pulseras VIP con cena' : 'Entradas generales',
                  generada: textoGenerada,
                  control: '${filas.length} egresados · $total '
                      '${pulseras ? 'pulseras VIP con cena' : 'generales'}'
                      '${retiraron > 0 ? ' · ya retiraron $retiraron' : ''}'
                      ' · Quien retira escribe su nombre y apellido: no se firma.',
                ),
            contenido: (alto) => [_tabla(tema, material, filas, alto)],
          );
        }(),
    ];

    if (secciones.isEmpty) {
      final vacio = pw.Document(theme: theme);
      vacio.addPage(
        pw.Page(
          pageFormat: _formato,
          build: (_) => pw.Center(
            child: pw.Text('No hay egresados para entregar.'),
          ),
        ),
      );
      return vacio.save();
    }

    pw.MultiPage pagina(
      _Seccion s, {
      required double alto,
      required int inicio,
      int? total,
    }) =>
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
          build: (_) => s.contenido(alto),
        );

    Future<int> contarHojas(_Seccion s, double alto) async {
      final prueba = pw.Document(theme: theme);
      prueba.addPage(pagina(s, alto: alto, inicio: 1));
      await prueba.save();
      return prueba.document.pdfPageList.pages.length;
    }

    // Igual que la planilla del sorteo: primero se arma cada división sola para
    // contar sus hojas, porque el contexto no sabe cuántas va a tener. De paso
    // se elige el renglón: el justo solo si ahorra una hoja.
    final hojas = <int>[];
    final altos = <double>[];
    for (final s in secciones) {
      final normal = await contarHojas(s, altoRenglon);
      final justo = normal > 1 ? await contarHojas(s, altoRenglonJusto) : normal;
      final alto = altoParaDivision(hojasNormal: normal, hojasJusto: justo);
      altos.add(alto);
      hojas.add(alto == altoRenglon ? normal : justo);
    }

    final doc = pw.Document(
      theme: theme,
      title: 'Planilla de entrega de ${pulseras ? 'pulseras VIP' : 'generales'}',
      author: 'Junior Eventos',
    );
    var inicio = 1;
    for (var i = 0; i < secciones.length; i++) {
      doc.addPage(
        pagina(secciones[i], alto: altos[i], inicio: inicio, total: hojas[i]),
      );
      inicio += hojas[i];
    }
    return doc.save();
  }

  static pw.Widget _tabla(
    PlanillaTema t,
    ParteEntrega material,
    List<FilaPlanillaEntrega> filas,
    double alto,
  ) {
    final titulos = columnas(material);
    final anchos = PlanillaEntregaPdf.anchos(material);
    return pw.Table(
      border: pw.TableBorder(
        top: pw.BorderSide(color: t.linea, width: 0.6),
        bottom: pw.BorderSide(color: t.linea, width: 0.6),
        horizontalInside: pw.BorderSide(color: t.linea, width: 0.6),
        verticalInside: pw.BorderSide(color: t.linea, width: 0.3),
      ),
      columnWidths: {
        for (var i = 0; i < anchos.length; i++) i: pw.FlexColumnWidth(anchos[i]),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: t.fondoEncabezadoTabla),
          children: [
            for (var i = 0; i < titulos.length; i++)
              t.celdaTitulo(
                titulos[i],
                align: i == 2 || i == titulos.length - 1
                    ? pw.TextAlign.center
                    : pw.TextAlign.left,
              ),
          ],
        ),
        for (final f in filas) _fila(t, f, alto),
      ],
    );
  }

  static pw.TableRow _fila(PlanillaTema t, FilaPlanillaEntrega f, double alto) {
    pw.Widget celda(
      String texto, {
      bool negrita = false,
      bool centro = false,
      PdfColor? color,
    }) =>
        pw.Container(
          constraints: pw.BoxConstraints(minHeight: alto),
          alignment: centro ? pw.Alignment.center : pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: pw.Text(
            texto,
            textAlign: centro ? pw.TextAlign.center : pw.TextAlign.left,
            style: t.estilo(negrita: negrita, color: color),
          ),
        );

    final casilla = pw.Container(
      constraints: pw.BoxConstraints(minHeight: alto),
      alignment: pw.Alignment.center,
      child: f.entregado
          ? pw.Text('Sí', style: t.estilo(negrita: true, color: t.verde))
          : f.noLleva
              ? pw.Text('-', style: t.estilo(color: t.textoSuave))
              : pw.Container(
                  width: 9,
                  height: 9,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: t.textoSuave, width: 0.8),
                  ),
                ),
    );

    final pulseras = f.material == ParteEntrega.pulseras;
    // A quien no se le entrega no escribe su nombre: ahí va por qué.
    final nombre = f.noEntregar != null
        ? celda(f.noEntregar!, negrita: true, color: t.rojo)
        : f.noLleva
            ? celda('No lleva generales: las 8 son con cena',
                color: t.textoSuave)
            // En blanco siempre: lo escribe quien retira.
            : celda('');

    return pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        celda(f.egresado, negrita: true),
        celda(f.mesa),
        celda(f.noLleva ? '-' : '${f.cantidad}', centro: true),
        pulseras ? celda(f.menores, centro: true) : celda(f.delAl),
        celda(f.parentesco),
        nombre,
        casilla,
      ],
    );
  }
}
