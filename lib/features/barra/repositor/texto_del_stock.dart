import '../cuentas/nombre_de_barra.dart';
import '../cuentas/stock_por_barra.dart';
import '../datos/barra_repositorio.dart';

/// Cómo se dice el stock en palabras: un solo lugar para STOCK del repositor, VENDER, LAS
/// CAJAS y el reparto del jefe. Todo puro; los números salen de [StockPorBarra].

/// "Depósito" o el nombre de la barra.
String nombreDelLugar(String lugar) => esElDeposito(lugar) ? 'Depósito' : lugar.trim();

/// "la Barra 1" / "el depósito", para armar una oración.
String elLugar(String lugar) => esElDeposito(lugar) ? 'el depósito' : 'la ${lugar.trim()}';

/// "Quedan 12", "Queda 1", "SIN STOCK", o "SIN STOCK · se vendieron 5 de más" cuando se
/// vendió con el stock en cero (sin señal no se frena): eso se descuenta de lo que se
/// reponga.
String cuantoQueda(StockDeUnLugar s) {
  if (s.queda < 0) {
    return 'SIN STOCK · se ${s.queda == -1 ? 'vendió 1' : 'vendieron ${-s.queda}'} de más';
  }
  if (s.queda == 0) return 'SIN STOCK';
  return s.queda == 1 ? 'Queda 1' : 'Quedan ${s.queda}';
}

/// El renglón chico de un producto en una barra: "Arrancó con 72 · entró 12 · vendió 61 ·
/// faltó 2", solo lo que no es cero. En el depósito: "El jefe cargó 240 · salió 132 ·
/// entró 24 · faltó 1".
String detalleDelStock(StockDeUnLugar s) {
  final partes = <String>[
    s.esDeposito ? 'El jefe cargó ${s.inicial}' : 'Arrancó con ${s.inicial}',
    if (s.esDeposito && s.salio != 0) 'a las barras ${s.salio}',
    if (s.entro != 0) 'entró ${s.entro}',
    if (!s.esDeposito && s.salio != 0) 'pasó a otra ${s.salio}',
    if (s.vendido != 0) 'vendió ${s.vendido}',
    if (s.falto != 0) 'faltó ${s.falto}',
    // Lo que corrigieron los conteos: la cuenta no daba y el repositor dejó dicho cuántas hay.
    if (s.porConteos != 0) 'contadas ${s.porConteos > 0 ? '+' : '−'}${s.porConteos.abs()}',
  ];
  return partes.join(' · ');
}

/// La cuenta de una reposición, en palabras: "La cuenta da 33 (tenía 21 + 12)", o, si se
/// había vendido de más sin stock, "Se vendieron 5 sin stock: 24 que traés − 5 ya vendidas
/// = quedan 19".
String cuentaDeLaReposicion({required int tenia, required int trae}) {
  final queda = tenia + trae;
  if (tenia < 0) {
    final deMas = -tenia;
    return 'Se ${deMas == 1 ? 'vendió 1' : 'vendieron $deMas'} sin stock: $trae que traés − $deMas ya '
        '${deMas == 1 ? 'vendida' : 'vendidas'} = ${queda == 1 ? 'queda 1' : 'quedan $queda'}.';
  }
  return 'La cuenta da $queda (tenía $tenia + $trae).';
}

/// Un movimiento, para el historial: qué se movió y por dónde.
/// "Speed · depósito → Barra 1", "Agua · Barra 2 → Barra 1", "Cerveza · Barra 1 · Congelada".
String queDelMovimiento(MovimientoDeStock m, String producto) {
  String lugar(String? l) => l == null ? '—' : (esElDeposito(l) ? 'depósito' : l);
  return switch (m.tipo) {
    TipoMovimientoDeStock.entrada => '$producto · entró al depósito',
    TipoMovimientoDeStock.reposicion => '$producto · depósito → ${lugar(m.hacia)}',
    TipoMovimientoDeStock.traspaso => '$producto · ${lugar(m.desde)} → ${lugar(m.hacia)}',
    TipoMovimientoDeStock.faltante => '$producto · ${lugar(m.desde)} · ${m.motivo ?? 'faltante'}',
    TipoMovimientoDeStock.conteo => '$producto · ${lugar(m.hacia)} · se contaron ${m.contadas ?? 0}',
    TipoMovimientoDeStock.enCamino => '$producto · voy en camino a ${lugar(m.hacia)}',
    TipoMovimientoDeStock.enCaminoNo => '$producto · ya no voy a ${lugar(m.hacia)}',
    null => producto,
  };
}

/// La cantidad con su signo, para el historial: "+12", "−2", o "" si no mueve nada.
String cuantoDelMovimiento(MovimientoDeStock m) => switch (m.tipo) {
      TipoMovimientoDeStock.entrada || TipoMovimientoDeStock.reposicion => '+${m.cantidad}',
      TipoMovimientoDeStock.traspaso => '${m.cantidad}',
      TipoMovimientoDeStock.faltante => '−${m.cantidad}',
      _ => '',
    };

/// Lo de más que dice un movimiento: la nota, y si al contar no daba la cuenta.
String? notaDelMovimiento(MovimientoDeStock m) {
  final partes = <String>[
    if (m.tipo != TipoMovimientoDeStock.conteo && m.contadas != null) 'quedaron ${m.contadas}',
    if (m.ajuste != 0)
      '${m.ajuste < 0 ? 'faltaban ${-m.ajuste}' : 'sobraban ${m.ajuste}'}'
          '${m.tipo != TipoMovimientoDeStock.faltante && m.motivo != null ? ' (${m.motivo})' : ''}',
    if (m.nota != null) '"${m.nota}"',
  ];
  return partes.isEmpty ? null : partes.join(' · ');
}

/// "Se vendió sin stock: 5 speed en la Barra 1 · 2 agua en la Barra 2. Se descuenta de lo
/// que se reponga.": lo vendido con el stock en cero (sin señal no se frena), para la
/// encargada y el jefe. Null si no se vendió nada de más.
String? vendidoSinStock(Iterable<StockDeUnLugar> deMas, String Function(String productoId) nombreDe) {
  final partes = [
    for (final s in deMas)
      if (s.queda < 0) '${-s.queda} ${nombreDe(s.productoId).toLowerCase()} en ${elLugar(s.lugar)}',
  ];
  if (partes.isEmpty) return null;
  return 'Se vendió sin stock: ${partes.join(' · ')}. Se descuenta de lo que se reponga.';
}

/// "Se repusieron 12 Speed en tu barra · quedan 12 · Nico": lo que ven la cajera de esa
/// barra y la encargada cuando llega una reposición o un traspaso.
String seRepusieron(MovimientoDeStock m, String producto, {int? quedan, bool enTuBarra = true}) {
  final donde = enTuBarra ? 'en tu barra' : 'en ${elLugar(m.hacia ?? '')}';
  return [
    'Se ${m.cantidad == 1 ? 'repuso 1' : 'repusieron ${m.cantidad}'} $producto $donde',
    if (quedan != null) quedan == 1 ? 'queda 1' : 'quedan $quedan',
    if (m.hechoPor != null) m.hechoPor!,
  ].join(' · ');
}
