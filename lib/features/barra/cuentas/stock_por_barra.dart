import 'dart:math' as math;

import '../datos/barra_repositorio.dart';
import '../datos/movimiento_de_stock.dart';
import '../datos/stock_en_la_barra.dart';
import '../services/barras_del_salon.dart' show barraDe;
import 'cierre_de_barra.dart' show ventasAnuladasConElVale;
import 'dia_de_operacion.dart';
import 'nombre_de_barra.dart';

/// Cuánto hay de un producto en un lugar: el depósito ([kDeposito]) o una barra.
class StockDeUnLugar {
  final String productoId;

  /// [kDeposito] o el nombre de la barra (como lo escribió el jefe en el reparto).
  final String lugar;

  /// En el depósito, el stock general; en una barra, con cuánto arrancó.
  final int inicial;

  /// En el depósito, las entradas de mercadería; en una barra, lo repuesto y lo que le
  /// pasaron de otra barra.
  final int entro;

  /// En el depósito, lo repartido y lo repuesto; en una barra, lo que pasó a otra.
  final int salio;

  /// Lo vendido en las cajas de esa barra, sin las anuladas. En el depósito, 0.
  final int vendido;

  /// Los faltantes anotados (rotas, congeladas…).
  final int falto;

  /// Lo que hay. Sin conteos, la cuenta; con conteos, lo contado más lo que pasó
  /// después. **Puede dar negativo** si se vendió más de lo anotado (dos cajas sin la
  /// central a la vez): se muestra como "sin stock".
  final int queda;

  /// Desde cuántas que quedan se avisa. Null: no avisa.
  final int? aviso;

  const StockDeUnLugar({
    required this.productoId,
    required this.lugar,
    required this.inicial,
    this.entro = 0,
    this.salio = 0,
    this.vendido = 0,
    this.falto = 0,
    required this.queda,
    this.aviso,
  });

  bool get esDeposito => lugar == kDeposito;

  /// La cuenta sin los conteos.
  int get cuenta => inicial + entro - salio - vendido - falto;

  /// Lo que corrigieron los conteos del repositor (negativo: faltaban).
  int get porConteos => queda - cuenta;

  bool get sinStock => queda <= 0;

  /// Sin stock, o llegó al aviso que puso el jefe.
  bool get enAviso => sinStock || (aviso != null && queda <= aviso!);
}

/// Un "voy en camino" que sigue en pie: el repositor avisó a [barra] y todavía no repuso.
class EnCamino {
  /// El movimiento del aviso (para "ya no voy" y para que la reposición lo conteste).
  final MovimientoDeStock aviso;

  /// El nombre de la barra.
  final String barra;

  const EnCamino({required this.aviso, required this.barra});

  String get productoId => aviso.productoId;

  /// Quién avisó.
  String? get quien => aviso.hechoPor;
}

/// El stock de una fiesta repartido por barra (decidido por el usuario el 25-nov-2026;
/// `docs/SPEC_repositor_y_stock_por_barra_2026-11-25.md`).
///
/// **La única cuenta del stock por barra**: las pantallas (VENDER, STOCK del repositor,
/// LAS CAJAS, la página del iPhone) y los límites (no reponer más de lo que hay en el
/// depósito, no pasar más de lo que tiene una barra) salen de acá.
///
/// - Depósito = stock general − lo repartido − lo repuesto + entradas − faltantes.
/// - Barra = arranque + lo que entró − lo que salió − lo vendido en sus cajas − faltantes.
/// - **Con un conteo** ("quedan 40"), lo de ese lugar sale de lo contado más lo que pasó
///   **después de contar**: lo que el equipo del repositor no conocía al contar (estaba
///   en el otro router, o llegó tarde) se suma o resta una sola vez ([FotoDeStock]). Si
///   dos conteos se hicieron sin conocerse, vale el que da menos: mejor frenar que vender
///   lo que no hay.
///
/// **Ninguna cuenta mira la hora** ni el orden en que llegaron las filas. Las barras se
/// comparan con [claveDeBarra].
///
/// Un producto se controla **en una barra** solo si el jefe le cargó el stock general y
/// le puso con cuánto arranca ahí (una fila de `barra_stock_barras` activa, aunque sea
/// 0). Sin eso no frena: un producto que el jefe no repartió no queda trabado.
class StockPorBarra {
  final String eventoId;
  final Map<String, StockDeUnLugar> _deposito; // producto →
  final Map<String, Map<String, StockDeUnLugar>> _barras; // clave de barra → producto →
  final Map<String, String> _nombres; // clave de barra → nombre
  final Map<String, Map<String, StockEnLaBarra>> _reparto; // clave → producto →
  final List<EnCamino> _enCamino;
  final _Datos _datos;

  /// Productos con reparto pero sin stock general: no se controlan hasta que el jefe lo
  /// cargue.
  final Set<String> faltaElStockGeneral;

  /// Unidades vendidas de productos repartidos en cajas sin barra (o de una barra sin
  /// reparto): no descuentan de ninguna. Para avisarle al jefe.
  final int vendidoSinBarra;

  /// Ventas cuya caja todavía no llegó a este equipo: no se sabe de qué barra son.
  final int ventasSinCaja;

  StockPorBarra._({
    required this.eventoId,
    required Map<String, StockDeUnLugar> deposito,
    required Map<String, Map<String, StockDeUnLugar>> barras,
    required Map<String, String> nombres,
    required Map<String, Map<String, StockEnLaBarra>> reparto,
    required List<EnCamino> enCamino,
    required _Datos datos,
    required this.faltaElStockGeneral,
    required this.vendidoSinBarra,
    required this.ventasSinCaja,
  })  : _deposito = deposito,
        _barras = barras,
        _nombres = nombres,
        _reparto = reparto,
        _enCamino = enCamino,
        _datos = datos;

  /// Si la fiesta tiene reparto. Sin reparto, el stock sigue como antes
  /// (`StockDeLaBarra`: de la fiesta entera, avisa y no frena).
  bool get hayReparto => _barras.isNotEmpty;

  /// Las barras con reparto, con el nombre que les puso el jefe.
  List<String> get nombresDeBarras => [for (final c in _barras.keys) _nombres[c]!]..sort();

  /// [ventas]: las de las cajas de esa noche (el día de operación); [cajas] dice la barra
  /// de cada caja (`sede`). Lo que no es de [eventoId] se ignora.
  factory StockPorBarra.de({
    required String eventoId,
    required Iterable<PrecioBarra> precios,
    required Iterable<StockEnLaBarra> repartos,
    required Iterable<MovimientoDeStock> movimientos,
    required Iterable<VentaBarra> ventas,
    required Iterable<CajaBarra> cajas,
    required Iterable<AnulacionBarra> anulaciones,
  }) {
    final general = <String, int?>{
      for (final p in precios)
        if (p.eventoId == eventoId) p.productoId: p.stockInicial,
    };

    // El reparto del jefe: clave de barra → producto → fila, solo con stock general.
    final reparto = <String, Map<String, StockEnLaBarra>>{};
    final nombres = <String, String>{};
    final falta = <String>{};
    for (final r in repartos) {
      if (r.eventoId != eventoId || !r.activo || r.barra.trim().isEmpty) continue;
      if (general[r.productoId] == null) {
        falta.add(r.productoId);
        continue;
      }
      final c = claveDeBarra(r.barra);
      nombres.putIfAbsent(c, () => r.barra.trim());
      reparto.putIfAbsent(c, () => {})[r.productoId] = r;
    }
    final repartidos = {for (final m in reparto.values) ...m.keys};

    final cajasDeLaFiesta = [for (final c in cajas) if (c.eventoId == eventoId) c];
    // La barra de cada caja sale de la lista fija del salón (`barraDe`, 26-nov-2026: la
    // caja la elige de "Barra 1 · Barra 2"); una caja vieja con otro texto no es de
    // ninguna barra y su venta va a `vendidoSinBarra`.
    final barraDeCaja = <String, String>{
      for (final c in cajasDeLaFiesta)
        if (barraDe(c.sede) case final b?) c.id: claveDeBarra(b),
    };
    final idsDeCajas = {for (final c in cajasDeLaFiesta) c.id};
    final lasVentas = [for (final v in ventas) if (v.eventoId == eventoId) v];
    final lasAnulaciones = [for (final a in anulaciones) if (a.eventoId == eventoId) a];
    // Solo las anuladas con el vale de vuelta devuelven el stock ("¿Volvió el vale?").
    final anuladas = ventasAnuladasConElVale(lasAnulaciones);
    final losMovimientos = [
      for (final m in movimientos)
        if (m.eventoId == eventoId && m.tipo != null) m,
    ];

    final datos = _Datos(
      general: general,
      reparto: reparto,
      barraDeCaja: barraDeCaja,
      ventas: lasVentas,
      anulaciones: lasAnulaciones,
      movimientos: losMovimientos,
    );

    var sinBarra = 0, sinCaja = 0;
    for (final v in lasVentas) {
      if (anuladas.contains(v.id)) continue;
      if (!idsDeCajas.contains(v.cajaBarraId)) sinCaja++;
      final b = barraDeCaja[v.cajaBarraId];
      for (final r in v.renglones) {
        if (repartidos.contains(r.productoId) && reparto[b]?.containsKey(r.productoId) != true) {
          sinBarra += r.cantidad;
        }
      }
    }

    final deposito = <String, StockDeUnLugar>{
      for (final p in repartidos) p: datos.stock(kDeposito, p, aviso: null, nombre: kDeposito),
    };
    final barras = <String, Map<String, StockDeUnLugar>>{
      for (final e in reparto.entries)
        e.key: {
          for (final r in e.value.values)
            r.productoId: datos.stock(e.key, r.productoId, aviso: r.aviso, nombre: nombres[e.key]!),
        },
    };

    return StockPorBarra._(
      eventoId: eventoId,
      deposito: deposito,
      barras: barras,
      nombres: nombres,
      reparto: reparto,
      enCamino: _avisosEnPie(losMovimientos, reparto, nombres),
      datos: datos,
      faltaElStockGeneral: falta,
      vendidoSinBarra: sinBarra,
      ventasSinCaja: sinCaja,
    );
  }

  /// **El stock de una noche** (26-nov-2026, junto con la barra por noche): las cajas y
  /// las ventas de esa noche ([CajasPorDia.delDia] y [CajasPorDia.ventasDelDia]); una caja
  /// de prueba de otro día no descuenta. Los movimientos del repositor y el reparto del
  /// jefe son de la fiesta entera. **Las pantallas usan esta, no [de].**
  factory StockPorBarra.deLaNoche({
    required String eventoId,
    required Iterable<PrecioBarra> precios,
    required Iterable<StockEnLaBarra> repartos,
    required Iterable<MovimientoDeStock> movimientos,
    required Iterable<VentaBarra> ventas,
    required Iterable<AnulacionBarra> anulaciones,
    required CajasPorDia cajas,
    required DiaDeOperacion dia,
  }) =>
      StockPorBarra.de(
        eventoId: eventoId,
        precios: precios,
        repartos: repartos,
        movimientos: movimientos,
        ventas: cajas.ventasDelDia(ventas, dia),
        cajas: cajas.delDia(dia),
        anulaciones: anulaciones,
      );

  static String? _clave(String lugar) {
    final t = lugar.trim();
    if (t.isEmpty) return null;
    return esElDeposito(t) ? kDeposito : claveDeBarra(t);
  }

  /// El stock de [productoId] en [lugar] (el depósito o una barra, escritos como sea).
  /// Null si ahí no se controla.
  StockDeUnLugar? en(String lugar, String productoId) {
    final c = _clave(lugar);
    if (c == null) return null;
    return c == kDeposito ? _deposito[productoId] : _barras[c]?[productoId];
  }

  /// Si se controla [productoId] en [barra].
  bool controla(String? barra, String productoId) {
    if (barra == null) return false;
    final c = _clave(barra);
    return c != null && c != kDeposito && _barras[c]?.containsKey(productoId) == true;
  }

  /// Si en [barra] se pueden vender [cantidad] de [productoId]. **Sin stock no se vende**
  /// (decidido el 25-nov-2026); un producto que no se controla en esa barra, sí.
  bool sePuedeVender(String? barra, String productoId, int cantidad) {
    if (!controla(barra, productoId)) return true;
    return en(barra!, productoId)!.queda >= cantidad;
  }

  /// Cuántas se pueden vender en [barra]: null si no se controla (sin límite).
  int? cuantasSePuedenVender(String? barra, String productoId) =>
      controla(barra, productoId) ? math.max(0, en(barra!, productoId)!.queda) : null;

  /// Hasta cuánto se puede reponer de [productoId] desde el depósito: lo que queda ahí.
  int cuantoSePuedeReponer(String productoId) => math.max(0, _deposito[productoId]?.queda ?? 0);

  /// Hasta cuánto se puede pasar de [productoId] desde [barra]: lo que le queda.
  int cuantoSePuedePasar(String barra, String productoId) =>
      math.max(0, en(barra, productoId)?.queda ?? 0);

  /// Hasta cuánto se puede descontar como faltante en [lugar]: lo que queda ahí.
  int cuantoPuedeFaltar(String lugar, String productoId) =>
      math.max(0, en(lugar, productoId)?.queda ?? 0);

  /// Lo que ve el repositor al contar en [lugar]: lo contado menos lo que hay, sumando
  /// [ademas] (lo que está reponiendo en ese momento). Va en el historial; el stock sale
  /// de lo contado y la foto.
  int ajustePara(String lugar, String productoId, int contadas, {int ademas = 0}) =>
      contadas - ((en(lugar, productoId)?.queda ?? 0) + ademas);

  /// Hasta dónde sabe este equipo, para guardar con un conteo de [productoId] en [lugar].
  /// (Es lo mismo para cualquier lugar y producto: de toda la fiesta.)
  FotoDeStock fotoDe(String lugar, String productoId) => _datos.foto();

  /// Por qué no se puede reponer, o null si se puede.
  String? errorAlReponer(String productoId, String barra, int cantidad) {
    if (cantidad <= 0) return 'Poné cuánto reponés.';
    if (!controla(barra, productoId)) {
      return 'En la ${barra.trim()} no se lleva el stock de este producto: el jefe no lo repartió.';
    }
    final hay = cuantoSePuedeReponer(productoId);
    if (cantidad > hay) return 'En el depósito quedan $hay: no se puede reponer más.';
    return null;
  }

  /// Por qué no se puede pasar de [desde] a [hacia], o null si se puede.
  String? errorAlPasar(String productoId, String desde, String hacia, int cantidad, String? porque) {
    if (cantidad <= 0) return 'Poné cuánto pasás.';
    if (_clave(desde) == _clave(hacia)) return 'Elegí otra barra.';
    if (!controla(desde, productoId) || !controla(hacia, productoId)) {
      return 'El jefe no repartió este producto en las dos barras.';
    }
    final hay = cuantoSePuedePasar(desde, productoId);
    if (cantidad > hay) return 'La ${desde.trim()} tiene $hay: no se puede pasar más.';
    if (porque == null || porque.trim().isEmpty) return 'Para pasar de una barra a otra, decí por qué.';
    return null;
  }

  /// Por qué no se puede anotar el faltante, o null si se puede.
  String? errorAlDescontar(String productoId, String lugar, int cantidad, String? motivo) {
    if (cantidad <= 0) return 'Poné cuántas faltan.';
    if (en(lugar, productoId) == null) return 'Ahí no se lleva el stock de este producto.';
    final hay = cuantoPuedeFaltar(lugar, productoId);
    if (cantidad > hay) return 'Hay $hay: no pueden faltar más.';
    if (motivo == null || motivo.trim().isEmpty) return 'Elegí el motivo.';
    return null;
  }

  /// Por qué no se puede guardar lo contado, o null si se puede: si no da la cuenta,
  /// hace falta el motivo.
  static String? errorDelAjuste(int ajuste, String? motivo) {
    if (ajuste != 0 && (motivo == null || motivo.trim().isEmpty)) {
      return ajuste < 0
          ? 'Faltan ${-ajuste}: elegí qué pasó con ${-ajuste == 1 ? 'esa' : 'esas'}.'
          : 'Sobran $ajuste: decí de dónde salieron.';
    }
    return null;
  }

  /// Por qué no se puede anotar la entrada al depósito, o null si se puede.
  static String? errorAlEntrar(int cantidad, String? deDonde) {
    if (cantidad <= 0) return 'Poné cuánto entró.';
    if (deDonde == null || deDonde.trim().isEmpty) return 'Decí de dónde vino.';
    return null;
  }

  /// Por qué no se puede guardar el stock general y el reparto de [productoId], o null si
  /// se puede. [arranques]: barra → con cuánto arranca (las que no vienen quedan como
  /// están).
  ///
  /// - **No se reparte más de lo que hay** (contando lo que ya entró y salió del depósito).
  /// - Una barra que ya vendió o movió no puede arrancar con menos de lo que le falta: si
  ///   no, el depósito ganaría botellas que no existen.
  /// - **Un producto ya contado no cambia** el stock general ni el reparto: lo que se
  ///   mueve desde ahí lo anota el repositor (entrada, reposición, faltante). Si no, el
  ///   conteo y el cambio del jefe se sumarían dos veces.
  String? errorDelReparto(String productoId, int? stockGeneral, Map<String, int> arranques) {
    if (stockGeneral == null) return 'Primero cargá el stock general.';
    if (stockGeneral < 0 || arranques.values.any((a) => a < 0)) return 'No puede ser negativo.';
    final nuevos = <String, int>{
      for (final e in _reparto.entries)
        if (e.value.containsKey(productoId)) e.key: e.value[productoId]!.arranque,
    };
    final viejos = Map<String, int>.of(nuevos);
    for (final e in arranques.entries) {
      final c = _clave(e.key);
      if (c == null || c == kDeposito) return 'Elegí una barra.';
      nuevos[c] = e.value;
    }
    final cambia = stockGeneral != (_datos.general[productoId] ?? 0) ||
        nuevos.entries.any((e) => viejos[e.key] != e.value);
    if (cambia && _datos.tieneConteos(productoId)) {
      return 'Este producto ya se contó: lo que cambie, que lo anote el repositor '
          '(entró mercadería, reponer o faltante).';
    }
    for (final e in nuevos.entries) {
      final antes = viejos[e.key];
      final s = _barras[e.key]?[productoId];
      // Solo se mira lo que baja: dejarla como está, o subirla, siempre se puede.
      if (antes == null || s == null || e.value >= antes) continue;
      final minimo = antes - s.queda;
      if (e.value < minimo) {
        return 'La ${_nombres[e.key]} ya usó ${antes - s.queda} de su arranque: '
            'no puede arrancar con menos de $minimo.';
      }
    }
    final d = _deposito[productoId];
    final generalAntes = _datos.general[productoId] ?? 0;
    // Lo que habría en el depósito sin ningún reparto, con el stock general nuevo. Sin
    // reparto todavía, con las entradas y faltantes del depósito que ya se anotaron.
    final sinReparto = (d?.queda ?? _datos.cuentaDelDeposito(productoId)) +
        viejos.values.fold<int>(0, (s, a) => s + a) +
        (stockGeneral - generalAntes);
    final total = nuevos.values.fold<int>(0, (s, a) => s + a);
    if (total > sinReparto) return 'Hay $sinReparto: no se puede repartir $total.';
    return null;
  }

  /// Por qué no se puede sacar [productoId] del reparto de [barra], o null si se puede:
  /// una barra que ya vendió, movió, contó o recibió un aviso de ese producto lo sigue
  /// llevando. Con ventas de cajas que todavía no llegaron a este equipo, tampoco: podrían
  /// ser de esa barra.
  String? errorAlSacarDelReparto(String productoId, String barra) {
    final c = _clave(barra);
    if (c == null) return null;
    if (_datos.tuvoMovimiento(c, productoId)) {
      return 'La ${barra.trim()} ya vendió o movió este producto: no se puede sacar del reparto.';
    }
    if (ventasSinCaja > 0) {
      return 'Hay ventas de cajas que todavía no llegaron a este equipo: probá de nuevo en un rato.';
    }
    return null;
  }

  /// Los "voy en camino" que siguen en pie en [barra] (todas si es null).
  List<EnCamino> enCamino([String? barra]) {
    final c = barra == null ? null : _clave(barra);
    return _enCamino.where((e) => c == null || claveDeBarra(e.barra) == c).toList();
  }

  /// Si alguien avisó "voy en camino" a [barra] con [productoId] y todavía no repuso.
  EnCamino? enCaminoDe(String barra, String productoId) {
    for (final e in enCamino(barra)) {
      if (e.productoId == productoId) return e;
    }
    return null;
  }

  /// Cuántas reposiciones y traspasos hacia [barra] con [productoId] hizo el equipo
  /// [equipo]: lo que va en `avisos_previos` de un "voy en camino". Un equipo conoce
  /// todas sus filas, así que la cuenta es exacta.
  static int llegadasDesde(
    Iterable<MovimientoDeStock> movimientos,
    String eventoId,
    String barra,
    String productoId,
    String? equipo,
  ) =>
      movimientos.where((m) => _esLlegada(m, eventoId, claveDeBarra(barra), productoId, equipo)).length;

  static bool _esLlegada(MovimientoDeStock m, String eventoId, String claveBarra, String productoId, String? equipo) =>
      m.eventoId == eventoId &&
      m.productoId == productoId &&
      m.deviceId == equipo &&
      m.hacia != null &&
      claveDeBarra(m.hacia!) == claveBarra &&
      (m.tipo == TipoMovimientoDeStock.reposicion || m.tipo == TipoMovimientoDeStock.traspaso);

  /// Un aviso sigue mientras nadie lo sacó ni lo contestó, y su equipo no repuso ahí;
  /// y solo si la barra sigue llevando ese producto. Si hay varios para la misma barra y
  /// el mismo producto, se muestra el más nuevo (por su hora, y si empatan, por su id:
  /// siempre el mismo en todos los equipos).
  ///
  /// **`avisos_previos` lo cuenta el repositorio con el equipo que va a guardar**: si se
  /// contara con otro, el aviso nacería ya cumplido.
  static List<EnCamino> _avisosEnPie(
    List<MovimientoDeStock> movimientos,
    Map<String, Map<String, StockEnLaBarra>> reparto,
    Map<String, String> nombres,
  ) {
    final contestados = {
      for (final m in movimientos)
        if (m.respondeA != null) m.respondeA!,
    };
    final enPie = <String, EnCamino>{};
    final avisos = [
      for (final m in movimientos)
        if (m.tipo == TipoMovimientoDeStock.enCamino && m.hacia != null) m,
    ]..sort((a, b) {
        final t = compararMomentos(b.createdAt, a.createdAt);
        return t != 0 ? t : b.id.compareTo(a.id);
      });
    for (final a in avisos) {
      final c = claveDeBarra(a.hacia!);
      if (reparto[c]?.containsKey(a.productoId) != true) continue;
      if (contestados.contains(a.id)) continue;
      final hechas = movimientos.where((m) => _esLlegada(m, a.eventoId, c, a.productoId, a.deviceId)).length;
      if (hechas > (a.avisosPrevios ?? 0)) continue;
      enPie.putIfAbsent('$c|${a.productoId}', () => EnCamino(aviso: a, barra: nombres[c]!));
    }
    return enPie.values.toList();
  }

  /// Para el repositor: lo de las barras que llegó al aviso, **lo que no tiene stock
  /// arriba** y después lo que tiene menos.
  List<StockDeUnLugar> enAviso() {
    final todos = [
      for (final m in _barras.values)
        for (final s in m.values)
          if (s.enAviso) s,
    ];
    todos.sort((a, b) {
      if (a.sinStock != b.sinStock) return a.sinStock ? -1 : 1;
      final q = a.queda.compareTo(b.queda);
      if (q != 0) return q;
      return a.lugar.compareTo(b.lugar);
    });
    return todos;
  }
}

/// Lo que sabe este equipo de la fiesta, y la cuenta de un lugar con todo lo que sabe o
/// solo con lo que pasó antes de un conteo.
class _Datos {
  final Map<String, int?> general;
  final Map<String, Map<String, StockEnLaBarra>> reparto;
  final Map<String, String> barraDeCaja;
  final List<VentaBarra> ventas;
  final List<AnulacionBarra> anulaciones;
  final List<MovimientoDeStock> movimientos;
  final Set<String> anuladas;
  final Map<String, AnulacionBarra> _anulacionDe;

  _Datos({
    required this.general,
    required this.reparto,
    required this.barraDeCaja,
    required this.ventas,
    required this.anulaciones,
    required this.movimientos,
  })  : anuladas = ventasAnuladasConElVale(anulaciones),
        // La anulada sin el vale sigue vendida para el stock: un conteo no la descuenta.
        _anulacionDe = {for (final a in anulaciones) if (a.valeVolvio) a.ventaId: a};

  static String? _lugar(String? l) => l == null ? null : (esElDeposito(l) ? kDeposito : claveDeBarra(l));

  static int _cmp(String a, String b) => compararMomentos(a, b);

  /// Si [m] toca [lugar] con [p].
  bool _toca(MovimientoDeStock m, String lugar, String p) =>
      m.productoId == p && (_lugar(m.desde) == lugar || _lugar(m.hacia) == lugar);

  bool _esDeLaBarra(VentaBarra v, String barra) => barraDeCaja[v.cajaBarraId] == barra;

  int _unidades(VentaBarra v, String p) =>
      v.renglones.fold<int>(0, (s, r) => r.productoId == p ? s + r.cantidad : s);

  /// Si [p] tiene algún conteo, en cualquier lugar.
  bool tieneConteos(String p) => movimientos.any((m) => m.productoId == p && m.esConteo);

  /// Si en [barra] hay algo de [p] que el reparto no puede deshacer: ventas,
  /// reposiciones, traspasos, faltantes, conteos o avisos.
  bool tuvoMovimiento(String barra, String p) =>
      movimientos.any((m) => _toca(m, barra, p)) ||
      ventas.any((v) => _esDeLaBarra(v, barra) && _unidades(v, p) > 0);

  /// La cuenta de [lugar] con lo que dicen [incluye] y [vendida], y el reparto de hoy.
  int _cuenta(
    String lugar,
    String p, {
    required bool Function(MovimientoDeStock) incluye,
    required bool Function(VentaBarra) vendida,
    void Function(int inicial, int entro, int salio, int vendido, int falto)? partes,
  }) {
    var entro = 0, salio = 0, falto = 0, vendido = 0;
    for (final m in movimientos) {
      if (m.productoId != p || !incluye(m)) continue;
      final desde = _lugar(m.desde), hacia = _lugar(m.hacia);
      switch (m.tipo) {
        case TipoMovimientoDeStock.entrada:
          if (hacia == lugar) entro += m.cantidad;
        case TipoMovimientoDeStock.reposicion:
        case TipoMovimientoDeStock.traspaso:
          if (hacia == lugar) entro += m.cantidad;
          if (desde == lugar) salio += m.cantidad;
        case TipoMovimientoDeStock.faltante:
          if (desde == lugar) falto += m.cantidad;
        default:
          break;
      }
    }
    final arranques = _arranquesDe(p);
    int inicial;
    if (lugar == kDeposito) {
      inicial = general[p] ?? 0;
      salio += arranques.values.fold<int>(0, (s, a) => s + a);
    } else {
      inicial = arranques[lugar] ?? 0;
      for (final v in ventas) {
        if (_esDeLaBarra(v, lugar) && vendida(v)) vendido += _unidades(v, p);
      }
    }
    partes?.call(inicial, entro, salio, vendido, falto);
    return inicial + entro - salio - vendido - falto;
  }

  Map<String, int> _arranquesDe(String p) => {
        for (final e in reparto.entries)
          if (e.value.containsKey(p)) e.key: e.value[p]!.arranque,
      };

  /// La cuenta del depósito de [p] con todo lo que se sabe, sin conteos.
  int cuentaDelDeposito(String p) =>
      _cuenta(kDeposito, p, incluye: (_) => true, vendida: (v) => !anuladas.contains(v.id));

  /// Si el conteo [b] sabía de verdad que [a] fue antes: conocía lo de su equipo hasta
  /// ahí o después.
  bool _sabidoAntes(MovimientoDeStock a, MovimientoDeStock b) =>
      b.foto?.conoce(a.deviceId, a.createdAt) ?? false;

  /// El stock de [lugar] (clave) con lo que sabe este equipo.
  StockDeUnLugar stock(String lugar, String p, {required int? aviso, required String nombre}) {
    late int inicial, entro, salio, vendido, falto;
    final total = _cuenta(lugar, p,
        incluye: (_) => true,
        vendida: (v) => !anuladas.contains(v.id),
        partes: (i, e, s, v, f) {
          inicial = i;
          entro = e;
          salio = s;
          vendido = v;
          falto = f;
        });

    // Los conteos de ese lugar. Un conteo deja sin efecto a otro solo si **sabía** que
    // el otro fue antes; los que no se conocen valen los dos, y se toma el que da menos
    // (mejor frenar que vender lo que no hay). La hora nunca decide entre conteos.
    final conteos = [
      for (final m in movimientos)
        if (m.productoId == p && _lugar(m.hacia) == lugar && m.esConteo) m,
    ];
    var vigentes = [
      for (final a in conteos)
        if (!conteos.any((b) => b.id != a.id && _sabidoAntes(a, b) && !_sabidoAntes(b, a))) a,
    ];
    if (vigentes.isEmpty) vigentes = conteos; // relojes rotos: que no se pierda ninguno

    int? queda;
    for (final r in vigentes) {
      final f = r.foto!;
      // Antes de contar: lo que conocía (por el número de cada caja y el orden de cada
      // equipo), el mismo conteo, y solo si no hay otra forma de saberlo, la hora.
      bool antes(String? equipo, String momento) =>
          f.conoce(equipo, momento) || _cmp(momento, r.createdAt) < 0;
      bool ventaAntes(VentaBarra v) =>
          (f.ventasHasta[v.cajaBarraId] ?? 0) >= v.numero || antes(v.deviceId, v.createdAt);
      bool anuladaAntes(VentaBarra v) {
        final a = _anulacionDe[v.id];
        return a != null && antes(a.deviceId, a.createdAt);
      }

      final cuentaAntes = _cuenta(lugar, p,
          incluye: (m) => m.id == r.id || antes(m.deviceId, m.createdAt),
          vendida: (v) => ventaAntes(v) && !anuladaAntes(v));
      final desde = r.contadas! + (total - cuentaAntes);
      queda = queda == null ? desde : math.min(queda, desde);
    }
    return StockDeUnLugar(
      productoId: p,
      lugar: nombre,
      inicial: inicial,
      entro: entro,
      salio: salio,
      vendido: vendido,
      falto: falto,
      queda: queda ?? total,
      aviso: aviso,
    );
  }

  /// Hasta dónde sabe este equipo, para guardar con un conteo: de toda la fiesta, la
  /// venta más alta de cada caja y la fila más nueva de cada equipo.
  FotoDeStock foto() {
    final hasta = <String, int>{};
    final equipos = <String, String>{};
    void anotar(String? equipo, String momento) {
      final e = equipo ?? '';
      final antes = equipos[e];
      if (antes == null || _cmp(momento, antes) > 0) equipos[e] = momento;
    }

    for (final v in ventas) {
      hasta[v.cajaBarraId] = math.max(hasta[v.cajaBarraId] ?? 0, v.numero);
      anotar(v.deviceId, v.createdAt);
    }
    for (final a in anulaciones) {
      anotar(a.deviceId, a.createdAt);
    }
    for (final m in movimientos) {
      anotar(m.deviceId, m.createdAt);
    }
    return FotoDeStock(ventasHasta: hasta, equiposHasta: equipos);
  }
}
