import '../datos/barra_repositorio.dart';
import 'vales_de_barra.dart';

/// Una venta de la caja de la cajera, con lo que se puede hacer con ella: **reimprimir
/// sus vales con freno**, imprimir los que nunca salieron, anularla y sacar el ticket
/// con precios. Cuenta pura: no lee la base ni imprime.
///
/// **El freno de la copia** (decidido el 3-nov, "contra el engaño, sin aparato"): la
/// cajera reimprime **solo la última venta de su caja, una vez**, con motivo. Cada copia
/// sale con COPIA arriba y abajo, quién, cuándo y por qué, y "Se entrega solo con el
/// jefe". El jefe reimprime cualquiera (etapa 7, desde la PC).
///
/// Una copia saca **el mismo vale que salió** (sus bebidas y su número). Si una copia se
/// cortó a la mitad (la impresora se apagó), lo que no salió se puede terminar: el freno
/// es por vale, una copia cada uno.
class VentaDeLaCaja {
  final VentaBarra venta;
  final AnulacionBarra? anulacion;

  /// Los papeles que salieron de esta venta: originales y copias.
  final List<ValeBarra> vales;

  /// Si es la última venta de la caja (la de número más alto).
  final bool esLaUltima;

  const VentaDeLaCaja({
    required this.venta,
    this.anulacion,
    this.vales = const [],
    required this.esLaUltima,
  });

  /// Las ventas de una caja, **la última primero**, cada una con su anulación y sus
  /// vales. Lo de otras ventas se ignora.
  static List<VentaDeLaCaja> armar({
    required List<VentaBarra> ventas,
    required List<AnulacionBarra> anulaciones,
    required List<ValeBarra> vales,
  }) {
    if (ventas.isEmpty) return const [];
    final ultima = ventas.map((v) => v.numero).reduce((a, b) => a > b ? a : b);
    final ordenadas = [...ventas]..sort((a, b) => b.numero.compareTo(a.numero));
    return [
      for (final v in ordenadas)
        VentaDeLaCaja(
          venta: v,
          anulacion: anulaciones.where((a) => a.ventaId == v.id).firstOrNull,
          vales: [for (final x in vales) if (x.ventaId == v.id) x],
          esLaUltima: v.numero == ultima,
        ),
    ];
  }

  bool get anulada => anulacion != null;

  /// Los vales que salieron la primera vez, por su número (el único, sin número, primero).
  List<ValeBarra> get originales =>
      [for (final v in vales) if (!v.esCopia) v]..sort((a, b) => (a.numeroVale ?? 0).compareTo(b.numeroVale ?? 0));

  List<ValeBarra> get copias => [for (final v in vales) if (v.esCopia) v];

  /// Las copias que ya salieron de [original].
  int copiasDe(ValeBarra original) =>
      copias.where((c) => c.numeroVale == original.numeroVale).length;

  /// Los originales que todavía no tienen copia.
  List<ValeBarra> get sinCopia => [for (final o in originales) if (copiasDe(o) == 0) o];

  /// Cuántas unidades de la venta todavía no salieron en ningún vale.
  int get unidadesSinVale {
    final salieron = originales.fold<int>(
      0,
      (s, v) => s + v.bebidas.fold<int>(0, (t, b) => t + b.cantidad),
    );
    final quedan = venta.unidades - salieron;
    return quedan < 0 ? 0 : quedan;
  }

  /// Si quedan bebidas sin vale: salió sin impresora, o se dejó a la mitad.
  bool get faltanVales => !anulada && unidadesSinVale > 0;

  /// Null si la cajera puede reimprimir; si no, por qué no, en palabras.
  String? get porQueNoSeReimprime {
    if (anulada) return 'Anulada: no se reimprime';
    if (originales.isEmpty) return 'No salió ningún vale todavía';
    if (!esLaUltima) return 'Solo se reimprime la última venta';
    if (sinCopia.isEmpty) return 'Ya se reimprimió: otra copia, solo el jefe';
    return null;
  }

  bool get sePuedeReimprimir => porQueNoSeReimprime == null;

  /// Los vales de la copia, en orden, cada uno con su marca de COPIA: los que todavía no
  /// tienen. Vacío si no se puede reimprimir. Sin motivo es un error del programa.
  List<({Vale vale, CopiaDeVale copia})> copia({
    required String motivo,
    String? hechoPor,
    required DateTime ahora,
  }) {
    if (!sePuedeReimprimir) return const [];
    final m = motivo.trim();
    if (m.isEmpty) throw ArgumentError.value(motivo, 'motivo', 'reimprimir lleva motivo');
    return [
      for (final o in sinCopia)
        (
          vale: Vale.comoSalio(o),
          copia: CopiaDeVale(
            numero: copiasDe(o) + 1,
            createdAt: ahora.toUtc().toIso8601String(),
            hechoPor: hechoPor,
            motivo: m,
          ),
        ),
    ];
  }

  /// Null si la cajera puede anularla; si no, por qué no.
  String? get porQueNoSeAnula => anulada ? 'Ya está anulada' : null;

  /// Null si se puede sacar el ticket con precios; si no, por qué no.
  String? get porQueNoHayTicket => anulada ? 'Anulada: no hay ticket' : null;
}
