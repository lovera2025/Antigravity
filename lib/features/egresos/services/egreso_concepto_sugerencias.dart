import '../../../models/egreso.dart';
import '../../../models/evento.dart';
import '../../cierre_caja/models/turno_caja.dart';

/// Valor que se persiste para un pago a operador (liquidación, colores, edición).
const String kCategoriaPersonal = 'Personal';

/// Etiqueta del combo y del desglose. El gasto global histórico guardaba esto
/// en vez de [kCategoriaPersonal] y partía el historial de Juan.
const String kCategoriaOperadores = 'Operadores';

/// Default del combo cuando el nombre es nuevo: no se adivina.
const String kCategoriaComboDefault = 'Proveedores';

/// Rubros del formulario unificado. **Operadores** se guarda como [kCategoriaPersonal].
const List<String> kCategoriasEgresoNegocioCombo = [
  'Sueldos',
  kCategoriaOperadores,
  'Alquiler local',
  'Proveedores',
  'Logística',
  'Marketing',
  'Impuestos',
  'Otro',
];

bool esCategoriaOperador(String? cat) {
  final c = (cat ?? '').trim();
  return c == kCategoriaPersonal || c == kCategoriaOperadores;
}

/// Lo que va a `egresos.categoria` al guardar el combo.
String categoriaEgresoParaGuardar(String comboValue) {
  final c = comboValue.trim();
  if (c == kCategoriaOperadores) return kCategoriaPersonal;
  return c;
}

/// Lo que tiene que mostrar el combo a partir de lo ya persistido.
String categoriaEgresoParaCombo(String? stored) {
  final c = (stored ?? '').trim();
  if (c == kCategoriaPersonal) return kCategoriaOperadores;
  return c;
}

/// Rubro único para "En qué se fue": Personal y Operadores no van en dos líneas.
String rubroDesgloseEgreso(String? cat) {
  final c = (cat ?? '').trim();
  if (c.isEmpty) return 'Sin categoría';
  if (esCategoriaOperador(c)) return kCategoriaOperadores;
  return c;
}

bool filaEsBolsilloParaSugerencias({
  required String proveedor,
  required String categoria,
}) {
  final cat = categoria.trim();
  if (cat == kCategoriaGastoPersonal || cat == kCategoriaRetiroDueno) {
    return true;
  }
  final p = proveedor.trim();
  return p.startsWith(kPrefijoGastoPersonalEmpresa) ||
      p.startsWith(kPrefijoGastoPersonalPendiente);
}

/// Una fila de historial para armar el buscador. [proveedor] es el texto
/// persistido (la identidad del historial).
class EgresoConceptoFila {
  final String proveedor;
  final String categoria;
  final double monto;
  final DateTime? fecha;
  final String? eventoTipo;

  const EgresoConceptoFila({
    required this.proveedor,
    required this.categoria,
    required this.monto,
    this.fecha,
    this.eventoTipo,
  });

  factory EgresoConceptoFila.fromEgreso(Egreso e, {String? eventoTipo}) {
    return EgresoConceptoFila(
      proveedor: (e.proveedor ?? '').trim(),
      categoria: (e.categoria ?? '').trim(),
      monto: e.monto,
      fecha: e.fecha,
      eventoTipo: eventoTipo,
    );
  }
}

/// Índice en memoria de nombres ya cargados. No adivina categoría de un nombre nuevo.
class EgresoConceptoSugerencias {
  EgresoConceptoSugerencias(this._filas);

  /// Negocio only, más reciente primero.
  final List<EgresoConceptoFila> _filas;

  factory EgresoConceptoSugerencias.fromFilas(Iterable<EgresoConceptoFila> filas) {
    final negocio = filas
        .where(
          (f) =>
              f.proveedor.trim().isNotEmpty &&
              !filaEsBolsilloParaSugerencias(
                proveedor: f.proveedor,
                categoria: f.categoria,
              ),
        )
        .toList();
    negocio.sort((a, b) {
      final fa = a.fecha;
      final fb = b.fecha;
      if (fa == null && fb == null) return 0;
      if (fa == null) return 1;
      if (fb == null) return -1;
      return fb.compareTo(fa);
    });
    return EgresoConceptoSugerencias(negocio);
  }

  factory EgresoConceptoSugerencias.fromEgresos(
    Iterable<Egreso> egresos, {
    Map<String, String>? tipoPorEventoId,
  }) {
    return EgresoConceptoSugerencias.fromFilas([
      for (final e in egresos)
        EgresoConceptoFila.fromEgreso(
          e,
          eventoTipo: tipoPorEventoId?[e.eventoId],
        ),
    ]);
  }

  /// Nombres canónicos, el más reciente primero. Variantes distintas
  /// (`GALPON` vs `PAGO GALPON`) quedan las dos.
  List<String> get nombresUnicos {
    final seen = <String>{};
    final out = <String>[];
    for (final f in _filas) {
      if (seen.add(f.proveedor)) out.add(f.proveedor);
    }
    return out;
  }

  Iterable<String> filtrarNombres(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const Iterable<String>.empty();
    return nombresUnicos.where((n) => n.toLowerCase().contains(q));
  }

  /// Si el texto coincide (sin importar mayúsculas) con un único nombre ya
  /// cargado, devuelve **ese** string persistido. Si hay varias grafías, se
  /// queda con la más reciente. Si no hay match, el texto recortado.
  String nombreCanonico(String typed) {
    final t = typed.trim();
    if (t.isEmpty) return t;
    final lower = t.toLowerCase();
    final matches =
        nombresUnicos.where((n) => n.toLowerCase() == lower).toList();
    if (matches.isEmpty) return t;
    final exacto = matches.where((n) => n == t);
    if (exacto.isNotEmpty) return exacto.first;
    return matches.first;
  }

  bool esNombreConocidoDe(String typed) {
    final t = typed.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
    return nombresUnicos.any((n) => n.toLowerCase() == lower);
  }

  String? ultimaCategoriaGuardada(String typed) {
    final canon = nombreCanonico(typed);
    for (final f in _filas) {
      if (f.proveedor == canon) return f.categoria;
    }
    return null;
  }

  /// Valor del combo al elegir un nombre ya cargado. `null` si es nuevo:
  /// no se infiere.
  String? categoriaComboAlElegir(String typed) {
    if (!esNombreConocidoDe(typed)) return null;
    final cat = ultimaCategoriaGuardada(typed);
    if (cat == null || cat.isEmpty) return null;
    return categoriaEgresoParaCombo(cat);
  }

  /// Moda; empate → el primero de la lista (el más reciente si vino ordenada).
  static double modaOUltimo(List<double> montos) {
    if (montos.isEmpty) return 0;
    if (montos.length == 1) return montos.first;
    final freq = <double, int>{};
    for (final m in montos) {
      freq[m] = (freq[m] ?? 0) + 1;
    }
    final maxFreq = freq.values.reduce((a, b) => a > b ? a : b);
    final candidatos = freq.entries
        .where((e) => e.value == maxFreq)
        .map((e) => e.key)
        .toList();
    if (candidatos.length == 1) return candidatos.first;
    return montos.first;
  }

  /// Solo para operadores. Si hay [tipoEvento], prioriza ese tipo; si no hay
  /// historial de ese tipo, usa todos los pagos de operador a ese nombre.
  double? montoSugeridoOperador(String typed, {String? tipoEvento}) {
    if (!esNombreConocidoDe(typed)) return null;
    final canon = nombreCanonico(typed);
    if (!esCategoriaOperador(ultimaCategoriaGuardada(canon))) return null;

    final deEsteNombre = _filas
        .where((f) => f.proveedor == canon && esCategoriaOperador(f.categoria))
        .toList();
    if (deEsteNombre.isEmpty) return null;

    final tipoNorm = Evento.normalizarTipo(tipoEvento);
    var montos = <double>[];
    if (tipoNorm.isNotEmpty) {
      montos = [
        for (final f in deEsteNombre)
          if (Evento.normalizarTipo(f.eventoTipo) == tipoNorm && f.monto > 0)
            f.monto,
      ];
    }
    if (montos.isEmpty) {
      montos = [
        for (final f in deEsteNombre)
          if (f.monto > 0) f.monto,
      ];
    }
    if (montos.isEmpty) return null;
    return modaOUltimo(montos);
  }

  /// Operadores a los que ya se les pagó en este tipo de evento, más frecuentes
  /// primero. El valor es el monto sugerido.
  List<MapEntry<String, double>> operadoresParaTipo(String tipoEvento) {
    final tipoNorm = Evento.normalizarTipo(tipoEvento);
    if (tipoNorm.isEmpty) return const [];

    final porProveedor = <String, List<double>>{};
    for (final f in _filas) {
      if (!esCategoriaOperador(f.categoria)) continue;
      if (Evento.normalizarTipo(f.eventoTipo) != tipoNorm) continue;
      if (f.monto <= 0) continue;
      porProveedor.putIfAbsent(f.proveedor, () => []).add(f.monto);
    }

    final sugeridos = <MapEntry<String, double>>[
      for (final e in porProveedor.entries)
        MapEntry(e.key, modaOUltimo(e.value)),
    ];
    sugeridos.sort((a, b) {
      final countA = porProveedor[a.key]!.length;
      final countB = porProveedor[b.key]!.length;
      if (countB != countA) return countB.compareTo(countA);
      return a.key.compareTo(b.key);
    });
    return sugeridos;
  }
}
