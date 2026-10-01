import '../services/divisiones.dart';
import 'armado_salon.dart';

/// Quién ocupa mesas del plano. Es genérico a propósito: en los masivos sale
/// de un alumno y, en diciembre, el tótem lo va a armar desde la lista de la
/// puerta, sin tocar el dibujo.
class OcupantePlano {
  final String id;

  /// Como está cargado ("GÓMEZ, SOFÍA").
  final String nombre;
  final List<int> numeros;
  final String? division;

  /// Sillas extra que van en cada una de sus mesas (mesa → cantidad).
  final Map<int, int> sillasExtraPorMesa;

  const OcupantePlano({
    required this.id,
    required this.nombre,
    required this.numeros,
    this.division,
    this.sillasExtraPorMesa = const {},
  });

  /// Lo que va antes de la coma: "GÓMEZ" de "GÓMEZ, SOFÍA".
  String get apellido {
    final i = nombre.indexOf(',');
    return (i < 0 ? nombre : nombre.substring(0, i)).trim();
  }

  /// La mesa principal: la primera del tramo más largo (a igual largo, el que
  /// empieza antes). Es la misma regla que usa la planilla del sorteo.
  int? get principal => principalDe(numeros);

  static int? principalDe(Iterable<int> numeros) {
    final l = numeros.toSet().toList()..sort();
    if (l.isEmpty) return null;
    var mejorInicio = l.first;
    var mejorLargo = 1;
    var inicio = l.first;
    var largo = 1;
    for (var i = 1; i < l.length; i++) {
      if (l[i] == l[i - 1] + 1) {
        largo++;
      } else {
        inicio = l[i];
        largo = 1;
      }
      if (largo > mejorLargo) {
        mejorLargo = largo;
        mejorInicio = inicio;
      }
    }
    return mejorInicio;
  }
}

enum EstadoMesa {
  /// Nadie la tiene.
  vacia,

  /// La tiene una familia.
  ocupada,

  /// Se dejó libre a propósito: el sorteo no la usa.
  libre,

  /// Reservada para una familia antes del sorteo.
  fijada,

  /// Algo no cierra y hay que resolverlo: dos familias con el mismo número,
  /// una mesa fijada para una familia y ocupada por otra, o una mesa que se
  /// dejó libre y tiene familia.
  conflicto,
}

class InfoMesa {
  final int numero;
  final EstadoMesa estado;
  final List<OcupantePlano> ocupantes;

  /// Índice de la división en [EstadoPlano.divisiones] (para el color). Null
  /// si la familia no tiene división cargada.
  final int? division;

  /// Es la mesa que lleva el apellido de su familia, si hay lugar: la
  /// principal de la que la ocupa o, antes del sorteo, de la que la tiene
  /// fijada.
  final bool principal;
  final int sillasExtra;

  /// La familia para la que está fijada (antes del sorteo). Se conserva
  /// aunque la mesa ya tenga familia: el candado se sigue viendo.
  final OcupantePlano? fijadaPara;

  /// Se dejó libre a propósito. Se conserva aunque esté ocupada (y entonces
  /// es un conflicto).
  final bool libre;

  const InfoMesa({
    required this.numero,
    this.estado = EstadoMesa.vacia,
    this.ocupantes = const [],
    this.division,
    this.principal = false,
    this.sillasExtra = 0,
    this.fijadaPara,
    this.libre = false,
  });

  OcupantePlano? get ocupante => ocupantes.isEmpty ? null : ocupantes.first;
}

/// Cómo está el salón: qué hay en cada mesa. Es lo que dibuja el plano.
class EstadoPlano {
  final Map<int, InfoMesa> _mesas;

  /// Las divisiones en el orden de la leyenda (y de los colores), como claves
  /// de [Divisiones.clave]: "5° a" y "5° A" son la misma. Las familias sin
  /// división no están acá: no llevan color y van al final de la leyenda
  /// ([haySinDivision]).
  final List<String> divisiones;

  /// Clave → nombre para mostrar en la leyenda (la forma más usada). Incluye
  /// la clave vacía, con "Sin curso asignado", si hay familias sin división.
  final Map<String, String> nombresDivision;

  /// Hay familias sin división cargada.
  final bool haySinDivision;

  /// Familias con números que el armado no tiene (por ejemplo un 200 cargado a
  /// mano): no se dibujan, pero la pantalla avisa.
  final List<({OcupantePlano ocupante, int numero})> fueraDelPlano;

  /// Mesas fijadas que el armado no tiene (se achicó el salón después de
  /// fijarlas): no se dibujan, pero la pantalla avisa.
  final List<({OcupantePlano para, int numero})> fijadasFueraDelPlano;

  /// Mesas marcadas como libres que el armado no tiene.
  final List<int> libresFueraDelPlano;

  EstadoPlano._(
    this._mesas,
    this.divisiones,
    this.nombresDivision,
    this.haySinDivision,
    this.fueraDelPlano,
    this.fijadasFueraDelPlano,
    this.libresFueraDelPlano,
  );

  static final EstadoPlano vacio = EstadoPlano._(
    const {},
    const [],
    const {},
    false,
    const [],
    const [],
    const [],
  );

  InfoMesa info(int numero) => _mesas[numero] ?? InfoMesa(numero: numero);

  Iterable<InfoMesa> get mesas => _mesas.values;

  /// El lugar de una división en la leyenda, como la escribió cada uno
  /// ("5° a"). -1 si no tiene división o no está en el plano.
  int indiceDivision(String? division) {
    final k = Divisiones.clave(division);
    return k.isEmpty ? -1 : divisiones.indexOf(k);
  }

  /// Arma el estado de un armado con sus ocupantes.
  ///
  /// - [libres]: mesas que no se usan.
  /// - [fijadas]: mesa → familia, reservadas antes del sorteo.
  /// - [ordenDivisiones]: el orden de la leyenda, en claves de
  ///   [Divisiones.clave] (como se guarda en el plano de la fiesta); las que no
  ///   tienen familias se saltean. Si falta, van por la mesa más chica de cada
  ///   división (los colores siguen al salón desde el escenario).
  factory EstadoPlano.desde({
    required ArmadoSalon armado,
    List<OcupantePlano> ocupantes = const [],
    Set<int> libres = const {},
    Map<int, OcupantePlano> fijadas = const {},
    List<String>? ordenDivisiones,
  }) {
    final divisiones = _ordenar(ocupantes, fijadas, ordenDivisiones);
    final todos = [...ocupantes, ...fijadas.values];
    final haySinDivision =
        todos.any((o) => Divisiones.clave(o.division).isEmpty);
    final nombres = Divisiones.nombresDe(todos.map((o) => o.division));

    int? indice(OcupantePlano o) {
      final i = divisiones.indexOf(Divisiones.clave(o.division));
      return i < 0 ? null : i;
    }

    final porMesa = <int, List<OcupantePlano>>{};
    final fuera = <({OcupantePlano ocupante, int numero})>[];
    for (final o in ocupantes) {
      for (final n in o.numeros.toSet()) {
        if (!armado.existe(n)) {
          fuera.add((ocupante: o, numero: n));
          continue;
        }
        porMesa.putIfAbsent(n, () => []).add(o);
      }
    }
    final fijadasFuera = [
      for (final e in fijadas.entries)
        if (!armado.existe(e.key)) (para: e.value, numero: e.key),
    ]..sort((a, b) => a.numero.compareTo(b.numero));
    final libresFuera = [
      for (final n in libres)
        if (!armado.existe(n)) n,
    ]..sort();

    bool enConflicto(int n) {
      final lista = porMesa[n] ?? const <OcupantePlano>[];
      final fijada = fijadas[n];
      if (lista.length > 1) return true;
      if (lista.length == 1 && fijada != null && fijada.id != lista.first.id) {
        return true;
      }
      return libres.contains(n) && (lista.isNotEmpty || fijada != null);
    }

    // La mesa que lleva el apellido: la principal entre las que se dibujan y
    // son solo de esa familia. Así un número fuera del plano o en conflicto no
    // deja a la familia sin apellido en ninguna mesa.
    final principalOcupante = <String, int?>{
      for (final o in ocupantes)
        o.id: OcupantePlano.principalDe([
          for (final n in o.numeros.toSet())
            if (armado.existe(n) && !enConflicto(n)) n,
        ]),
    };
    // Antes del sorteo, lo mismo para las fijadas que todavía no tienen
    // familia.
    final fijadasSolas = <String, List<int>>{};
    for (final e in fijadas.entries) {
      final n = e.key;
      if (!armado.existe(n) || enConflicto(n)) continue;
      if ((porMesa[n] ?? const []).isNotEmpty) continue;
      fijadasSolas.putIfAbsent(e.value.id, () => []).add(n);
    }
    final principalFijada = <String, int?>{
      for (final e in fijadasSolas.entries)
        e.key: OcupantePlano.principalDe(e.value),
    };

    final mesas = <int, InfoMesa>{};
    for (final n in armado.numeros) {
      final lista = porMesa[n] ?? const <OcupantePlano>[];
      final fijada = fijadas[n];
      final libre = libres.contains(n);
      if (lista.isEmpty && fijada == null && !libre) continue;
      final quien = lista.isNotEmpty ? lista.first : fijada;
      final EstadoMesa estado;
      if (enConflicto(n)) {
        estado = EstadoMesa.conflicto;
      } else if (lista.isNotEmpty) {
        estado = EstadoMesa.ocupada;
      } else if (fijada != null) {
        estado = EstadoMesa.fijada;
      } else {
        estado = EstadoMesa.libre;
      }
      mesas[n] = InfoMesa(
        numero: n,
        estado: estado,
        ocupantes: lista,
        division: quien == null ? null : indice(quien),
        principal: switch (estado) {
          EstadoMesa.ocupada => principalOcupante[lista.first.id] == n,
          EstadoMesa.fijada => principalFijada[fijada!.id] == n,
          _ => false,
        },
        sillasExtra:
            lista.length == 1 ? lista.first.sillasExtraPorMesa[n] ?? 0 : 0,
        fijadaPara: fijada,
        libre: libre,
      );
    }
    return EstadoPlano._(
      mesas,
      List.unmodifiable(divisiones),
      Map.unmodifiable(nombres),
      haySinDivision,
      fuera,
      fijadasFuera,
      libresFuera,
    );
  }

  /// Las claves de división que tienen familias, en el orden de la leyenda.
  static List<String> _ordenar(
    List<OcupantePlano> ocupantes,
    Map<int, OcupantePlano> fijadas,
    List<String>? orden,
  ) {
    final minimo = <String, int>{};
    void anotar(OcupantePlano o, Iterable<int> numeros) {
      final k = Divisiones.clave(o.division);
      if (k.isEmpty) return;
      var menor = 1 << 30;
      for (final n in numeros) {
        if (n < menor) menor = n;
      }
      final actual = minimo[k];
      if (actual == null || menor < actual) minimo[k] = menor;
    }

    for (final o in ocupantes) {
      anotar(o, o.numeros);
    }
    // Una fijada puede no tener números todavía: se ordena por su mesa.
    for (final e in fijadas.entries) {
      anotar(e.value, [...e.value.numeros, e.key]);
    }
    final resto = minimo.keys.toList()
      ..sort((a, b) {
        final c = minimo[a]!.compareTo(minimo[b]!);
        return c != 0 ? c : a.compareTo(b);
      });
    if (orden == null) return resto;
    final pedido = <String>[];
    for (final d in orden) {
      final k = Divisiones.clave(d);
      if (minimo.containsKey(k) && !pedido.contains(k)) pedido.add(k);
    }
    return [
      ...pedido,
      for (final d in resto)
        if (!pedido.contains(d)) d,
    ];
  }
}
