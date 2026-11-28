import '../datos/barra_repositorio.dart';
import 'cuenta_barra.dart';
import 'nombre_de_barra.dart';
import 'recetas_de_la_barra.dart';
import 'stock_de_la_barra.dart';
import 'stock_por_barra.dart';

/// Qué hace VENDER cuando se toca un producto del que no queda.
enum FrenoDeStock {
  /// Queda, o no se controla: se suma sin preguntar.
  ninguno,

  /// El stock general de siempre (el jefe no lo repartió por barra): avisa y deja vender.
  pregunta,

  /// Repartido por barra y **con señal**: sin stock no se vende (decidido el 25-nov-2026).
  noSeVende,

  /// Repartido por barra y **sin señal**: esta caja no sabe si repusieron. Avisa en rojo
  /// y deja vender; lo vendido de más se descuenta de lo que se reponga (27-nov-2026).
  sinSenial,
}

/// El stock como lo mira VENDER, en la barra de **esta caja** (28-nov-2026).
///
/// Un producto que el jefe repartió en esta barra se cuenta con [StockPorBarra] (lo de
/// esta barra, de esta noche); el que no, con el stock general de siempre
/// ([StockDeLaBarra]). **Una sola cuenta para "Quedan", para el freno al tocar y para el
/// freno al cobrar**: la pantalla no hace otra al lado.
class StockParaVender {
  final Map<String, StockDeProducto> general;
  final StockPorBarra? porBarra;

  /// La barra de esta caja ("Barra 1"). Null: la caja no tiene barra y nada se controla
  /// por barra.
  final String? barra;
  final RecetasDeLaBarra recetas;

  const StockParaVender({
    this.general = const {},
    this.porBarra,
    this.barra,
    this.recetas = RecetasDeLaBarra.ninguna,
  });

  static const nada = StockParaVender();

  /// Si [productoId] se controla en la barra de esta caja.
  bool enLaBarra(String productoId) => porBarra?.controla(barra, productoId) ?? false;

  /// Si lo que frena a [productoId] es el stock de la barra: él mismo, o algo que lleva
  /// entero (el Speed del vodka).
  bool frenaLaBarra(String productoId) =>
      enLaBarra(productoId) || recetas.enteros(productoId).keys.any(enLaBarra);

  /// Lo que queda de [productoId] solo (sin mirar su receta ni la cuenta). En la barra
  /// puede dar negativo: se vendió sin stock. Null: no se controla.
  int? quedaSolo(String productoId) {
    if (enLaBarra(productoId)) return porBarra!.en(barra!, productoId)!.queda;
    final s = general[productoId];
    return s == null || !s.controla ? null : s.queda;
  }

  /// Lo que se lleva de [productoId] la [cuenta]: él mismo y lo que va entero adentro de
  /// los tragos (dos vodkas son dos Speed).
  int enLaCuenta(String productoId, CuentaBarra cuenta) => cuenta.renglones.fold(
        0,
        (s, r) => s + (recetas.loQueBaja(r.productoId, r.cantidad)[productoId] ?? 0),
      );

  /// Lo que queda para seguir sumando [productoId] a la [cuenta]. Un trago con algo
  /// entero alcanza para lo menor entre su propio stock y lo que dé eso. Null: no se
  /// controla.
  int? quedan(String productoId, CuentaBarra cuenta) {
    int? de(String id) {
      final q = quedaSolo(id);
      return q == null ? null : q - enLaCuenta(id, cuenta);
    }

    final propio = de(productoId);
    if (recetas.enteros(productoId).isEmpty) return propio;
    final alcanza = recetas.alcanzaPara(productoId, de);
    if (propio == null) return alcanza;
    if (alcanza == null) return propio;
    return propio < alcanza ? propio : alcanza;
  }

  /// Desde cuántas que quedan se avisa (el de la barra, si se controla ahí).
  int? avisoDe(String productoId) => enLaBarra(productoId)
      ? porBarra!.en(barra!, productoId)!.aviso
      : general[productoId]?.aviso;

  /// Qué pasa al tocar [productoId] con la [cuenta] como está.
  FrenoDeStock alSumar(String productoId, CuentaBarra cuenta, {required bool conSenial}) {
    final q = quedan(productoId, cuenta);
    if (q == null || q > 0) return FrenoDeStock.ninguno;
    if (!frenaLaBarra(productoId)) return FrenoDeStock.pregunta;
    return conSenial ? FrenoDeStock.noSeVende : FrenoDeStock.sinSenial;
  }

  /// Lo que no alcanza para cobrar la [cuenta], **con señal**: "producto → cuántas
  /// quedan" de lo repartido en esta barra que la cuenta se lleva de más (otra caja
  /// vendió las últimas mientras se armaba). Vacío: se cobra.
  Map<String, int> noAlcanzaPara(CuentaBarra cuenta) {
    final pide = <String, int>{};
    for (final r in cuenta.renglones) {
      for (final e in recetas.loQueBaja(r.productoId, r.cantidad).entries) {
        pide[e.key] = (pide[e.key] ?? 0) + e.value;
      }
    }
    return {
      for (final e in pide.entries)
        if (enLaBarra(e.key) && quedaSolo(e.key)! < e.value) e.key: quedaSolo(e.key)! < 0 ? 0 : quedaSolo(e.key)!,
    };
  }

  /// Los "voy en camino" que siguen en pie para esta barra.
  List<EnCamino> get enCamino => barra == null ? const [] : (porBarra?.enCamino(barra) ?? const []);

  /// Lo que llegó a esta barra (reposiciones del depósito y lo que le pasaron de otra),
  /// de lo más viejo a lo más nuevo. Para "Se repusieron…".
  static List<MovimientoDeStock> llegadasA(String? barra, Iterable<MovimientoDeStock> movimientos) {
    if (barra == null) return const [];
    final clave = claveDeBarra(barra);
    final lista = [
      for (final m in movimientos)
        if ((m.tipo == TipoMovimientoDeStock.reposicion || m.tipo == TipoMovimientoDeStock.traspaso) &&
            m.hacia != null &&
            claveDeBarra(m.hacia!) == clave)
          m,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return lista;
  }
}
