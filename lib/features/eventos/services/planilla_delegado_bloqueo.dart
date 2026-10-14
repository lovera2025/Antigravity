import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../../models/contrato_alumno.dart';
import 'planilla_delegado.dart';

/// Cierra el Excel del delegado: deja escribir **solo** en los casilleros de
/// Acompañantes y Música, y hace que el de Acompañantes rechace un tercero.
///
/// El paquete `excel` no sabe proteger una hoja ni validar un casillero, así
/// que esto se escribe después, sobre el archivo ya armado: un .xlsx es un zip
/// con XML adentro. Toca dos archivos:
///
/// - `xl/styles.xml`: los casilleros amarillos ([kColorCasilleroDelegado])
///   pasan a "sin bloquear";
/// - la hoja: se protege, y la columna de Acompañantes lleva la regla de
///   [kMaxAcompanantes] con su cartel.
///
/// **Es una ayuda para el delegado, no la garantía.** Excel lo respeta (en la
/// PC y en el celular); Google Sheets puede dejar escribir igual. La garantía
/// está al importar, que lee solo esos dos casilleros y no carga un tercero.
///
/// La hoja lleva una clave ([kClavePlanillaDelegado]) para que no se pueda
/// desproteger con un clic desde Revisar → "Desproteger hoja". No es un
/// secreto —está acá escrita— ni una seguridad: es un freno para que nadie
/// la saque sin querer.
///
/// [alumnos] es cuántos renglones de alumnos tiene la planilla. Tira si el
/// archivo no tiene la forma esperada: quien llama exporta entonces la
/// planilla sin cerrar y lo avisa ([exportarPlanillaDelegado]).
const String kClavePlanillaDelegado = 'delegado';

/// La clave de una hoja como la guarda Excel: no va el texto, va esta cuenta
/// de 16 bits, en hexadecimal (ECMA-376, parte 4, 3.3.1.81).
String claveDeHojaExcel(String clave) {
  var cuenta = 0;
  for (var i = 0; i < clave.length; i++) {
    final corrido = clave.codeUnitAt(i) << (i + 1);
    cuenta ^= (corrido & 0x7FFF) | (corrido >> 15);
  }
  cuenta ^= clave.length;
  cuenta ^= 0xCE4B;
  return cuenta.toRadixString(16).toUpperCase();
}

Uint8List bloquearPlanilla(Uint8List bytes, {required int alumnos}) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final nuevo = Archive();
  var estilos = false;
  var hoja = false;

  for (final archivo in zip.files) {
    if (!archivo.isFile) continue;
    var contenido = archivo.content as List<int>;
    if (archivo.name == 'xl/styles.xml') {
      contenido = utf8.encode(_desbloquearAmarillos(utf8.decode(contenido)));
      estilos = true;
    } else if (!hoja &&
        RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(archivo.name)) {
      contenido = utf8.encode(_protegerHoja(utf8.decode(contenido), alumnos));
      hoja = true;
    }
    nuevo.addFile(ArchiveFile(archivo.name, contenido.length, contenido));
  }
  if (!estilos || !hoja) {
    throw StateError('El Excel no tiene la hoja o los estilos esperados.');
  }
  return Uint8List.fromList(ZipEncoder().encode(nuevo)!);
}

/// En los estilos, los casilleros con el relleno amarillo dejan de estar
/// bloqueados. Todo lo demás queda bloqueado, que es lo que Excel asume.
String _desbloquearAmarillos(String xml) {
  final doc = XmlDocument.parse(xml);
  final rellenos = doc.findAllElements('fills').first.childElements.toList();
  final amarillo = rellenos.indexWhere(
    (f) => f.findAllElements('fgColor').any(
          (c) => c.getAttribute('rgb')?.toUpperCase() == kColorCasilleroDelegado,
        ),
  );
  if (amarillo < 0) {
    throw StateError('No está el relleno de los casilleros para completar.');
  }
  var tocados = 0;
  for (final xf in doc.findAllElements('cellXfs').first.childElements) {
    if (xf.getAttribute('fillId') != '$amarillo') continue;
    xf.setAttribute('applyProtection', '1');
    xf.children.add(
      XmlElement(XmlName('protection'), [
        XmlAttribute(XmlName('locked'), '0'),
      ]),
    );
    tocados++;
  }
  if (tocados == 0) {
    throw StateError('Ningún casillero usa el relleno para completar.');
  }
  return doc.toXmlString();
}

/// En la hoja: la protección, y la regla del máximo en Acompañantes.
String _protegerHoja(String xml, int alumnos) {
  final doc = XmlDocument.parse(xml);
  final raiz = doc.rootElement;
  final hijos = raiz.children;

  // El orden de los elementos de una hoja es fijo: la protección va justo
  // después de los datos, y las reglas después de las celdas combinadas.
  final datos = raiz.findElements('sheetData').first;
  hijos.insert(
    hijos.indexOf(datos) + 1,
    XmlElement(XmlName('sheetProtection'), [
      XmlAttribute(
        XmlName('password'),
        claveDeHojaExcel(kClavePlanillaDelegado),
      ),
      XmlAttribute(XmlName('sheet'), '1'),
      XmlAttribute(XmlName('objects'), '1'),
      XmlAttribute(XmlName('scenarios'), '1'),
    ]),
  );

  if (alumnos > 0) {
    final primera = PlanillaDelegado.filaEncabezados + 2;
    final ultima = primera + alumnos - 1;
    final col = String.fromCharCode(
      'A'.codeUnitAt(0) + PlanillaDelegado.columnaAcompanantes,
    );
    // Cuenta las barras: con una sola hay dos nombres.
    final formula = 'LEN($col$primera)-LEN(SUBSTITUTE($col$primera,"/",""))'
        '<=${kMaxAcompanantes - 1}';
    final reglas = XmlElement(XmlName('dataValidations'), [
      XmlAttribute(XmlName('count'), '1'),
    ], [
      XmlElement(XmlName('dataValidation'), [
        XmlAttribute(XmlName('type'), 'custom'),
        XmlAttribute(XmlName('allowBlank'), '1'),
        XmlAttribute(XmlName('showInputMessage'), '1'),
        XmlAttribute(XmlName('showErrorMessage'), '1'),
        XmlAttribute(
          XmlName('errorTitle'),
          'Máximo $kMaxAcompanantes acompañantes',
        ),
        XmlAttribute(
          XmlName('error'),
          'Escribí hasta $kMaxAcompanantes nombres, separados por una '
              'barra: Marta Acosta / Hugo Ríos',
        ),
        XmlAttribute(XmlName('promptTitle'), 'Acompañantes'),
        XmlAttribute(
          XmlName('prompt'),
          'Hasta $kMaxAcompanantes, separados por una barra ( / )',
        ),
        XmlAttribute(XmlName('sqref'), '$col$primera:$col$ultima'),
      ], [
        XmlElement(XmlName('formula1'), [], [XmlText(formula)]),
      ]),
    ]);
    final combinadas = raiz.findElements('mergeCells');
    final despuesDe =
        combinadas.isNotEmpty ? combinadas.first : raiz.findElements('sheetProtection').first;
    hijos.insert(hijos.indexOf(despuesDe) + 1, reglas);
  }
  return doc.toXmlString();
}

/// Lo que sale al exportar: el archivo, y si se pudo cerrar.
typedef PlanillaExportada = ({Uint8List bytes, bool cerrada});

/// El Excel de una institución, cerrado si se pudo.
///
/// Si [bloquearPlanilla] falla, devuelve el Excel sin cerrar: el jefe no se
/// puede quedar sin planilla por una ayuda que no es la garantía.
PlanillaExportada exportarPlanillaDelegado({
  required String eventoId,
  required String institucion,
  required Iterable<ContratoAlumno> alumnos,
}) {
  final lista = PlanillaDelegado.alumnosDeLaPlanilla(alumnos);
  final abierta = PlanillaDelegado.armar(
    eventoId: eventoId,
    institucion: institucion,
    alumnos: lista,
  );
  try {
    return (
      bytes: bloquearPlanilla(abierta, alumnos: lista.length),
      cerrada: true,
    );
  } catch (_) {
    return (bytes: abierta, cerrada: false);
  }
}
