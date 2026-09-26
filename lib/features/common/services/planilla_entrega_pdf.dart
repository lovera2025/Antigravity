import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/evento.dart';
import '../../eventos/services/planilla_sorteo.dart';
import '../../eventos/services/retiro_entradas.dart';
import 'planilla_tema.dart';

typedef _Seccion = ({
  String nombre,
  pw.Widget Function() encabezado,
  List<pw.Widget> Function(double altoRenglon) contenido,
});

/// La planilla de entrega de entradas: una hoja A4 acostada por división, para
/// tener en el mostrador el día del retiro.
///
/// Es el registro en papel que acompaña al de la app. Quien retira **escribe su
/// nombre y apellido** en su renglón: no se firma, porque una firma la dibuja
/// cualquiera. Lo que la app ya sabe va impreso (egresado, mesa, VIP y
/// generales); si ya retiró, también sus números, sus menores y el parentesco.
/// A quien no se le puede entregar se le imprime por qué ("Debe: no entregar").
///
/// Las filas las arma [RetiroEntradas.filaPlanilla] (lógica pura, con tests).
class PlanillaEntregaPdf {
  PlanillaEntregaPdf._();

  static final PdfPageFormat _formato = PdfPageFormat.a4.landscape;

  static const columnas = [
    'Egresado',
    'Mesa',
    'VIP',
    'Gen.',
    'Generales del … al …',
    'Menores de 10',
    'Parentesco',
    'Nombre y apellido de quien retira',
    'Retiró',
  ];

  /// Se le saca a la columna del nombre, que es la más ancha, para que no se
  /// partan dos cosas:
  /// - "RETIRÓ" necesita ~30 pt de ancho útil: con 0.55 tenía 29 y salía
  ///   "RETIR / Ó";
  /// - "Hermano/a mayor" necesita ~75 pt: con 1.05 iba en dos líneas, el
  ///   renglón crecía y una división de 26 ya no entraba en una hoja.
  static const _anchos = [2.3, 0.75, 0.45, 0.5, 1.75, 0.75, 1.25, 2.85, 0.6];

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

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static Future<Uint8List> construir({
    required Evento evento,
    required List<ContratoAlumno> alumnos,
    required Map<String, EntradasRetiro> retiros,
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

    final institucion = evento.cliente?.nombreCompleto ?? 'EVENTO';
    final cuando = generada ?? ArTime.nowAr();
    final textoGenerada = 'Generada el ${_dos(cuando.day)}/${_dos(cuando.month)}/'
        '${cuando.year} · ${_dos(cuando.hour)}:${_dos(cuando.minute)}';
    const leyenda = <(PdfColor?, String)>[
      (null, 'VIP: con cena, sin número'),
      (null, 'Generales: con número del talonario'),
      (null, 'Menores de 10: no llevan entrada'),
    ];

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
              RetiroEntradas.filaPlanilla(
                a,
                retiro: retiros[a.id],
                deuda: deudas[a.id] ??
                    const DeudaAlumno(saldoFicha: 0, saldoPagos: 0, mora: 0),
              ),
          ];
          final entradas =
              filas.fold<int>(0, (s, f) => s + f.vip + f.generales);
          final vip = filas.fold<int>(0, (s, f) => s + f.vip);
          final retiraron = filas.where((f) => f.entregado).length;
          return (
            nombre: d,
            encabezado: () => tema.encabezado(
                  titulo: 'Planilla de entrega · $d',
                  institucion: institucion,
                  version: 'Retiro de entradas',
                  generada: textoGenerada,
                  control: '${filas.length} egresados · $entradas entradas '
                      '($vip VIP y ${entradas - vip} generales)'
                      '${retiraron > 0 ? ' · ya retiraron $retiraron' : ''}'
                      ' · Quien retira escribe su nombre y apellido: no se firma.',
                ),
            contenido: (alto) => [_tabla(tema, filas, alto)],
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
      final justo =
          normal > 1 ? await contarHojas(s, altoRenglonJusto) : normal;
      final alto = altoParaDivision(hojasNormal: normal, hojasJusto: justo);
      altos.add(alto);
      hojas.add(alto == altoRenglon ? normal : justo);
    }

    final doc = pw.Document(
      theme: theme,
      title: 'Planilla de entrega de entradas',
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
    List<FilaPlanillaEntrega> filas,
    double alto,
  ) {
    return pw.Table(
      border: pw.TableBorder(
        top: pw.BorderSide(color: t.linea, width: 0.6),
        bottom: pw.BorderSide(color: t.linea, width: 0.6),
        horizontalInside: pw.BorderSide(color: t.linea, width: 0.6),
        verticalInside: pw.BorderSide(color: t.linea, width: 0.3),
      ),
      columnWidths: {
        for (var i = 0; i < _anchos.length; i++)
          i: pw.FlexColumnWidth(_anchos[i]),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: t.fondoEncabezadoTabla),
          children: [
            for (var i = 0; i < columnas.length; i++)
              t.celdaTitulo(
                columnas[i],
                align: i >= 2 && i <= 3 ? pw.TextAlign.center : pw.TextAlign.left,
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
          : pw.Container(
              width: 9,
              height: 9,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: t.textoSuave, width: 0.8),
              ),
            ),
    );

    return pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        celda(f.egresado, negrita: true),
        celda(f.mesa, centro: true),
        celda('${f.vip}', centro: true),
        celda('${f.generales}', centro: true),
        f.noEntregar != null
            ? celda(f.noEntregar!, negrita: true, color: t.rojo)
            : celda(f.delAl),
        celda(f.menores, centro: true),
        celda(f.parentesco),
        // En blanco siempre: lo escribe quien retira.
        celda(''),
        casilla,
      ],
    );
  }
}
