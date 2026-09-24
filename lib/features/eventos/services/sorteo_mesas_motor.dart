import 'dart:collection';
import 'dart:math';

import '../../../models/contrato_alumno.dart';
import 'mesas_extra_utils.dart';

/// Lo que el sorteo tiene que resolver para un alumno.
class PedidoSorteo {
  final String alumnoId;

  /// Mesas que le corresponden: la base más las extra de su cuenta.
  final int mesas;

  /// Cuántas de esas mesas van sueltas, lejos de su bloque. 0 = todas juntas.
  final int separadas;

  /// Números que ya tiene. Si hay, el sorteo no los mueve: solo agrega los que
  /// faltan (alguien que compró una mesa extra después del sorteo).
  final List<int> actuales;

  const PedidoSorteo({
    required this.alumnoId,
    required this.mesas,
    this.separadas = 0,
    this.actuales = const [],
  });

  bool get esNuevo => actuales.isEmpty;
  int get faltan => mesas - actuales.length;
}

/// Cuántas mesas pide el sorteo y de dónde sale ese número.
class DemandaSorteo {
  /// Alumnos que todavía no tienen mesa.
  final int alumnosNuevos;
  final int mesasBase;
  final int mesasExtras;

  /// Alumnos con menos mesas de las que les corresponden, y cuántas les faltan.
  final int alumnosACompletar;
  final int mesasACompletar;

  const DemandaSorteo({
    required this.alumnosNuevos,
    required this.mesasBase,
    required this.mesasExtras,
    required this.alumnosACompletar,
    required this.mesasACompletar,
  });

  int get total => mesasBase + mesasExtras + mesasACompletar;
  bool get vacia => total == 0;
}

/// Sorteo de mesas de un evento masivo, armado para que no pueda fallar.
///
/// Cada número que se asigna sale de la lista de libres en el mismo paso, así
/// que no hay forma de repetir uno ni de pisar uno ocupado. El azar decide dónde
/// va cada alumno, pero **solo entre ubicaciones que dejan terminar el salón**:
/// antes de aceptar una, se verifica con [_Armado.seCompleta] que el resto
/// todavía entra. Esa verificación hace el mismo recorrido que
/// [capacidadMinima] y [esFactible], y su propia elección está siempre entre
/// las candidatas; por eso, si el salón entra al empezar, el sorteo termina.
///
/// [validar] queda como red final: repasa el resultado entero antes de
/// guardarlo, y no debería encontrar nada nunca.
class SorteoMesasMotor {
  SorteoMesasMotor._();

  /// Números ya ocupados en el evento: los de todos sus alumnos, también los
  /// de baja. Una baja temporal conserva su lugar hasta que alguien lo libere.
  static Set<int> ocupadas(Iterable<ContratoAlumno> alumnos) => {
        for (final a in alumnos)
          ...MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa),
      };

  /// Quiénes entran al sorteo.
  ///
  /// - Alumnos activos sin mesa: se sortean enteros.
  /// - Alumnos activos con menos mesas de las que les corresponden: se completan
  ///   sin mover las que ya tienen.
  /// - Alumnos con un número cargado que no se entiende (letras, por ejemplo):
  ///   **no se tocan**, para no pisar algo escrito a mano.
  static List<PedidoSorteo> pedidos(
    Iterable<ContratoAlumno> alumnos, {
    Map<String, int> separaciones = const {},
  }) {
    final out = <PedidoSorteo>[];
    for (final a in alumnos) {
      if (a.esBajaTemporal) continue;
      final mesas = MesasExtraUtils.cantidadMesasFisicasSorteo(a);
      final texto = a.numeroMesa?.trim() ?? '';
      final actuales =
          MesasExtraUtils.numerosMesaDesdeTexto(texto).toList()..sort();
      if (texto.isNotEmpty && actuales.isEmpty) continue;
      if (actuales.length >= mesas) continue;
      final separadas = actuales.isEmpty
          ? MesasExtraUtils.cantidadAlejadasEfectivas(
              mesas,
              separaciones[a.id] ?? 0,
            )
          : 0;
      out.add(
        PedidoSorteo(
          alumnoId: a.id,
          mesas: mesas,
          separadas: separadas,
          actuales: actuales,
        ),
      );
    }
    return out;
  }

  /// Huella de lo que decide el sorteo: quién está, cuántas mesas le tocan, qué
  /// números tiene y si está de baja. Si cambia entre que se abrió el diálogo
  /// y se tocó SORTEAR, se sortea sobre la lista nueva.
  static String firma(Iterable<ContratoAlumno> alumnos) {
    final filas = [
      for (final a in alumnos)
        '${a.id}|${MesasExtraUtils.cantidadMesasFisicasSorteo(a)}|'
            '${a.numeroMesa?.trim() ?? ''}|${a.esBajaTemporal}',
    ]..sort();
    return filas.join('\n');
  }

  static DemandaSorteo demanda(List<PedidoSorteo> pedidos) {
    var nuevos = 0, extras = 0, aCompletar = 0, faltantes = 0;
    for (final p in pedidos) {
      if (p.esNuevo) {
        nuevos++;
        extras += p.mesas - 1;
      } else {
        aCompletar++;
        faltantes += p.faltan;
      }
    }
    return DemandaSorteo(
      alumnosNuevos: nuevos,
      mesasBase: nuevos,
      mesasExtras: extras,
      alumnosACompletar: aCompletar,
      mesasACompletar: faltantes,
    );
  }

  /// ¿Entra todo con esta capacidad? Es exactamente la cuenta con la que
  /// [sortear] arranca: si esto da true, el sorteo termina.
  static bool esFactible({
    required List<PedidoSorteo> pedidos,
    required Set<int> ocupadas,
    required int capacidad,
  }) {
    if (pedidos.every((p) => p.faltan <= 0)) return true;
    if (capacidad < 1) return false;
    final armado = _Armado.inicial(pedidos, ocupadas, capacidad);
    if (!armado.completar(pedidos)) return false;
    final piezas = _Piezas.de(pedidos);
    return armado.seCompleta(piezas.bloques, piezas.sueltas, piezas.simples);
  }

  /// La capacidad más chica con la que todo entra, para proponerla en el
  /// diálogo. Arranca desde abajo para aprovechar los huecos del salón.
  ///
  /// Todo cabe en el tramo libre que queda por encima del número más alto
  /// ocupado, con un hueco de guarda por cada mesa separada; la búsqueda sigue
  /// bastante más allá de eso, así que siempre devuelve una capacidad que pasa
  /// [esFactible]. Los tests lo verifican con miles de salones.
  static int capacidadMinima({
    required List<PedidoSorteo> pedidos,
    required Set<int> ocupadas,
  }) {
    final necesarias = pedidos.fold<int>(0, (s, p) => s + max(0, p.faltan));
    if (necesarias == 0) return 0;
    final separadas = pedidos.fold<int>(0, (s, p) => s + p.separadas);
    final masAlto = [
      ...ocupadas,
      for (final p in pedidos) ...p.actuales,
    ].fold<int>(0, max);
    final limite = masAlto + 2 * (necesarias + separadas) + 2;
    // Nunca por debajo del número más alto ya asignado: si hay alguien en la
    // mesa 10, el salón tiene por lo menos 10 mesas.
    for (var c = max(necesarias, masAlto); c <= limite; c++) {
      if (esFactible(pedidos: pedidos, ocupadas: ocupadas, capacidad: c)) {
        return c;
      }
    }
    return limite;
  }

  /// Sortea. Devuelve, por alumno, **todos** sus números: los que ya tenía más
  /// los nuevos, ordenados.
  ///
  /// Llamarlo con una capacidad que no pasa [esFactible] es un error de
  /// programación (el diálogo no lo permite), y se corta antes de tocar nada.
  static Map<String, List<int>> sortear({
    required List<PedidoSorteo> pedidos,
    required Set<int> ocupadas,
    required int capacidad,
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    final armado = _Armado.inicial(pedidos, ocupadas, capacidad);
    if (!armado.completar(pedidos)) {
      throw StateError('Con capacidad $capacidad no entran las mesas.');
    }
    // El orden en que se procesa es fijo —el mismo de [esFactible]—; el azar
    // decide dónde va cada uno. Si el orden también fuera al azar, en un salón
    // muy justo podría no coincidir con la cuenta que habilitó el botón.
    final piezas = _Piezas.de(pedidos);
    if (!armado.seCompleta(piezas.bloques, piezas.sueltas, piezas.simples)) {
      throw StateError('Con capacidad $capacidad no entran las mesas.');
    }

    // 1. Bloques de dos o más mesas, de mayor a menor: son los que necesitan
    //    lugar corrido. Cada uno, en un lugar al azar que deje terminar.
    for (var i = 0; i < piezas.bloques.length; i++) {
      final bloque = piezas.bloques[i];
      final resto = piezas.bloques.sublist(i + 1);
      final inicios = armado.iniciosPosibles(bloque.tamano)..shuffle(rng);
      var puesto = false;
      for (final inicio in inicios) {
        final prueba = armado.copia()
          ..ocupar(bloque.alumnoId, _corrido(inicio, bloque.tamano));
        if (prueba.seCompleta(resto, piezas.sueltas, piezas.simples)) {
          armado.ocupar(bloque.alumnoId, _corrido(inicio, bloque.tamano));
          puesto = true;
          break;
        }
      }
      if (!puesto) {
        throw StateError('El sorteo no encontró lugar para un bloque.');
      }
    }

    // 2. Mesas sueltas de quienes pidieron separar: lo más lejos posible de
    //    las suyas, nunca pegadas.
    for (var j = 0; j < piezas.sueltas.length; j++) {
      final suelta = piezas.sueltas[j];
      final resto = piezas.sueltas.sublist(j + 1);
      var puesta = false;
      for (final n in armado.candidatasLejos(suelta.alumnoId, rng)) {
        final prueba = armado.copia()..ocupar(suelta.alumnoId, [n]);
        if (prueba.seCompleta(const [], resto, piezas.simples)) {
          armado.ocupar(suelta.alumnoId, [n]);
          puesta = true;
          break;
        }
      }
      if (!puesta) {
        throw StateError('El sorteo no encontró lugar para una mesa separada.');
      }
    }

    // 3. Los de una sola mesa, en los libres que quedan, al azar.
    final libres = armado.libres.toList()..shuffle(rng);
    final simples = piezas.simplesIds;
    for (var k = 0; k < simples.length; k++) {
      armado.ocupar(simples[k], [libres[k]]);
    }

    return {
      for (final p in pedidos)
        p.alumnoId: (List<int>.from(armado.numeros[p.alumnoId]!)..sort()),
    };
  }

  /// Red de seguridad final. Devuelve `null` si todo está bien, o el motivo.
  static String? validar({
    required List<PedidoSorteo> pedidos,
    required Set<int> ocupadas,
    required int capacidad,
    required Map<String, List<int>> asignaciones,
  }) {
    if (asignaciones.length != pedidos.length) {
      return 'El resultado no coincide con la lista de alumnos a sortear.';
    }
    final usados = <int, String>{};
    for (final p in pedidos) {
      final nums = asignaciones[p.alumnoId];
      if (nums == null) return 'Quedó un alumno sin mesa.';
      if (nums.length != p.mesas) {
        return 'Un alumno recibió ${nums.length} mesas y le corresponden '
            '${p.mesas}.';
      }
      if (nums.toSet().length != nums.length) {
        return 'Un alumno recibió dos veces el mismo número.';
      }
      if (!p.actuales.every(nums.contains)) {
        return 'Se movió un número que el alumno ya tenía.';
      }
      for (final n in nums) {
        if (p.actuales.contains(n)) continue;
        if (n < 1 || n > capacidad) {
          return 'El número $n queda fuera del salón (1 a $capacidad).';
        }
        if (ocupadas.contains(n)) return 'El número $n ya estaba ocupado.';
        if (usados.containsKey(n)) return 'El número $n salió dos veces.';
        usados[n] = p.alumnoId;
      }
      if (p.esNuevo && !_formaCorrecta(nums, p)) {
        return p.separadas == 0
            ? 'Las mesas de un alumno no quedaron juntas.'
            : 'Las mesas separadas de un alumno quedaron pegadas.';
      }
    }
    return null;
  }

  /// Juntas: un solo tramo. Separadas: un tramo de (mesas − separadas) más
  /// [PedidoSorteo.separadas] mesas sueltas, sin que ninguna toque a otra.
  static bool _formaCorrecta(List<int> nums, PedidoSorteo p) {
    final tramos = tramosDe(nums).map((t) => t.length).toList()..sort();
    if (p.separadas == 0) return tramos.length == 1;
    final esperado = [
      for (var i = 0; i < p.separadas; i++) 1,
      p.mesas - p.separadas,
    ]..sort();
    if (tramos.length != esperado.length) return false;
    for (var i = 0; i < tramos.length; i++) {
      if (tramos[i] != esperado[i]) return false;
    }
    return true;
  }

  /// Tramos de números consecutivos, en orden.
  static List<List<int>> tramosDe(Iterable<int> numeros) {
    final ordenados = numeros.toSet().toList()..sort();
    final out = <List<int>>[];
    for (final n in ordenados) {
      if (out.isNotEmpty && out.last.last == n - 1) {
        out.last.add(n);
      } else {
        out.add([n]);
      }
    }
    return out;
  }

  static List<int> _corrido(int inicio, int tamano) =>
      [for (var i = 0; i < tamano; i++) inicio + i];
}

/// Un pedazo del lugar de un alumno: su bloque o una mesa separada.
class _Pieza {
  final String alumnoId;
  final int tamano;
  const _Pieza(this.alumnoId, this.tamano);
}

/// Cómo se reparte el sorteo en piezas, y en qué orden se ubican.
///
/// El orden es parte del contrato con [_Armado.seCompleta]: el sorteo y la
/// verificación recorren las mismas listas, en el mismo orden.
class _Piezas {
  /// Bloques de dos o más mesas, de mayor a menor.
  final List<_Pieza> bloques;

  /// Mesas de a una de quienes separan, agrupadas por alumno.
  final List<_Pieza> sueltas;

  /// Alumnos de una sola mesa.
  final List<String> simplesIds;

  _Piezas(this.bloques, this.sueltas, this.simplesIds);

  int get simples => simplesIds.length;

  /// Orden fijo (por alumno), el mismo para las cuentas y para el sorteo.
  factory _Piezas.de(List<PedidoSorteo> pedidos) {
    final nuevos = pedidos.where((p) => p.esNuevo).toList()
      ..sort((a, b) => a.alumnoId.compareTo(b.alumnoId));

    final bloques = <_Pieza>[];
    final porAlumno = <List<_Pieza>>[];
    final simples = <String>[];
    for (final p in nuevos) {
      final juntas = p.mesas - p.separadas;
      if (p.separadas == 0) {
        if (p.mesas == 1) {
          simples.add(p.alumnoId);
        } else {
          bloques.add(_Pieza(p.alumnoId, p.mesas));
        }
        continue;
      }
      final propias = <_Pieza>[];
      if (juntas >= 2) {
        bloques.add(_Pieza(p.alumnoId, juntas));
      } else {
        propias.add(_Pieza(p.alumnoId, 1));
      }
      for (var i = 0; i < p.separadas; i++) {
        propias.add(_Pieza(p.alumnoId, 1));
      }
      porAlumno.add(propias);
    }
    // De mayor a menor; a igual tamaño, por alumno, para que el orden no
    // dependa de cómo vino la lista.
    bloques.sort((a, b) {
      final c = b.tamano.compareTo(a.tamano);
      return c != 0 ? c : a.alumnoId.compareTo(b.alumnoId);
    });
    return _Piezas(
      bloques,
      [for (final g in porAlumno) ...g],
      simples,
    );
  }
}

/// El salón mientras se arma: qué números quedan libres y cuáles tiene cada
/// alumno del sorteo.
class _Armado {
  final int capacidad;
  final SplayTreeSet<int> libres;
  final Map<String, List<int>> numeros;

  _Armado(this.capacidad, this.libres, this.numeros);

  factory _Armado.inicial(
    List<PedidoSorteo> pedidos,
    Set<int> ocupadas,
    int capacidad,
  ) {
    final libres = SplayTreeSet<int>();
    for (var n = 1; n <= capacidad; n++) {
      if (!ocupadas.contains(n)) libres.add(n);
    }
    return _Armado(capacidad, libres, {
      for (final p in pedidos) p.alumnoId: List<int>.from(p.actuales),
    });
  }

  _Armado copia() => _Armado(
        capacidad,
        SplayTreeSet<int>.of(libres),
        {for (final e in numeros.entries) e.key: List<int>.from(e.value)},
      );

  void ocupar(String alumnoId, Iterable<int> ns) {
    for (final n in ns) {
      libres.remove(n);
      numeros[alumnoId]!.add(n);
    }
  }

  /// Completa a quienes tienen menos mesas de las que les corresponden, sin
  /// mover las que ya tienen: primero pegadas a su tramo más grande; si ahí no
  /// hay lugar, en la libre más cercana. Siempre en el mismo orden, así la
  /// cuenta de capacidad y el sorteo hacen exactamente lo mismo.
  bool completar(List<PedidoSorteo> pedidos) {
    final aCompletar = pedidos.where((p) => !p.esNuevo).toList()
      ..sort((a, b) => a.alumnoId.compareTo(b.alumnoId));
    for (final p in aCompletar) {
      for (var i = 0; i < p.faltan; i++) {
        final n = _proximaAlTramo(numeros[p.alumnoId]!);
        if (n == null) return false;
        ocupar(p.alumnoId, [n]);
      }
    }
    return true;
  }

  int? _proximaAlTramo(List<int> propios) {
    final tramos = SorteoMesasMotor.tramosDe(propios)
      ..sort((a, b) {
        final c = b.length.compareTo(a.length);
        return c != 0 ? c : a.first.compareTo(b.first);
      });
    for (final t in tramos) {
      if (libres.contains(t.last + 1)) return t.last + 1;
      if (libres.contains(t.first - 1)) return t.first - 1;
    }
    int? mejor;
    var mejorDist = 1 << 30;
    for (final n in libres) {
      final d = propios.fold<int>(1 << 30, (m, o) => min(m, (n - o).abs()));
      if (d < mejorDist) {
        mejorDist = d;
        mejor = n;
      }
    }
    return mejor;
  }

  /// ¿Se puede terminar desde acá? Recorrido fijo: bloques en el lugar más
  /// justo que les entre, sueltas lo más lejos posible de lo suyo, y los de una
  /// mesa en lo que sobre.
  bool seCompleta(List<_Pieza> bloques, List<_Pieza> sueltas, int simples) {
    final a = copia();
    for (final b in bloques) {
      final inicio = a._mejorEncaje(b.tamano);
      if (inicio == null) return false;
      a.ocupar(b.alumnoId, SorteoMesasMotor._corrido(inicio, b.tamano));
    }
    for (final s in sueltas) {
      final n = a._masLejos(s.alumnoId);
      if (n == null) return false;
      a.ocupar(s.alumnoId, [n]);
    }
    return a.libres.length >= simples;
  }

  /// Inicio del tramo libre más chico donde entra [tamano]; a igual largo, el
  /// que empieza antes.
  int? _mejorEncaje(int tamano) {
    int? mejorInicio;
    var mejorLargo = 1 << 30;
    for (final t in SorteoMesasMotor.tramosDe(libres)) {
      if (t.length >= tamano && t.length < mejorLargo) {
        mejorLargo = t.length;
        mejorInicio = t.first;
      }
    }
    return mejorInicio;
  }

  /// La libre más lejos de los números del alumno que no toque ninguno; a
  /// igual distancia, la más baja. Sin números todavía, la más baja.
  int? _masLejos(String alumnoId) {
    final propios = numeros[alumnoId]!;
    if (propios.isEmpty) return libres.isEmpty ? null : libres.first;
    int? mejor;
    var mejorDist = 1;
    for (final n in libres) {
      final d = propios.fold<int>(1 << 30, (m, o) => min(m, (n - o).abs()));
      if (d > mejorDist) {
        mejorDist = d;
        mejor = n;
      }
    }
    return mejor;
  }

  /// Inicios donde entra un bloque de [tamano] mesas corridas libres.
  List<int> iniciosPosibles(int tamano) => [
        for (final t in SorteoMesasMotor.tramosDe(libres))
          for (var i = 0; i + tamano <= t.length; i++) t[i],
      ];

  /// Libres que no tocan ningún número del alumno, de la más lejana a la más
  /// cercana; entre las que están igual de lejos, el orden lo decide el azar.
  List<int> candidatasLejos(String alumnoId, Random rng) {
    final propios = numeros[alumnoId]!;
    if (propios.isEmpty) return libres.toList()..shuffle(rng);
    final porDistancia = <int, List<int>>{};
    for (final n in libres) {
      final d = propios.fold<int>(1 << 30, (m, o) => min(m, (n - o).abs()));
      if (d <= 1) continue;
      porDistancia.putIfAbsent(d, () => []).add(n);
    }
    final distancias = porDistancia.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    return [
      for (final d in distancias) ...(porDistancia[d]!..shuffle(rng)),
    ];
  }
}
