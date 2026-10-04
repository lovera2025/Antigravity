import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/services/pago_para_sorteo.dart';
import '../../eventos/services/sorteo_mesas_motor.dart';
import '../modelo/armado_salon.dart';
import 'divisiones.dart';

/// Las mesas del plano puestas en fila para el motor del sorteo.
///
/// El motor entiende que n y n+1 son mesas pegadas. En el plano eso vale casi
/// siempre (la serpentina), salvo en los cortes: otra hoja, las mesas sueltas
/// del medio, el pasto, o un número que no existe. En cada corte se mete un
/// **casillero fantasma**, siempre ocupado: así el motor nunca junta a una
/// familia de un lado y del otro, y no hace falta tocar su algoritmo.
///
/// Orden: primero las mesas comunes por número, después las del pasto.
class CasillerosPlano {
  /// Casillero (desde 1) → número de mesa, o null si es fantasma.
  final List<int?> _numeros;
  final Map<int, int> _casilleroDe;
  final Set<int> pasto;

  CasillerosPlano._(this._numeros, this._casilleroDe, this.pasto);

  factory CasillerosPlano.de(ArmadoSalon armado) {
    final comunes = [for (final m in armado.mesas) if (!m.pasto) m.numero]
      ..sort();
    final delPasto = [for (final m in armado.mesas) if (m.pasto) m.numero]
      ..sort();
    final numeros = <int?>[];
    final casilleroDe = <int, int>{};
    int? anterior;
    for (final n in [...comunes, ...delPasto]) {
      if (anterior != null && !(n == anterior + 1 && armado.pegadas(anterior, n))) {
        numeros.add(null);
      }
      numeros.add(n);
      casilleroDe[n] = numeros.length;
      anterior = n;
    }
    return CasillerosPlano._(numeros, casilleroDe, delPasto.toSet());
  }

  int get total => _numeros.length;

  /// El número de mesa de un casillero (desde 1), o null si es fantasma.
  int? numero(int casillero) => _numeros[casillero - 1];

  int? casillero(int numero) => _casilleroDe[numero];

  Set<int> get fantasmas => {
        for (var i = 0; i < _numeros.length; i++)
          if (_numeros[i] == null) i + 1,
      };

  /// Los números de mesa de los casilleros [desde]..[hasta].
  List<int> numerosEntre(int desde, int hasta) => [
        for (var c = desde; c <= hasta && c <= total; c++)
          if (numero(c) != null) numero(c)!,
      ];
}

/// Todo lo que decide un sorteo sobre el plano.
class EntradaSorteoPlano {
  final ArmadoSalon armado;
  final ConfigPlano config;

  /// Todos los alumnos del evento, también los de baja (conservan su lugar).
  final List<ContratoAlumno> alumnos;
  final ExclusionSorteo exclusion;
  final Map<String, int> separaciones;
  final ModoSorteo modo;

  /// Claves de división ([Divisiones.clave]) en el orden elegido.
  final List<String> ordenDivisiones;
  final bool usarPasto;

  /// Sorteo entero: usar de la mesa 1 a esta. Null: la mínima que alcanza.
  final int? hastaMesa;

  const EntradaSorteoPlano({
    required this.armado,
    this.config = ConfigPlano.vacia,
    required this.alumnos,
    this.exclusion = ExclusionSorteo.ninguna,
    this.separaciones = const {},
    this.modo = ModoSorteo.entera,
    this.ordenDivisiones = const [],
    this.usarPasto = false,
    this.hastaMesa,
  });

  EntradaSorteoPlano conPasto(bool usar) => EntradaSorteoPlano(
        armado: armado,
        config: config,
        alumnos: alumnos,
        exclusion: exclusion,
        separaciones: separaciones,
        modo: modo,
        ordenDivisiones: ordenDivisiones,
        usarPasto: usar,
        hastaMesa: hastaMesa,
      );
}

/// Un renglón del resumen por división del sorteo por bloques.
class FilaBloque {
  final String clave;
  final String nombre;
  final int familias;
  final int mesas;

  /// El bloque, en números de mesa. Null si no entra.
  final int? desde;
  final int? hasta;
  final bool entra;
  final bool usaPasto;

  /// Llegan tarde a un sorteo ya hecho y no entran en su bloque: van a la
  /// reserva, después del último bloque.
  final bool enReserva;

  const FilaBloque({
    required this.clave,
    required this.nombre,
    required this.familias,
    required this.mesas,
    this.desde,
    this.hasta,
    this.entra = true,
    this.usaPasto = false,
    this.enReserva = false,
  });
}

/// Lo que va a pasar si se sortea así. Lo que muestra el diálogo es lo que
/// después hace el sorteo: los mismos bloques y el mismo "entra", salvo quién
/// va a qué mesa adentro de cada bloque ([SorteoConPlano.sortear] lo garantiza).
class PlanSorteo {
  final ModoSorteo modo;

  /// Se pidió por bloques y no se puede (ver [avisos]).
  final bool modoForzado;
  final List<FilaBloque> bloques;

  /// Sorteo entero: hasta qué mesa se usa, y la mínima que alcanza.
  final int? hastaMesa;
  final int? hastaMesaMinima;
  final bool entra;

  /// No entra así, pero entraría usando el pasto.
  final bool necesitaPasto;
  final int familias;
  final int mesas;
  final List<String> avisos;

  const PlanSorteo({
    required this.modo,
    this.modoForzado = false,
    this.bloques = const [],
    this.hastaMesa,
    this.hastaMesaMinima,
    required this.entra,
    this.necesitaPasto = false,
    required this.familias,
    required this.mesas,
    this.avisos = const [],
  });
}

class ResultadoSorteoPlano {
  /// Alumno → todos sus números (los que tenía más los nuevos), ordenados.
  final Map<String, List<int>> asignaciones;

  /// Los bloques del sorteo (vacío si fue entero), para guardar en el plano.
  final List<BloqueDivision> bloques;
  final List<String> avisos;

  const ResultadoSorteoPlano({
    required this.asignaciones,
    this.bloques = const [],
    this.avisos = const [],
  });
}

/// El sorteo de mesas sobre el plano de la fiesta, por bloques de división o
/// entero. **El motor no cambia**: esto arma sus entradas (casilleros, qué está
/// ocupado, cuántos casilleros usar) y traduce la salida a números de mesa.
class SorteoConPlano {
  SorteoConPlano._();

  /// Huella de las divisiones: si alguien cambia de división con el diálogo
  /// abierto, los bloques cambian.
  static String firmaDivisiones(Iterable<ContratoAlumno> alumnos) {
    final filas = [
      for (final a in alumnos) '${a.id}|${Divisiones.clave(a.cursoDivision)}',
    ]..sort();
    return filas.join('\n');
  }

  /// Cuántos repartos distintos prueba la vista previa antes de decir que no
  /// entra, y cuántas veces intenta el sorteo con azar de verdad antes de usar
  /// el reparto de la vista previa.
  static const int _semillasDeLaVista = 12;
  static const int _intentosConAzar = 40;

  /// El plan que se muestra, con la semilla con la que se consiguió.
  ///
  /// Casi siempre no hay nada que elegir: el plan no depende del azar. La
  /// excepción son los que llegan tarde a un sorteo por bloques ya hecho: dónde
  /// cae uno puede dejar sin lugar a otro. Ahí se prueban varios repartos y se
  /// queda con el primero en que entran todos, para no decir "no entra" cuando
  /// sí se puede.
  static ((PlanSorteo, ResultadoSorteoPlano?), int) _planEstable(
    _Base b,
    EntradaSorteoPlano e,
  ) {
    final primero = _calcular(b, e, null);
    final dependeDelAzar = primero.$1.modo == ModoSorteo.bloques &&
        e.config.bloques.isNotEmpty;
    if (primero.entra || !dependeDelAzar) return (primero, 0);
    for (var semilla = 1; semilla < _semillasDeLaVista; semilla++) {
      final otro = _calcular(b, e, null, semillaVista: semilla);
      if (otro.entra) return (otro, semilla);
    }
    return (primero, 0);
  }

  static bool _mismosBloques(PlanSorteo a, PlanSorteo b) {
    if (a.bloques.length != b.bloques.length) return false;
    for (var i = 0; i < a.bloques.length; i++) {
      final x = a.bloques[i];
      final y = b.bloques[i];
      if (x.clave != y.clave ||
          x.desde != y.desde ||
          x.hasta != y.hasta ||
          x.entra != y.entra ||
          x.enReserva != y.enReserva) {
        return false;
      }
    }
    return true;
  }

  static PlanSorteo preparar(EntradaSorteoPlano e) {
    final base = _armar(e);
    final plan = _planEstable(base, e).$1;
    if (plan.entra || e.usarPasto || base.cas.pasto.isEmpty) {
      return plan.$1;
    }
    // ¿Entraría con el pasto?
    final conPasto =
        _planEstable(_armar(e.conPasto(true)), e.conPasto(true)).$1;
    return PlanSorteo(
      modo: plan.$1.modo,
      modoForzado: plan.$1.modoForzado,
      bloques: plan.$1.bloques,
      hastaMesa: plan.$1.hastaMesa,
      hastaMesaMinima: plan.$1.hastaMesaMinima,
      entra: false,
      necesitaPasto: conPasto.entra,
      familias: plan.$1.familias,
      mesas: plan.$1.mesas,
      avisos: plan.$1.avisos,
    );
  }

  /// Sortea. Tira [StateError] si no entra (el diálogo no lo deja llegar acá).
  ///
  /// **Si [preparar] dijo que entra, esto no tira, y los bloques son los que
  /// mostró.** Se sortea con azar de verdad; si un intento no entra o arma
  /// otros bloques (pasa solo cuando dónde cae uno le saca el lugar a otro), se
  /// vuelve a intentar, y como última red se usa el reparto con el que se armó
  /// la vista previa, que ya se sabe que entra.
  static ResultadoSorteoPlano sortear(EntradaSorteoPlano e, {Random? random}) {
    final base = _armar(e);
    final (previa, semilla) = _planEstable(base, e);
    if (!previa.entra) {
      throw StateError('Con este plano no entran las mesas.');
    }
    final rng = random ?? Random.secure();
    for (var i = 0; i < _intentosConAzar; i++) {
      try {
        final r = _calcular(base, e, rng);
        final resultado = r.$2;
        if (resultado != null && _mismosBloques(previa.$1, r.$1)) {
          return resultado;
        }
      } on StateError {
        // Este reparto no entró: se prueba otro.
      }
    }
    return _calcular(base, e, Random(semilla)).$2!;
  }

  /// Red final antes de guardar. Null si está todo bien, o el motivo.
  ///
  /// Mira solo lo que **dio este sorteo**. Lo que cada familia ya tenía no se
  /// juzga: dos familias con el mismo número cargado a mano de antes son un
  /// problema viejo (lo avisa la pantalla), y frenar por eso trabaría el sorteo
  /// de toda la escuela.
  static String? validar(EntradaSorteoPlano e, ResultadoSorteoPlano r) {
    final a = e.armado;
    final libres = e.config.libres.keys.toSet();
    final fijadaPara = {
      for (final f in e.config.fijadas.entries) f.key: f.value.alumnoId,
    };
    final antes = {
      for (final x in e.alumnos)
        x.id: MesasExtraUtils.numerosMesaDesdeTexto(x.numeroMesa),
    };
    // De quién era cada mesa antes de sortear (también de los de baja).
    final eraDe = <int, Set<String>>{};
    for (final x in antes.entries) {
      for (final n in x.value) {
        eraDe.putIfAbsent(n, () => <String>{}).add(x.key);
      }
    }
    final dadaA = <int, String>{};
    for (final entrada in r.asignaciones.entries) {
      final id = entrada.key;
      final nums = entrada.value;
      final suyas = antes[id] ?? const <int>[];
      for (final n in suyas) {
        if (!nums.contains(n)) {
          return 'A una familia se le sacó la mesa $n, que ya tenía.';
        }
      }
      for (final n in nums) {
        if (!a.existe(n)) return 'La mesa $n no está en el plano.';
        // Ya era suya: no la dio este sorteo.
        if (suyas.contains(n)) continue;
        if ((eraDe[n] ?? const <String>{}).any((otro) => otro != id)) {
          return 'La mesa $n ya era de otra familia.';
        }
        final previa = dadaA[n];
        if (previa != null && previa != id) return 'La mesa $n salió dos veces.';
        dadaA[n] = id;
        final para = fijadaPara[n];
        if (para != null) {
          if (para != id) return 'La mesa $n estaba fijada para otra familia.';
          // Fijada para esta familia: vale aunque sea del pasto.
          continue;
        }
        if (libres.contains(n)) return 'La mesa $n estaba libre a propósito.';
        if (!e.usarPasto && a.pasto.contains(n)) {
          return 'La mesa $n es del pasto y no se pidió usarlo.';
        }
      }
      // Una familia nueva (sin mesas antes ni fijadas) tiene que quedar junta
      // de verdad en el salón: números seguidos y mesas pegadas. A quien se le
      // completa una mesa comprada después se le da la más cercana que haya,
      // como hace el sorteo sin plano.
      final nueva = suyas.isEmpty && !e.config.fijadasPorAlumno.containsKey(id);
      if (!nueva) continue;
      if ((e.separaciones[id] ?? 0) == 0 && tramosPegados(a, nums).length > 1) {
        return 'Las mesas de una familia no quedaron juntas.';
      }
    }
    return null;
  }

  /// Los números de una familia, de a tramos de mesas **seguidas y pegadas** en
  /// el salón. Dos números seguidos con un corte en el medio (otra hoja, el
  /// otro lado de la pasarela) son dos tramos: en el salón no están juntas.
  static List<List<int>> tramosPegados(ArmadoSalon a, Iterable<int> numeros) {
    final ordenados = numeros.toSet().toList()..sort();
    final out = <List<int>>[];
    for (final n in ordenados) {
      if (out.isNotEmpty &&
          out.last.last == n - 1 &&
          a.pegadas(out.last.last, n)) {
        out.last.add(n);
      } else {
        out.add([n]);
      }
    }
    return out;
  }

  // ── Por dentro ──────────────────────────────────────────────────────────

  static _Base _armar(EntradaSorteoPlano e) {
    final a = e.armado;
    final cas = CasillerosPlano.de(a);
    final avisos = <String>[];
    final nombres = {for (final x in e.alumnos) x.id: x.nombreAlumno};

    final fijadas = e.config.fijadasPorAlumno;
    // De quién es hoy cada mesa (también de los de baja, que conservan su
    // lugar): una fijada no puede dar una mesa que ya tiene otra familia.
    final duenio = <int, String>{};
    for (final x in e.alumnos) {
      for (final n in MesasExtraUtils.numerosMesaDesdeTexto(x.numeroMesa)) {
        duenio.putIfAbsent(n, () => x.id);
      }
    }
    // Las fijadas que de verdad se pueden dar, por familia. Las que no, quedan
    // reservadas (siguen ocupadas) y se avisa por qué.
    final usables = <String, List<int>>{};
    for (final f in fijadas.entries) {
      final quien = nombres[f.key] ?? 'una familia que ya no está en la fiesta';
      final sirven = <int>[];
      for (final n in f.value) {
        if (!a.existe(n)) {
          avisos.add('La mesa $n está fijada para $quien pero no está en el '
              'plano: no se usa.');
        } else if (duenio[n] != null && duenio[n] != f.key) {
          avisos.add('La mesa $n está fijada para $quien pero ya la tiene '
              '${nombres[duenio[n]] ?? 'otra familia'}: no se usa.');
        } else if (e.config.libres.containsKey(n)) {
          avisos.add('La mesa $n está fijada para $quien y también marcada '
              'como libre: no se usa.');
        } else {
          sirven.add(n);
        }
      }
      usables[f.key] = sirven;
    }

    final pedidosPlano = <PedidoSorteo>[];
    for (final p in SorteoMesasMotor.pedidos(
      e.alumnos,
      separaciones: e.separaciones,
      sinMesa: e.exclusion.sinMesa,
      soloBase: e.exclusion.soloBase,
    )) {
      final fuera = [for (final n in p.actuales) if (!a.existe(n)) n];
      if (fuera.isNotEmpty) {
        avisos.add('${nombres[p.alumnoId]} tiene la mesa ${fuera.join(', ')}, '
            'que no está en el plano: no se toca.');
        continue;
      }
      // Sus fijadas que todavía no tiene: se le dan hasta completar lo que le
      // falta. Vale también para quien ya tiene mesa y compró otra después.
      final propias = [
        for (final n in usables[p.alumnoId] ?? const <int>[])
          if (!p.actuales.contains(n)) n,
      ];
      if (propias.isNotEmpty && p.faltan > 0) {
        final usar = propias.take(p.faltan).toList();
        if (propias.length > p.faltan) {
          avisos.add('${nombres[p.alumnoId]}: tiene fijadas '
              '${propias.join(', ')} pero le falta${p.faltan == 1 ? '' : 'n'} '
              '${p.faltan}. ${propias.skip(p.faltan).join(', ')} queda '
              'reservada.');
        }
        pedidosPlano.add(PedidoSorteo(
          alumnoId: p.alumnoId,
          mesas: p.mesas,
          separadas: p.esNuevo ? 0 : p.separadas,
          actuales: [...p.actuales, ...usar]..sort(),
        ));
      } else {
        pedidosPlano.add(p);
      }
    }
    final deBaja = {
      for (final x in e.alumnos)
        if (x.esBajaTemporal) x.id,
    };
    for (final id in fijadas.keys) {
      if (e.exclusion.sinMesa.contains(id)) {
        avisos.add('${nombres[id] ?? 'Una familia'} tiene mesa fijada pero no '
            'pagó la cuota base: la mesa queda reservada y no se le da.');
      } else if (deBaja.contains(id)) {
        avisos.add('${nombres[id]} tiene mesa fijada pero está de baja: la '
            'mesa queda reservada y no se le da.');
      }
    }

    // Lo ocupado, en números del plano.
    final ocupadasPlano = <int>{
      ...SorteoMesasMotor.ocupadas(e.alumnos).where(a.existe),
      ...e.config.fijadas.keys,
      ...e.config.libres.keys,
      for (final p in pedidosPlano) ...p.actuales,
    };
    final ocupadas = <int>{
      ...cas.fantasmas,
      for (final n in ocupadasPlano)
        if (cas.casillero(n) != null) cas.casillero(n)!,
      if (!e.usarPasto)
        for (final n in cas.pasto) cas.casillero(n)!,
    };

    PedidoSorteo aCasilleros(PedidoSorteo p) => PedidoSorteo(
          alumnoId: p.alumnoId,
          mesas: p.mesas,
          separadas: p.separadas,
          actuales: [for (final n in p.actuales) cas.casillero(n)!],
        );

    final division = {
      for (final x in e.alumnos) x.id: Divisiones.clave(x.cursoDivision),
    };
    // El casillero más alto que ya tiene familia. El pasto no cuenta si no se
    // usa: está al final de la fila y haría parecer que el salón se usó entero.
    final masAltoAsignado = [
      for (final n in {
        ...SorteoMesasMotor.ocupadas(e.alumnos).where(a.existe),
        for (final p in pedidosPlano) ...p.actuales,
      })
        if (e.usarPasto || !cas.pasto.contains(n)) cas.casillero(n) ?? 0,
    ].fold<int>(0, max);
    return _Base(
      cas: cas,
      masAltoAsignado: masAltoAsignado,
      pedidos: [for (final p in pedidosPlano) aCasilleros(p)],
      ocupadas: ocupadas,
      avisos: avisos,
      division: division,
      nombresDivision: Divisiones.nombres(e.alumnos),
      hayNumeros: e.alumnos.any(
        (x) =>
            !x.esBajaTemporal &&
            MesasExtraUtils.numerosMesaDesdeTexto(x.numeroMesa).any(a.existe),
      ),
    );
  }

  /// Calcula el plan y, si hay [rng], además sortea. Devuelve (plan,
  /// resultado); el resultado es null sin [rng] o si no entra.
  static (PlanSorteo, ResultadoSorteoPlano?) _calcular(
    _Base b,
    EntradaSorteoPlano e,
    Random? rng, {
    int semillaVista = 0,
  }) {
    final familias = b.pedidos.length;
    final mesas = b.pedidos.fold<int>(0, (s, p) => s + max(0, p.faltan));
    var modo = e.modo;
    var forzado = false;
    final avisos = [...b.avisos];
    if (modo == ModoSorteo.bloques &&
        b.hayNumeros &&
        e.config.bloques.isEmpty) {
      modo = ModoSorteo.entera;
      forzado = true;
      avisos.add('Ya hay mesas asignadas y el plano no tiene bloques '
          'guardados: se completa entero, sin mover a nadie.');
    }
    if (modo == ModoSorteo.entera) {
      return _entera(b, e, rng, familias, mesas, avisos, forzado);
    }
    return _bloques(b, e, rng, familias, mesas, avisos, semillaVista);
  }

  static int? _minimaCapacidad(
    List<PedidoSorteo> pedidos,
    Set<int> ocupadas,
    int desde,
    int total,
  ) {
    if (pedidos.every((p) => p.faltan <= 0)) {
      // No falta ninguna mesa (por ejemplo, familias con todas sus mesas
      // fijadas): la capacidad tiene que llegar igual hasta la más alta que ya
      // tienen, o el sorteo entero quedaba sin "hasta qué mesa".
      final masAlta = [
        for (final p in pedidos) ...p.actuales,
      ].fold<int>(0, max);
      return max(max(desde - 1, 0), masAlta);
    }
    for (var c = max(desde, 1); c <= total; c++) {
      if (SorteoMesasMotor.esFactible(
        pedidos: pedidos,
        ocupadas: ocupadas,
        capacidad: c,
      )) {
        return c;
      }
    }
    return null;
  }

  /// El número de mesa real más alto hasta el casillero [c].
  static int? _ultimaMesaHasta(CasillerosPlano cas, int c) {
    for (var i = min(c, cas.total); i >= 1; i--) {
      final n = cas.numero(i);
      if (n != null) return n;
    }
    return null;
  }

  static Map<String, List<int>> _aNumeros(
    CasillerosPlano cas,
    Map<String, List<int>> porCasillero,
  ) =>
      {
        for (final x in porCasillero.entries)
          x.key: ([for (final c in x.value) cas.numero(c)!]..sort()),
      };

  static Map<String, List<int>> _sortearEn(
    List<PedidoSorteo> pedidos,
    Set<int> ocupadas,
    int capacidad,
    Random rng,
  ) {
    if (pedidos.isEmpty) return const {};
    final r = SorteoMesasMotor.sortear(
      pedidos: pedidos,
      ocupadas: ocupadas,
      capacidad: capacidad,
      random: rng,
    );
    final error = SorteoMesasMotor.validar(
      pedidos: pedidos,
      ocupadas: ocupadas,
      capacidad: capacidad,
      asignaciones: r,
    );
    if (error != null) throw StateError(error);
    return r;
  }

  static (PlanSorteo, ResultadoSorteoPlano?) _entera(
    _Base b,
    EntradaSorteoPlano e,
    Random? rng,
    int familias,
    int mesas,
    List<String> avisos,
    bool forzado,
  ) {
    final cas = b.cas;
    // Nunca por debajo de la mesa más alta que ya tiene familia, igual que el
    // sorteo sin plano: si no, a quien compró una mesa después se la daba en
    // un hueco del principio del salón en vez de pegada a la suya.
    final minima = _minimaCapacidad(
      b.pedidos,
      b.ocupadas,
      max(1, b.masAltoAsignado),
      cas.total,
    );
    int? capacidad = minima;
    if (e.hastaMesa != null && minima != null) {
      final pedida = cas.casillero(e.hastaMesa!);
      if (pedida != null &&
          pedida >= minima &&
          SorteoMesasMotor.esFactible(
            pedidos: b.pedidos,
            ocupadas: b.ocupadas,
            capacidad: pedida,
          )) {
        capacidad = pedida;
      }
    }
    final entra = capacidad != null;
    final plan = PlanSorteo(
      modo: ModoSorteo.entera,
      modoForzado: forzado,
      hastaMesa: capacidad == null ? null : _ultimaMesaHasta(cas, capacidad),
      hastaMesaMinima: minima == null ? null : _ultimaMesaHasta(cas, minima),
      entra: entra,
      familias: familias,
      mesas: mesas,
      avisos: avisos,
    );
    if (rng == null || !entra) return (plan, null);
    final r = _sortearEn(b.pedidos, b.ocupadas, capacidad, rng);
    return (
      plan,
      ResultadoSorteoPlano(asignaciones: _aNumeros(cas, r), avisos: avisos),
    );
  }

  static (PlanSorteo, ResultadoSorteoPlano?) _bloques(
    _Base b,
    EntradaSorteoPlano e,
    Random? rng,
    int familias,
    int mesas,
    List<String> avisos,
    int semillaVista,
  ) {
    final cas = b.cas;
    final ocupadas = {...b.ocupadas};
    final asignaciones = <String, List<int>>{};
    // La vista previa hace el sorteo entero con una semilla fija: así lo que
    // muestra (bloques, quién entra, quién va a la reserva) es lo mismo que
    // hace el sorteo de verdad, que solo cambia quién va a qué mesa (ver
    // [sortear]).
    final azar = rng ?? Random(semillaVista);

    // 1. Los que ya tienen algo (fijadas, o les falta una mesa comprada
    //    después): se completan al lado de lo suyo, en todo el salón.
    final completar = [for (final p in b.pedidos) if (!p.esNuevo) p];
    if (completar.isNotEmpty) {
      final ok = SorteoMesasMotor.esFactible(
        pedidos: completar,
        ocupadas: ocupadas,
        capacidad: cas.total,
      );
      if (!ok) {
        return (
          PlanSorteo(
            modo: ModoSorteo.bloques,
            entra: false,
            familias: familias,
            mesas: mesas,
            avisos: [...avisos, 'No hay lugar para completar las familias que ya '
                'tienen mesa.'],
          ),
          null,
        );
      }
      final r = _sortearEn(completar, ocupadas, cas.total, azar);
      asignaciones.addAll(r);
      for (final l in r.values) {
        ocupadas.addAll(l);
      }
    }

    // 2. Los nuevos, por división.
    final nuevosPorDivision = <String, List<PedidoSorteo>>{};
    for (final p in b.pedidos.where((p) => p.esNuevo)) {
      nuevosPorDivision.putIfAbsent(b.division[p.alumnoId] ?? '', () => []).add(p);
    }
    final orden = [
      for (final k in e.ordenDivisiones)
        if (nuevosPorDivision.containsKey(k)) k,
      ...Divisiones.ordenNatural(
        nuevosPorDivision.keys.where((k) => !e.ordenDivisiones.contains(k)),
      ),
    ];

    final filas = <FilaBloque>[];
    final bloquesNuevos = <BloqueDivision>[];
    var entraTodo = true;

    FilaBloque fila(String k, List<PedidoSorteo> ps,
            {int? desde, int? hasta, bool entra = true, bool reserva = false}) =>
        FilaBloque(
          clave: k,
          nombre: b.nombresDivision[k] ?? (k.isEmpty ? Divisiones.sinDivision : k),
          familias: ps.length,
          mesas: ps.fold<int>(0, (s, p) => s + p.mesas),
          desde: desde,
          hasta: hasta,
          entra: entra,
          usaPasto: desde != null &&
              hasta != null &&
              cas.pasto.any((n) => n >= desde && n <= hasta),
          enReserva: reserva,
        );

    void anotar(Map<String, List<int>> r) {
      asignaciones.addAll(r);
      for (final l in r.values) {
        ocupadas.addAll(l);
      }
    }

    final guardados = {for (final bl in e.config.bloques) bl.division: bl};
    if (guardados.isNotEmpty) {
      // Un sorteo que ya se hizo: los que llegan tarde van a los huecos de su
      // bloque; si no entran, a la reserva (después del último bloque) y, si
      // tampoco hay, a cualquier mesa libre del salón. Siempre con aviso.
      //
      // Si la mesa del borde de un bloque ya no está (se sacó al acomodar el
      // salón), vale la que queda más cerca adentro del bloque: los huecos
      // siguen siendo de su división.
      int? primerCasillero(BloqueDivision bl) {
        for (var n = bl.desde; n <= bl.hasta; n++) {
          final c = cas.casillero(n);
          if (c != null) return c;
        }
        return null;
      }

      int? ultimoCasillero(BloqueDivision bl) {
        for (var n = bl.hasta; n >= bl.desde; n--) {
          final c = cas.casillero(n);
          if (c != null) return c;
        }
        return null;
      }

      final finBloques = guardados.values
          .map((bl) => ultimoCasillero(bl) ?? 0)
          .fold<int>(0, max);
      final aReserva = <String, List<PedidoSorteo>>{};
      for (final k in orden) {
        final ps = nuevosPorDivision[k]!;
        final bl = guardados[k];
        final ini = bl == null ? null : primerCasillero(bl);
        final fin = bl == null ? null : ultimoCasillero(bl);
        if (ini != null && fin != null) {
          final oc = {
            ...ocupadas,
            for (var c = 1; c <= cas.total; c++)
              if (c < ini || c > fin) c,
          };
          if (SorteoMesasMotor.esFactible(
            pedidos: ps,
            ocupadas: oc,
            capacidad: fin,
          )) {
            filas.add(fila(k, ps, desde: bl!.desde, hasta: bl.hasta));
            anotar(_sortearEn(ps, oc, fin, azar));
            continue;
          }
        }
        aReserva[k] = ps;
      }
      if (aReserva.isNotEmpty) {
        final todos = [for (final ps in aReserva.values) ...ps];
        final despues = {
          ...ocupadas,
          for (var c = 1; c <= finBloques; c++) c,
        };
        var oc = despues;
        var cap = _minimaCapacidad(todos, despues, finBloques + 1, cas.total);
        var dondeVan = 'van después del último bloque';
        if (cap == null) {
          oc = ocupadas;
          cap = _minimaCapacidad(todos, ocupadas, 1, cas.total);
          dondeVan = 'van a mesas libres de otros bloques';
        }
        for (final k in aReserva.keys) {
          final ps = aReserva[k]!;
          filas.add(fila(k, ps, entra: cap != null, reserva: true));
          avisos.add('${ps.length} familia${ps.length == 1 ? '' : 's'} de '
              '${b.nombresDivision[k] ?? k} no entra${ps.length == 1 ? '' : 'n'} '
              'en su bloque: ${cap == null ? 'no hay lugar' : dondeVan}.');
        }
        if (cap == null) {
          entraTodo = false;
        } else {
          anotar(_sortearEn(todos, oc, cap, azar));
        }
      }
    } else {
      // El primer sorteo: cada división, en el orden elegido, en el bloque más
      // chico donde entra, seguido del anterior.
      var cursor = 1;
      for (final k in orden) {
        final ps = nuevosPorDivision[k]!;
        final oc = {
          ...ocupadas,
          for (var c = 1; c < cursor; c++) c,
        };
        final fin = entraTodo
            ? _minimaCapacidad(ps, oc, cursor, cas.total)
            : null;
        if (fin == null) {
          entraTodo = false;
          filas.add(fila(k, ps, entra: false));
          continue;
        }
        // El bloque empieza en la primera mesa que se puede usar: no en un
        // corte, ni en una libre o fijada que quedó antes.
        var inicio = cursor;
        while (inicio < fin && oc.contains(inicio)) {
          inicio++;
        }
        final numeros = cas.numerosEntre(inicio, fin);
        final desde = numeros.isEmpty ? null : numeros.first;
        final hasta = numeros.isEmpty ? null : numeros.last;
        filas.add(fila(k, ps, desde: desde, hasta: hasta));
        if (desde != null && hasta != null) {
          bloquesNuevos.add(BloqueDivision(k, desde, hasta));
        }
        anotar(_sortearEn(ps, oc, fin, azar));
        cursor = fin + 1;
      }
    }

    final plan = PlanSorteo(
      modo: ModoSorteo.bloques,
      bloques: filas,
      entra: entraTodo,
      familias: familias,
      mesas: mesas,
      avisos: avisos,
    );
    if (rng == null || !entraTodo) return (plan, null);
    return (
      plan,
      ResultadoSorteoPlano(
        asignaciones: _aNumeros(cas, asignaciones),
        bloques: guardados.isNotEmpty ? e.config.bloques : bloquesNuevos,
        avisos: avisos,
      ),
    );
  }
}

extension on (PlanSorteo, ResultadoSorteoPlano?) {
  bool get entra => $1.entra;
}

class _Base {
  final CasillerosPlano cas;

  /// El casillero más alto que ya tiene familia (0 si nadie tiene mesa).
  final int masAltoAsignado;
  final List<PedidoSorteo> pedidos;
  final Set<int> ocupadas;
  final List<String> avisos;
  final Map<String, String> division;
  final Map<String, String> nombresDivision;
  final bool hayNumeros;

  _Base({
    required this.cas,
    required this.masAltoAsignado,
    required this.pedidos,
    required this.ocupadas,
    required this.avisos,
    required this.division,
    required this.nombresDivision,
    required this.hayNumeros,
  });
}
