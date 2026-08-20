/// Regla única de comparación para todos los buscadores de la app.
///
/// Antes cada lista tenía la suya, y todas eran un `contains` pelado sobre el
/// texto crudo. Eso hacía que "maxi operador" encontrara la fila `MAXI OPERADOR`
/// pero "operador maxi" no encontrara nada, y que buscar "anotacion" no diera con
/// "Anotación". Dos buscadores al lado del otro, en la misma pantalla, con
/// resultados distintos según cuál usabas.
///
/// Acá la regla es una sola: minúsculas, sin tildes, y **todas las palabras
/// presentes en cualquier orden**. Qué campos mira cada lista sigue siendo cosa
/// de cada pantalla — el panel de movimientos no busca por medio de pago porque
/// tiene los chips al lado, la tabla de egresos sí porque no los tiene.
library;

/// Texto comparable: minúsculas, sin tildes, sin espacios de sobra.
///
/// Vivía privado adentro del armador de PDFs, que era la única parte del sistema
/// que sabía ignorar tildes.
String normalizarTextoBusqueda(String? raw) {
  if (raw == null) return '';
  const pares = <String, String>{
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  final b = StringBuffer();
  for (final r in raw.toLowerCase().trim().runes) {
    final ch = String.fromCharCode(r);
    b.write(pares[ch] ?? ch);
  }
  return b.toString();
}

/// `true` si **todas** las palabras de [query] aparecen en alguno de [campos].
///
/// Cada palabra puede caer en un campo distinto: buscar "maxi personal" encuentra
/// una fila cuyo concepto es `MAXI OPERADOR` y cuya categoría es `Personal`.
/// Una consulta vacía no filtra nada.
bool coincideTextoBusqueda(Iterable<String?> campos, String query) {
  final palabras = normalizarTextoBusqueda(query).split(RegExp(r'\s+'))
    ..removeWhere((p) => p.isEmpty);
  if (palabras.isEmpty) return true;

  final heno = [
    for (final c in campos)
      if (c != null && c.trim().isNotEmpty) normalizarTextoBusqueda(c),
  ];
  if (heno.isEmpty) return false;

  return palabras.every((p) => heno.any((h) => h.contains(p)));
}
