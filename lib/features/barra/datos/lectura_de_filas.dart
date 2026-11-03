/// Cómo se leen las columnas de una fila de la barra, venga de la base de la PC o de
/// la nube. **Nunca tiran:** una fila rara se muestra con ceros, no frena la caja.
///
/// La nube devuelve la plata como número (`numeric`) y las fechas con su zona; la
/// base de la PC, como `REAL` y texto. Las dos pasan por acá.
library;

double comoDouble(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

double? comoDoubleONull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

int comoInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

int? comoIntONull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

/// Las casillas van como 0 y 1 en la PC y en la nube.
bool comoBool(Object? v) => v == 1 || v == true || v == '1' || v == 'true';

String? comoTextoONull(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

String comoTexto(Object? v) => v?.toString() ?? '';

/// El momento en el formato de todas las tablas: ISO en UTC.
String isoDe(DateTime momento) => momento.toUtc().toIso8601String();
