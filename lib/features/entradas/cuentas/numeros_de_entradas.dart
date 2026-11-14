import 'dart:math';

import '../../../models/entradas_retiro.dart';
import '../../eventos/services/retiro_entradas.dart';
import '../datos/anulacion_entradas.dart';
import '../datos/venta_entradas.dart';
import 'lugares_de_la_familia.dart';

/// Un número del talonario que quedó anotado dos veces: en dos ventas, o en
/// una venta y en una entrega sin cargo. Pasa cuando dos equipos venden sin
/// internet: **no se puede evitar, se avisa cuando se juntan.**
class NumeroRepetido {
  /// El primer número que comparten.
  final int numero;

  /// A nombre de quién está cada uno.
  final String uno;
  final String otro;

  /// Si [otro] es una entrega sin cargo y no una venta.
  final bool conUnaEntrega;

  const NumeroRepetido({
    required this.numero,
    required this.uno,
    required this.otro,
    this.conUnaEntrega = false,
  });

  /// "El 1043 está en dos ventas (A y B): revisar."
  String get texto {
    if (conUnaEntrega) {
      return 'El $numero está en una venta ($uno) y en una entrega ($otro): revisar.';
    }
    if (uno == otro) return 'El $numero está en dos ventas de $uno: revisar.';
    return 'El $numero está en dos ventas ($uno y $otro): revisar.';
  }
}

/// Los números del talonario de las entradas vendidas. **Son opcionales**; si
/// se anotan, se validan con las mismas reglas y las mismas palabras que la
/// entrega sin cargo (`RetiroEntradas.errorTramos`), y no pueden repetir uno ya
/// entregado ni uno ya vendido.
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

  /// Los números que ocupan las ventas (comprador → tramos). Cuentan los de
  /// una venta que cuenta y los de una **anulada sin devolver**; los de una
  /// anulada con las entradas devueltas vuelven a quedar libres. [salvo] es el
  /// id de una venta que no se mira.
  static Map<String, List<TramoTalonario>> deLasVentas(
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

  /// Todos los números que ya tienen dueño: los entregados sin cargo
  /// ([entregados], lo que da `RetiroEntradas.tramosDeOtros`) más los vendidos.
  ///
  /// **Es el `deOtros` de `errorTramos` para la venta y para la entrega**: así
  /// "El 1043 ya se le dio a…" sirve para los dos.
  static Map<String, List<TramoTalonario>> ocupados({
    Map<String, List<TramoTalonario>> entregados = const {},
    Iterable<VentaEntradas> ventas = const [],
    Iterable<AnulacionEntradas> anulaciones = const [],
    String? salvoVenta,
  }) {
    final out = <String, List<TramoTalonario>>{
      for (final e in entregados.entries) e.key: [...e.value],
    };
    final vendidos = deLasVentas(ventas, anulaciones, salvo: salvoVenta);
    for (final e in vendidos.entries) {
      out.putIfAbsent(e.key, () => []).addAll(e.value);
    }
    return out;
  }

  /// Qué está mal en los números de una venta de [cantidad] entradas, o null
  /// si están bien. **Sin números está bien**: son opcionales.
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

  /// Los números que quedaron anotados dos veces, del más bajo al más alto:
  /// entre dos ventas, o entre una venta y una entrega sin cargo. **Solo
  /// avisa**: nada se corrige solo.
  static List<NumeroRepetido> repetidos({
    required Iterable<VentaEntradas> ventas,
    required Iterable<AnulacionEntradas> anulaciones,
    Map<String, List<TramoTalonario>> entregados = const {},
  }) {
    final anuladas = anulacionesPorVenta(anulaciones);
    final conNumeros = <({String nombre, List<TramoTalonario> tramos})>[];
    for (final v in ventas) {
      final nombre = _aNombreDe(v, anuladas[v.id]);
      if (nombre == null) continue;
      conNumeros.add((nombre: nombre, tramos: TramoTalonario.deTexto(v.numeros)));
    }

    int? primeroEnComun(List<TramoTalonario> a, List<TramoTalonario> b) {
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

    final out = <NumeroRepetido>[];
    for (var i = 0; i < conNumeros.length; i++) {
      for (var j = i + 1; j < conNumeros.length; j++) {
        final n = primeroEnComun(conNumeros[i].tramos, conNumeros[j].tramos);
        if (n == null) continue;
        out.add(NumeroRepetido(
          numero: n,
          uno: conNumeros[i].nombre,
          otro: conNumeros[j].nombre,
        ));
      }
      for (final e in entregados.entries) {
        final n = primeroEnComun(conNumeros[i].tramos, e.value);
        if (n == null) continue;
        out.add(NumeroRepetido(
          numero: n,
          uno: conNumeros[i].nombre,
          otro: e.key,
          conUnaEntrega: true,
        ));
      }
    }
    out.sort((a, b) => a.numero.compareTo(b.numero));
    return out;
  }
}
