/// **Un error al anotar que la pantalla tiene que decir tal cual**, en vez de "No se
/// pudo. Probá de nuevo." (28-nov-2026, la revisión independiente): desde el iPhone de la
/// encargada, si se corta justo después de mandar un retiro, "probá de nuevo" la llevaba
/// a anotarlo dos veces. Lo implementan los errores de la página del iPhone.
abstract class AvisoAlAnotar implements Exception {
  String get texto;

  @override
  String toString() => texto;
}

/// Lo que dice la pantalla de [error]: el texto del aviso si es uno, o [siNo].
String textoDelError(Object error, String siNo) => error is AvisoAlAnotar ? error.texto : siNo;
