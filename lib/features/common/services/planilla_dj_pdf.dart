import 'dart:math';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../eventos/services/planilla_delegado.dart';
import 'planilla_tema.dart';

/// Un egresado en la hoja del DJ: su nombre, con quién viene y su música.
class FilaParaElDj {
  final String egresado;

  /// Un renglón por acompañante, y al final "2 sin nombre" si la cuenta
  /// dice más de los que tienen nombre. Vacía: viene solo.
  final List<String> acompanantes;

  /// Vacía: no eligió.
  final String musica;

  const FilaParaElDj({
    required this.egresado,
    required this.acompanantes,
    required this.musica,
  });
}

/// Una división de la hoja del DJ, con sus egresados en orden.
class DivisionParaElDj {
  final String nombre;
  final List<FilaParaElDj> filas;

  const DivisionParaElDj({required this.nombre, required this.filas});

  /// "5° A · 32 egresados": el título de su tabla.
  String get titulo =>
      '$nombre · ${filas.length == 1 ? '1 egresado' : '${filas.length} egresados'}';
}

/// La hoja para el DJ (PLANILLAS → "Para el DJ", 22-nov-2026): cada egresado
/// con sus acompañantes y su música, **y nada más**. Sin DNI, teléfono, mesas,
/// sillas, entradas ni plata: se le da a alguien de afuera.
///
/// A4 parado. Por división, en el orden del Excel del delegado
/// ([PlanillaDelegado.alumnosDeLaPlanilla]: los de baja afuera y "Sin curso
/// asignado" al final), una tabla de tres columnas: Egresado · Acompañantes ·
/// Música.
///
/// - Las divisiones van una detrás de la otra, sin hoja nueva para cada una:
///   se ahorra papel. Lo largo no se corta: la música baja de renglón y una
///   tabla que no entra sigue en la hoja siguiente.
/// - El título de la división y el de las columnas son renglones de la tabla
///   que se repiten en cada hoja: así el título nunca queda solo al pie de una
///   hoja, y en la hoja que sigue se sabe de qué división es.
/// - Las tablas van como hijas directas del `pw.MultiPage`, para que se partan
///   entre hojas, y cada celda en [AltoLibre]: en una tabla, una columna de
///   renglones puede perder el último sin avisar (ver la trampa de los PDF en
///   CLAUDE.md).
///
/// Sin [regular] y [negrita] sale con la letra de fábrica del paquete: así se
/// lee palabra por palabra en los tests (`palabrasDelPdf`).
class PlanillaDjPdf {
  PlanillaDjPdf._();

  static const titulo = 'Para el DJ';
  static const queLleva = 'Egresados, acompañantes y música';
  static const columnas = ['Egresado', 'Acompañantes', 'Música'];
  static const sinDivision = 'Sin curso asignado';

  /// Lo que se escribe en un casillero vacío.
  static const vacio = '-';

  /// Lo que va en la hoja, sin dibujar: los egresados activos por división,
  /// en el orden del Excel del delegado.
  static List<DivisionParaElDj> divisiones(Iterable<ContratoAlumno> alumnos) {
    final porDivision = <String, List<FilaParaElDj>>{};
    for (final a in PlanillaDelegado.alumnosDeLaPlanilla(alumnos)) {
      final division = (a.cursoDivision ?? '').trim();
      porDivision
          .putIfAbsent(division.isEmpty ? sinDivision : division, () => [])
          .add(fila(a));
    }
    return [
      for (final e in porDivision.entries)
        DivisionParaElDj(nombre: e.key, filas: e.value),
    ];
  }

  /// Un egresado tal como va en la hoja.
  static FilaParaElDj fila(ContratoAlumno a) {
    final nombres = PlanillaDelegado.limpios(a.nombresAcompanantes);
    final sinNombre = max(0, a.cantidadAcompanantes - nombres.length);
    return FilaParaElDj(
      egresado: PlanillaDelegado.nombreLimpio(a),
      acompanantes: [
        ...nombres,
        if (sinNombre > 0) '$sinNombre sin nombre',
      ],
      musica: (a.musicaElegida ?? '').trim(),
    );
  }

  /// [alumnos]: los de la fiesta, con los de baja (se sacan acá).
  /// [fechaFiesta]: el día de la fiesta, por sus partes (es una fecha, no un
  /// instante). [generada]: **un instante**; el papel lo escribe en la hora de
  /// Argentina. Sin él, ahora.
  static Future<Uint8List> construir({
    required String institucion,
    required Iterable<ContratoAlumno> alumnos,
    DateTime? fechaFiesta,
    pw.Font? regular,
    pw.Font? negrita,
    DateTime? generada,
  }) {
    const tema = PlanillaTema();
    final theme = regular != null && negrita != null
        ? pw.ThemeData.withFont(base: regular, bold: negrita)
        : null;
    final lista = divisiones(alumnos);
    final egresados = lista.fold<int>(0, (s, d) => s + d.filas.length);
    String dos(int n) => n.toString().padLeft(2, '0');
    final fiesta = fechaFiesta == null
        ? ''
        : 'Fiesta del ${dos(fechaFiesta.day)}/${dos(fechaFiesta.month)}/${fechaFiesta.year}';
    final cuando = ArTime.formatFechaHora(generada ?? ArTime.nowUtc());

    // Cada celda en `AltoLibre`: un nombre largo o la música bajan de renglón,
    // y en una tabla el último renglón de una celda se puede perder.
    pw.Widget celda(List<String> renglones, {bool negrita = false}) => AltoLibre(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final r in renglones.isEmpty ? const [vacio] : renglones)
                  pw.Text(r, style: tema.estilo(negrita: negrita)),
              ],
            ),
          ),
        );

    pw.Widget tabla(DivisionParaElDj d) => pw.Table(
          border: pw.TableBorder(
            bottom: pw.BorderSide(color: tema.linea, width: 0.8),
            horizontalInside: pw.BorderSide(color: tema.linea, width: 0.6),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(4),
          },
          children: [
            // El título de la división: se repite en cada hoja, junto con los
            // de las columnas. Escrito de un tirón, sin bajar de renglón: las
            // otras dos celdas van vacías y el texto pasa por encima.
            pw.TableRow(
              repeat: true,
              children: [
                AltoLibre(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.fromLTRB(0, 6, 5, 3),
                    child: pw.Text(
                      d.titulo,
                      softWrap: false,
                      overflow: pw.TextOverflow.visible,
                      style: tema.estilo(size: 11, negrita: true, color: tema.acento),
                    ),
                  ),
                ),
                pw.SizedBox(),
                pw.SizedBox(),
              ],
            ),
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(color: tema.fondoEncabezadoTabla),
              children: [for (final c in columnas) tema.celdaTitulo(c)],
            ),
            for (final (i, f) in d.filas.indexed)
              pw.TableRow(
                decoration: i.isOdd && tema.filaAlterna != null
                    ? pw.BoxDecoration(color: tema.filaAlterna)
                    : null,
                children: [
                  celda([f.egresado], negrita: true),
                  celda(f.acompanantes),
                  celda(f.musica.isEmpty ? const [] : [f.musica]),
                ],
              ),
          ],
        );

    final doc = pw.Document(theme: theme, title: '$titulo - $institucion');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(PlanillaTema.margen),
        maxPages: 200,
        header: (_) => tema.encabezado(
          titulo: titulo,
          institucion: institucion,
          version: fiesta,
          generada: 'Generada el $cuando',
          control: '$queLleva · '
              '${egresados == 1 ? '1 egresado' : '$egresados egresados'}',
        ),
        footer: (ctx) => tema.pie(
          leyenda: const [],
          paginacion: 'Hoja ${ctx.pageNumber} de ${ctx.pagesCount}',
        ),
        build: (_) => [
          if (lista.isEmpty)
            pw.Text(
              'No hay egresados activos en esta fiesta.',
              style: tema.estilo(color: tema.textoSuave),
            ),
          for (final (i, d) in lista.indexed) ...[
            if (i > 0) pw.SizedBox(height: 10),
            tabla(d),
          ],
        ],
      ),
    );
    return doc.save();
  }

  /// "Para el DJ - COLEGIO SAN JOSÉ.pdf": sin los caracteres que Windows no
  /// deja en el nombre de un archivo.
  static String nombreDelArchivo(String institucion) {
    final limpio = institucion
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    return '$titulo - ${limpio.isEmpty ? 'Evento' : limpio}.pdf';
  }
}
