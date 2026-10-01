import '../../../models/contrato_alumno.dart';

/// Las divisiones de una fiesta, como las escribió cada uno.
///
/// `curso_division` es texto libre y está escrito de mil formas ("5° A",
/// "5° a", "5ºA", "5 A"). Para el sorteo por bloques y la planilla son la misma
/// división; para la pantalla se muestra la forma más usada.
class Divisiones {
  Divisiones._();

  /// Lo que se muestra cuando un alumno no tiene división cargada.
  static const sinDivision = 'Sin curso asignado';

  static const _sinTilde = {
    'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N',
  };

  /// Lo que se escribe entre el número y la letra y no dice nada: "5° A",
  /// "5ºA", "5.A", "5-A", "5ª A", "5 'A'".
  static const _relleno = {'°', 'º', 'ª', '.', '-', '_', '/', "'", '"', '´', '`'};

  /// La clave con la que se agrupan: mayúsculas, sin tildes, sin °, º, puntos,
  /// guiones ni comillas, sin espacios. "5° a" → "5A". Vacía si no tiene
  /// división.
  static String clave(String? division) {
    final t = (division ?? '').trim().toUpperCase();
    final b = StringBuffer();
    for (final r in t.runes) {
      final c = String.fromCharCode(r);
      if (_relleno.contains(c) || c.trim().isEmpty) continue;
      b.write(_sinTilde[c] ?? c);
    }
    return b.toString();
  }

  /// Clave → nombre para mostrar (la forma más usada; a igual uso, la primera
  /// en orden alfabético).
  static Map<String, String> nombres(Iterable<ContratoAlumno> alumnos) =>
      nombresDe(alumnos.map((a) => a.cursoDivision));

  /// Lo mismo que [nombres], a partir de los textos sueltos (el plano no
  /// trabaja con alumnos sino con ocupantes).
  static Map<String, String> nombresDe(Iterable<String?> divisiones) {
    final usos = <String, Map<String, int>>{};
    for (final d in divisiones) {
      final k = clave(d);
      final texto = (d ?? '').trim();
      final porForma = usos.putIfAbsent(k, () => {});
      porForma[texto] = (porForma[texto] ?? 0) + 1;
    }
    return {
      for (final e in usos.entries)
        e.key: e.key.isEmpty
            ? sinDivision
            : (e.value.entries.toList()
                  ..sort((x, y) {
                    final c = y.value.compareTo(x.value);
                    return c != 0 ? c : x.key.compareTo(y.key);
                  }))
                .first
                .key,
    };
  }

  /// Las claves en un orden natural: por número y después por letra ("5A"
  /// antes que "10A"); "sin división" al final.
  static List<String> ordenNatural(Iterable<String> claves) {
    final l = claves.toSet().toList();
    int numero(String k) =>
        int.tryParse(RegExp(r'^\d+').firstMatch(k)?.group(0) ?? '') ?? 1 << 20;
    l.sort((a, b) {
      if (a.isEmpty) return 1;
      if (b.isEmpty) return -1;
      final c = numero(a).compareTo(numero(b));
      return c != 0 ? c : a.compareTo(b);
    });
    return l;
  }

  /// Pares de divisiones que se parecen demasiado para ser distintas ("1" y
  /// "1RA", "5A" y "5AA"): seguramente es la misma, escrita distinto. La app
  /// avisa para corregirlo en Editar alumno; no las junta sola.
  static List<(String, String)> parecidas(Iterable<String> claves) {
    final l = claves.where((k) => k.isNotEmpty).toSet().toList()..sort();
    final out = <(String, String)>[];
    for (var i = 0; i < l.length; i++) {
      for (var j = i + 1; j < l.length; j++) {
        final a = l[i];
        final b = l[j];
        final numA = RegExp(r'^\d+').firstMatch(a)?.group(0);
        final numB = RegExp(r'^\d+').firstMatch(b)?.group(0);
        if (numA == null || numA != numB) continue;
        final restoA = a.substring(numA.length);
        final restoB = b.substring(numB!.length);
        // "1" y "1RA", "1ERA", "1RO": el mismo número, y uno sin letra de
        // división o con un sufijo de ordinal.
        const ordinales = {'', 'RA', 'RO', 'ERA', 'ERO', 'DA', 'DO', 'TA', 'TO'};
        if (ordinales.contains(restoA) && ordinales.contains(restoB)) {
          out.add((a, b));
          continue;
        }
        // "5TO A" y "5 A": el mismo número y la misma letra, uno con el
        // ordinal escrito.
        String sinOrdinal(String resto) {
          for (final o in const ['ERA', 'ERO', 'RA', 'RO', 'DA', 'DO', 'TA', 'TO']) {
            if (resto.length > o.length && resto.startsWith(o)) {
              return resto.substring(o.length);
            }
          }
          return resto;
        }

        if (restoA != restoB &&
            (sinOrdinal(restoA) == restoB || sinOrdinal(restoB) == restoA)) {
          out.add((a, b));
          continue;
        }
        // Una letra repetida o de más: "5A" y "5AA".
        if (restoA.isNotEmpty &&
            restoB.isNotEmpty &&
            (restoA.startsWith(restoB) || restoB.startsWith(restoA)) &&
            (restoA.length - restoB.length).abs() == 1) {
          out.add((a, b));
        }
      }
    }
    return out;
  }
}
