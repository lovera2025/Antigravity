import 'dart:math';

import '../../../models/entradas_retiro.dart';
import '../../eventos/services/retiro_entradas.dart';
import '../datos/anulacion_entradas.dart';
import '../datos/venta_entradas.dart';
import 'lugares_de_la_familia.dart';
import 'para_rendir.dart' show BloqueParaRendir;

/// Un número anotado dos veces **en el mismo talonario**: en dos ventas (el de
/// las anticipadas) o en dos entregas sin cargo (el de las generales de los
/// alumnos). Pasa cuando dos equipos venden o entregan sin internet: **no se
/// puede evitar, se avisa cuando se juntan.**
///
/// Una venta y una entrega con el mismo número no son un repetido: son dos
/// talonarios distintos (ver [NumerosDeEntradas]).
class NumeroRepetido {
  /// El primer número que comparten.
  final int numero;

  /// A nombre de quién está cada uno.
  final String uno;
  final String otro;

  /// Si son dos entregas sin cargo (el talonario de las generales) y no dos
  /// ventas (el de las anticipadas).
  final bool enEntregas;

  const NumeroRepetido({
    required this.numero,
    required this.uno,
    required this.otro,
    this.enEntregas = false,
  });

  /// "El 1043 está en dos ventas (A y B): revisar."
  String get texto {
    final donde = enEntregas ? 'entregas' : 'ventas';
    if (uno == otro) return 'El $numero está en dos $donde de $uno: revisar.';
    return 'El $numero está en dos $donde ($uno y $otro): revisar.';
  }
}

/// Un número de las entradas para rendir que está también en una venta o en
/// otro bloque (21-nov-2026). Pasa cuando el jefe da sin internet, o cuando una
/// tablet que no conocía el bloque vende ese número: **no se puede evitar, se
/// avisa en PARA RENDIR cuando se juntan.**
class NumeroCruzado {
  /// El primer número que comparten.
  final int numero;

  /// El bloque y a quién se le dio.
  final String bloqueId;
  final String persona;

  /// El otro: el comprador de la venta, o a quién se le dio el otro bloque.
  final String otro;

  /// La venta, si el cruce es con una venta.
  final String? ventaId;

  /// El otro bloque, si el cruce es entre dos bloques.
  final String? otroBloqueId;

  const NumeroCruzado({
    required this.numero,
    required this.bloqueId,
    required this.persona,
    required this.otro,
    this.ventaId,
    this.otroBloqueId,
  });

  bool get conUnaVenta => otroBloqueId == null;

  String get texto {
    if (conUnaVenta) {
      return 'El $numero se le dio a $persona para rendir y también está en una '
          'venta a $otro: revisar.';
    }
    if (persona == otro) {
      return 'El $numero está dos veces en las que se le dieron a $persona para '
          'rendir: revisar.';
    }
    return 'El $numero se le dio para rendir a $persona y también a $otro: revisar.';
  }
}

/// Los números del talonario de las entradas. **Son dos talonarios, y cada uno
/// se mira solo consigo mismo** (lo confirmó el usuario el 20-nov, con el audio
/// del jefe):
/// - **el de las anticipadas**: todo lo que se vende, al público y lo A PAGAR
///   de las familias (la mesa adicional y las sillas). Se guarda en
///   `entradas_ventas.numeros`, y lo valida VENDER con [ocupadosDeLaVenta];
/// - **el de las generales de los alumnos**, lo que se entrega sin cargo: es
///   otro material, con su propia numeración (o sin número). Lo valida la
///   entrega con [ocupadosDeLaEntrega].
///
/// Hasta la 6.9.2 iban juntos, y el 5 de un talonario frenaba el 5 del otro.
/// **No hay una cuenta que junte los dos grupos**, a propósito: que no vuelva.
///
/// **Las entradas para rendir son del talonario de las anticipadas** (21-nov):
/// los números de un bloque que alguien se llevó para vender por su cuenta
/// quedan reservados ([ocupadosParaRendir]) y VENDER no los vende
/// ([ocupadosAlVender]). La entrega sin cargo no los mira: es el otro
/// talonario.
///
/// Los números **son opcionales**; si se anotan, se validan con las mismas
/// reglas y las mismas palabras que la entrega (`RetiroEntradas.errorTramos`).
class NumerosDeEntradas {
  NumerosDeEntradas._();

  /// Cómo se nombra al comprador de una venta anulada cuyas entradas no
  /// volvieron: esos números quedan anulados para siempre.
  static const sinDevolver = '(venta anulada, sin devolver)';

  /// A nombre de quién quedan los números de [v], o null si no ocupan nada:
  /// una venta sin números, o anulada **con** las entradas devueltas.
  static String? _aNombreDe(VentaEntradas v, AnulacionEntradas? anulacion) {
    if (TramoTalonario.deTexto(v.numeros).isEmpty) return null;
    if (anulacion == null) return v.compradorNombre;
    return anulacion.devueltas ? null : '${v.compradorNombre} $sinDevolver';
  }

  /// Los números de las anticipadas que ya tienen dueño (comprador → tramos).
  /// Cuentan los de una venta que cuenta y los de una **anulada sin
  /// devolver**; los de una anulada con las entradas devueltas vuelven a
  /// quedar libres. [salvo] es el id de una venta que no se mira.
  ///
  /// **Es el `deOtros` de VENDER**: no mira lo entregado sin cargo, que es
  /// otro talonario.
  static Map<String, List<TramoTalonario>> ocupadosDeLaVenta(
    Iterable<VentaEntradas> ventas,
    Iterable<AnulacionEntradas> anulaciones, {
    String? salvo,
  }) {
    final anuladas = anulacionesPorVenta(anulaciones);
    final out = <String, List<TramoTalonario>>{};
    for (final v in ventas) {
      if (v.id == salvo) continue;
      final nombre = _aNombreDe(v, anuladas[v.id]);
      if (nombre == null) continue;
      out.putIfAbsent(nombre, () => []).addAll(TramoTalonario.deTexto(v.numeros));
    }
    return out;
  }

  /// Cómo se nombra a quien tiene números para rendir: "PÉREZ, JUAN, para
  /// rendir". Así VENDER y DAR dicen "El 1205 ya se le dio a PÉREZ, JUAN, para
  /// rendir (1201 al 1220)." con las palabras de siempre. Con una coma y no
  /// entre paréntesis (21-nov-2026): el tramo ya va entre paréntesis, y dos
  /// seguidos se leían mal.
  static const paraRendir = 'para rendir';

  /// Los números de las anticipadas que están en manos de alguien para rendir
  /// (nombre → tramos): los de cada bloque menos los que devolvió. **Lo
  /// vendido y lo que no volvió siguen ocupados**; un bloque anulado no ocupa
  /// nada (`BloqueParaRendir.numerosOcupados`). Dos bloques de la misma
  /// persona juntan sus números.
  static Map<String, List<TramoTalonario>> ocupadosParaRendir(
    Iterable<BloqueParaRendir> bloques,
  ) {
    final out = <String, List<TramoTalonario>>{};
    for (final b in bloques) {
      if (b.numerosOcupados.isEmpty) continue;
      out.putIfAbsent('${b.persona}, $paraRendir', () => []).addAll(b.numerosOcupados);
    }
    return out;
  }

  /// **El `deOtros` de VENDER y de DAR ENTRADAS PARA RENDIR**: todo lo del
  /// talonario de las anticipadas que ya tiene dueño, lo vendido
  /// ([ocupadosDeLaVenta]) y lo que está para rendir ([ocupadosParaRendir]).
  /// No mira lo entregado sin cargo: es el otro talonario.
  static Map<String, List<TramoTalonario>> ocupadosAlVender(
    Iterable<VentaEntradas> ventas,
    Iterable<AnulacionEntradas> anulaciones,
    Iterable<BloqueParaRendir> bloques,
  ) {
    final out = ocupadosDeLaVenta(ventas, anulaciones);
    for (final e in ocupadosParaRendir(bloques).entries) {
      out.putIfAbsent(e.key, () => []).addAll(e.value);
    }
    return out;
  }

  /// El primer número desde [desde] (del 1 en adelante) que no tiene dueño en
  /// [ocupados], con lugar para [cantidad] seguidos. Lo usa VENDER al proponer
  /// el "del" (21-nov-2026): el que sigue al último de la caja puede ser de un
  /// bloque para rendir, y entonces propone el primero después.
  static int primeroLibreDesde(
    int desde,
    Map<String, List<TramoTalonario>> ocupados, {
    int cantidad = 1,
  }) {
    final tomados = [for (final l in ocupados.values) ...l];
    final largo = max(1, cantidad);
    var n = max(1, desde);
    while (true) {
      final pedido = TramoTalonario(n, n + largo - 1);
      final pisa = [
        for (final t in tomados)
          if (pedido.seCruzaCon(t)) t.hasta,
      ];
      if (pisa.isEmpty) return n;
      // Cada vuelta salta detrás de un tramo ocupado: termina siempre.
      n = pisa.reduce(max) + 1;
    }
  }

  /// Los números de los bloques para rendir que están también en una venta o
  /// en otro bloque, del más bajo al más alto. **Solo avisa** (en PARA
  /// RENDIR): nada se corrige solo. Cuenta lo mismo que frena VENDER: los
  /// números que el bloque todavía ocupa, y los de una venta que cuenta o
  /// anulada sin devolver.
  static List<NumeroCruzado> repetidosConParaRendir(
    Iterable<BloqueParaRendir> bloques,
    Iterable<VentaEntradas> ventas,
    Iterable<AnulacionEntradas> anulaciones,
  ) {
    final anuladas = anulacionesPorVenta(anulaciones);
    final vendidos = <({String id, String nombre, List<TramoTalonario> tramos})>[];
    for (final v in ventas) {
      final nombre = _aNombreDe(v, anuladas[v.id]);
      if (nombre == null) continue;
      vendidos.add((id: v.id, nombre: nombre, tramos: TramoTalonario.deTexto(v.numeros)));
    }
    final conNumeros = [
      for (final b in bloques)
        if (b.numerosOcupados.isNotEmpty) b,
    ];

    final out = <NumeroCruzado>[];
    for (var i = 0; i < conNumeros.length; i++) {
      final b = conNumeros[i];
      for (final v in vendidos) {
        final n = _primeroEnComun(b.numerosOcupados, v.tramos);
        if (n == null) continue;
        out.add(NumeroCruzado(
          numero: n,
          bloqueId: b.id,
          persona: b.persona,
          otro: v.nombre,
          ventaId: v.id,
        ));
      }
      for (var j = i + 1; j < conNumeros.length; j++) {
        final otro = conNumeros[j];
        final n = _primeroEnComun(b.numerosOcupados, otro.numerosOcupados);
        if (n == null) continue;
        out.add(NumeroCruzado(
          numero: n,
          bloqueId: b.id,
          persona: b.persona,
          otro: otro.persona,
          otroBloqueId: otro.id,
        ));
      }
    }
    out.sort((a, b) => a.numero.compareTo(b.numero));
    return out;
  }

  /// Los números de las generales que ya se entregaron sin cargo (nombre →
  /// tramos). [entregados] llega armado: hoy, lo que da
  /// `RetiroEntradas.tramosDeOtros` sin el alumno que se está entregando.
  ///
  /// **Es el `deOtros` de la entrega**: no mira lo vendido, que es el
  /// talonario de las anticipadas. Devuelve una copia, sin los nombres que no
  /// tienen números.
  static Map<String, List<TramoTalonario>> ocupadosDeLaEntrega(
    Map<String, List<TramoTalonario>> entregados,
  ) =>
      {
        for (final e in entregados.entries)
          if (e.value.isNotEmpty) e.key: [...e.value],
      };

  /// El número de las anticipadas que VENDER propone (20-nov-2026): **el que
  /// sigue al último que vendió la caja [cajaId]**, o null si esa caja todavía
  /// no vendió nada con números. Quien vende lo puede cambiar o borrar (sin
  /// número se vende igual: son opcionales).
  ///
  /// "El último" es el de su venta más nueva con números (por el número del
  /// comprobante, que es de la caja), y de esa venta el más alto. No cuenta una
  /// venta anulada con las entradas devueltas: esos números volvieron al
  /// talonario y se pueden volver a vender.
  static int? siguienteDeLaCaja(
    String cajaId,
    Iterable<VentaEntradas> ventas,
    Iterable<AnulacionEntradas> anulaciones,
  ) {
    final anuladas = anulacionesPorVenta(anulaciones);
    final deLaCaja = [
      for (final v in ventas)
        if (v.cajaEntradasId == cajaId) v,
    ]..sort((a, b) => b.numero.compareTo(a.numero));
    for (final v in deLaCaja) {
      if (_aNombreDe(v, anuladas[v.id]) == null) continue;
      final tramos = TramoTalonario.deTexto(v.numeros);
      return tramos.map((t) => t.hasta).reduce(max) + 1;
    }
    return null;
  }

  /// Qué está mal en los números de una venta de [cantidad] entradas, o null
  /// si están bien. **Sin números está bien**: son opcionales. [ocupados] es
  /// lo que da [ocupadosDeLaVenta].
  static String? error({
    required List<TramoTalonario> tramos,
    required int cantidad,
    Map<String, List<TramoTalonario>> ocupados = const {},
  }) {
    if (tramos.isEmpty) return null;
    if (cantidad < 1) return 'La venta no lleva entradas: sacá los números.';
    final bienEscritos = tramos.every((t) => t.desde >= 1 && t.hasta >= t.desde);
    if (bienEscritos) {
      final total = tramos.fold<int>(0, (s, t) => s + t.cantidad);
      if (total != cantidad) {
        return '${total == 1 ? 'Es 1 número' : 'Son $total números'} y la venta '
            'lleva ${cantidad == 1 ? '1 entrada' : '$cantidad entradas'}.';
      }
    }
    // Todo lo demás (al revés, pisados, ya dados a otro) lo dice la entrega,
    // con sus palabras.
    return RetiroEntradas.errorTramos(
      tramos: tramos,
      generales: cantidad,
      deOtros: ocupados,
    );
  }

  /// El número más bajo que está en [a] y en [b], o null si no comparten
  /// ninguno.
  static int? _primeroEnComun(List<TramoTalonario> a, List<TramoTalonario> b) {
    int? menor;
    for (final x in a) {
      for (final y in b) {
        if (!x.seCruzaCon(y)) continue;
        final n = max(x.desde, y.desde);
        if (menor == null || n < menor) menor = n;
      }
    }
    return menor;
  }

  /// Los números de las anticipadas anotados en dos ventas, del más bajo al
  /// más alto. **Solo avisa**: nada se corrige solo.
  static List<NumeroRepetido> repetidosDeLaVenta(
    Iterable<VentaEntradas> ventas,
    Iterable<AnulacionEntradas> anulaciones,
  ) {
    final anuladas = anulacionesPorVenta(anulaciones);
    final conNumeros = <({String nombre, List<TramoTalonario> tramos})>[];
    for (final v in ventas) {
      final nombre = _aNombreDe(v, anuladas[v.id]);
      if (nombre == null) continue;
      conNumeros.add((nombre: nombre, tramos: TramoTalonario.deTexto(v.numeros)));
    }

    final out = <NumeroRepetido>[];
    for (var i = 0; i < conNumeros.length; i++) {
      for (var j = i + 1; j < conNumeros.length; j++) {
        final n = _primeroEnComun(conNumeros[i].tramos, conNumeros[j].tramos);
        if (n == null) continue;
        out.add(NumeroRepetido(
          numero: n,
          uno: conNumeros[i].nombre,
          otro: conNumeros[j].nombre,
        ));
      }
    }
    out.sort((a, b) => a.numero.compareTo(b.numero));
    return out;
  }

  /// Los números de las generales anotados en dos entregas sin cargo, del más
  /// bajo al más alto. [entregados] es nombre → tramos de **todas** las
  /// entregas vigentes (`RetiroEntradas.tramosDeOtros` con `salvo: ''`).
  /// **Solo avisa**: nada se corrige solo.
  ///
  /// Hasta la 6.9.2 no se miraba: dos entregas sin internet con los mismos
  /// números no se avisaban nunca. Como `tramosDeOtros` junta a los alumnos
  /// del mismo nombre, también se mira dentro de cada nombre: ahí, dos tramos
  /// que se pisan son dos entregas (una sola entrega no deja pisarlos).
  static List<NumeroRepetido> repetidosDeLaEntrega(
    Map<String, List<TramoTalonario>> entregados,
  ) {
    final conNumeros = [
      for (final e in entregados.entries)
        if (e.value.isNotEmpty) (nombre: e.key, tramos: e.value),
    ];

    final out = <NumeroRepetido>[];
    for (var i = 0; i < conNumeros.length; i++) {
      final (:nombre, :tramos) = conNumeros[i];
      int? dentro;
      for (var a = 0; a < tramos.length; a++) {
        for (var b = a + 1; b < tramos.length; b++) {
          if (!tramos[a].seCruzaCon(tramos[b])) continue;
          final n = max(tramos[a].desde, tramos[b].desde);
          if (dentro == null || n < dentro) dentro = n;
        }
      }
      if (dentro != null) {
        out.add(NumeroRepetido(
          numero: dentro,
          uno: nombre,
          otro: nombre,
          enEntregas: true,
        ));
      }
      for (var j = i + 1; j < conNumeros.length; j++) {
        final n = _primeroEnComun(tramos, conNumeros[j].tramos);
        if (n == null) continue;
        out.add(NumeroRepetido(
          numero: n,
          uno: nombre,
          otro: conNumeros[j].nombre,
          enEntregas: true,
        ));
      }
    }
    out.sort((a, b) => a.numero.compareTo(b.numero));
    return out;
  }
}
