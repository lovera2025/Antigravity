import 'dart:convert';

import '../../../core/utils/uuid_utils.dart';
import '../cuentas/nombre_de_barra.dart';
import 'lectura_de_filas.dart';

/// El lugar del depósito en [MovimientoDeStock.desde] y [MovimientoDeStock.hacia]. Una
/// barra va con su nombre ("Barra 1").
const kDeposito = 'deposito';

/// Los motivos de lo que falta (una rota, una congelada…): los del faltante y los de una
/// cuenta que da de menos. Decididos por el usuario el 25-nov-2026.
const kMotivosQueFaltan = ['Rota', 'Congelada', 'Vencida', 'Se perdió', 'Otro'];

/// Los motivos de una cuenta que da de más.
const kMotivosQueSobran = ['Estaban sin anotar', 'Otro'];

/// Compara dos momentos guardados (`created_at`, en UTC).
int compararMomentos(String a, String b) {
  final x = DateTime.tryParse(a), y = DateTime.tryParse(b);
  if (x != null && y != null) return x.compareTo(y);
  return a.compareTo(b);
}

/// [lugar] como se guarda: [kDeposito] si es el depósito, si no el nombre de la barra sin
/// espacios de más. Vacío es un error del programa.
String lugarDeStock(String lugar) {
  final l = lugar.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (l.isEmpty) throw ArgumentError.value(lugar, 'lugar', 'hace falta el lugar');
  return esElDeposito(l) ? kDeposito : l;
}

/// Qué es cada fila de `barra_stock_movimientos`.
enum TipoMovimientoDeStock {
  /// Entró mercadería al depósito: la nota dice de dónde vino.
  entrada('entrada'),

  /// Del depósito a una barra.
  reposicion('reposicion'),

  /// De una barra a otra: la nota dice por qué.
  traspaso('traspaso'),

  /// Lo que falta y no es una venta (rota, congelada…), con su motivo.
  faltante('faltante'),

  /// "Anotar lo que hay": cuántas hay contadas en un lugar.
  conteo('conteo'),

  /// "Voy en camino" a una barra: no toca el stock.
  enCamino('en_camino'),

  /// "Ya no voy" (no hay, o lo repuso otro): saca un "voy en camino" ([MovimientoDeStock.respondeA]).
  enCaminoNo('en_camino_no');

  final String clave;
  const TipoMovimientoDeStock(this.clave);

  /// Null si la clave no se conoce (la escribió una versión más nueva): esa fila se
  /// ignora, no rompe nada.
  static TipoMovimientoDeStock? deClave(String? clave) {
    for (final t in values) {
      if (t.clave == clave) return t;
    }
    return null;
  }
}

/// **Hasta dónde conocía el equipo** cuando el repositor contó (revisión del 25-nov-2026).
///
/// Un conteo dice "acá hay 40". Para saber cuánto hay después, hay que sumarle solo lo
/// que pasó **después de contar**. El celular del repositor puede no tener todo (lo de
/// la otra caja estaba en el otro router, o llegó tarde): que no lo conociera no quiere
/// decir que haya pasado después. Lo que sí es seguro es **el orden dentro de cada
/// caja y de cada equipo**:
///
/// - las ventas de una caja se numeran en orden en su tablet: si conocía la venta 15 de
///   la Caja 2, la 3 de esa caja fue antes de contar, aunque no la tuviera;
/// - lo que anota un mismo equipo va en el orden de su propio reloj: si conocía un
///   movimiento de ese equipo, todo lo anterior de ese equipo fue antes de contar.
///
/// Por eso se guarda, **de toda la fiesta**, la venta más alta que conocía de cada caja
/// y la fila más nueva que conocía de cada equipo (ventas, anulaciones y movimientos: el
/// orden de un equipo vale para todo lo que anota). Solo lo de una caja o un equipo que
/// no conocía hasta ahí se ordena por la hora (`StockPorBarra`).
///
/// El arranque y el stock general del jefe no van: un producto ya contado no cambia el
/// reparto (lo que se mueve lo anota el repositor), así que la cuenta usa los de hoy.
class FotoDeStock {
  /// Por caja: el número de venta más alto que conocía.
  final Map<String, int> ventasHasta;

  /// Por equipo (`device_id`, '' si no tiene): la fila más nueva que conocía de él (su
  /// `created_at`).
  final Map<String, String> equiposHasta;

  const FotoDeStock({this.ventasHasta = const {}, this.equiposHasta = const {}});

  /// Si conocía lo de [equipo] hasta [momento] o después.
  bool conoce(String? equipo, String momento) {
    final hasta = equiposHasta[equipo ?? ''];
    return hasta != null && compararMomentos(momento, hasta) <= 0;
  }

  String toJson() => jsonEncode({'v': ventasHasta, 'e': equiposHasta});

  /// Null si no hay foto o no se puede leer (escrita por una versión más nueva).
  static FotoDeStock? fromJson(String? texto) {
    if (texto == null || texto.trim().isEmpty) return null;
    try {
      final m = jsonDecode(texto);
      if (m is! Map) return null;
      Map<String, int> numeros(Object? x) => {
            if (x is Map)
              for (final e in x.entries)
                if (e.value is num) e.key.toString(): (e.value as num).toInt(),
          };
      Map<String, String> textos(Object? x) => {
            if (x is Map)
              for (final e in x.entries)
                if (e.value is String) e.key.toString(): e.value as String,
          };
      return FotoDeStock(ventasHasta: numeros(m['v']), equiposHasta: textos(m['e']));
    } catch (_) {
      return null;
    }
  }
}

/// Lo que hace el repositor con el stock de una fiesta (`barra_stock_movimientos`, v83).
/// **Solo se agregan filas**: ninguna se edita ni se borra. Para corregir, otra fila.
///
/// Las reglas de forma (cantidades, notas y motivos obligatorios) están acá; los límites
/// (no más de lo que hay en el depósito, no más de lo que tiene una barra) y la
/// diferencia de un conteo los dice la cuenta, `StockPorBarra`, que sabe cuánto hay.
class MovimientoDeStock {
  final String id;
  final String eventoId;
  final String productoId;

  /// La clave como está guardada. [tipo] la lee.
  final String tipoClave;
  final int cantidad;

  /// De dónde sale: [kDeposito] o el nombre de una barra. Null en una entrada, un conteo
  /// o un aviso.
  final String? desde;

  /// A dónde va: [kDeposito] o el nombre de una barra. Null en un faltante.
  final String? hacia;

  /// Cuántas dijo que hay en [hacia] (en un conteo, o después de reponer o pasar). Con
  /// [conocido], es un conteo: desde ahí, el stock de ese lugar sale de esto.
  final int? contadas;

  /// La diferencia que vio el repositor contra la cuenta, para el historial ("faltaban
  /// 2"). **El stock no la suma**: sale de [contadas] y [conocido].
  final int ajuste;
  final String? motivo;
  final String? nota;

  /// Lo que sabía el equipo al contar ([FotoDeStock], en texto). Null sin conteo.
  final String? conocido;

  /// De un "voy en camino": cuántas reposiciones y traspasos hacia esa barra y ese
  /// producto **había hecho este mismo equipo** (los conoce todos). Queda "en camino"
  /// hasta que este equipo reponga ahí, o hasta que alguien lo saque.
  final int? avisosPrevios;

  /// El "voy en camino" que contesta: lo saca ("ya no voy") o lo cumple (la reposición
  /// que salió de ese aviso).
  final String? respondeA;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const MovimientoDeStock({
    required this.id,
    required this.eventoId,
    required this.productoId,
    required this.tipoClave,
    required this.cantidad,
    this.desde,
    this.hacia,
    this.contadas,
    this.ajuste = 0,
    this.motivo,
    this.nota,
    this.conocido,
    this.avisosPrevios,
    this.respondeA,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  TipoMovimientoDeStock? get tipo => TipoMovimientoDeStock.deClave(tipoClave);

  /// La foto de lo que sabía al contar, o null.
  FotoDeStock? get foto => FotoDeStock.fromJson(conocido);

  /// Si es un conteo: dejó dicho cuántas hay, con lo que sabía.
  bool get esConteo => contadas != null && foto != null && hacia != null;

  static MovimientoDeStock _nuevo({
    required String eventoId,
    required String productoId,
    required TipoMovimientoDeStock tipo,
    required int cantidad,
    String? desde,
    String? hacia,
    int? contadas,
    FotoDeStock? foto,
    int ajuste = 0,
    String? motivo,
    String? nota,
    int? avisosPrevios,
    String? respondeA,
    String? hechoPor,
    required DateTime ahora,
  }) {
    if (cantidad < 0) {
      throw ArgumentError.value(cantidad, 'cantidad', 'no puede ser negativa');
    }
    if (contadas != null && contadas < 0) {
      throw ArgumentError.value(contadas, 'contadas', 'no puede ser negativo');
    }
    if ((contadas == null) != (foto == null)) {
      throw ArgumentError('lo contado va con lo que se sabía al contar');
    }
    final m = comoTextoONull(motivo);
    if (ajuste != 0 && m == null) {
      throw ArgumentError.value(motivo, 'motivo', 'si no da la cuenta, hace falta el motivo');
    }
    final id = UuidUtils.generate();
    final iso = isoDe(ahora);
    return MovimientoDeStock(
      id: id,
      eventoId: eventoId,
      productoId: productoId,
      tipoClave: tipo.clave,
      cantidad: cantidad,
      desde: desde,
      hacia: hacia,
      contadas: contadas,
      // Una reposición contada incluye lo que repuso: `StockPorBarra` la cuenta como
      // anterior a lo contado.
      conocido: foto?.toJson(),
      ajuste: ajuste,
      motivo: m,
      nota: comoTextoONull(nota),
      avisosPrevios: avisosPrevios,
      respondeA: respondeA,
      hechoPor: hechoPor,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  static String _barra(String barra) {
    final b = lugarDeStock(barra);
    if (b == kDeposito) {
      throw ArgumentError.value(barra, 'barra', 'hace falta el nombre de una barra');
    }
    return b;
  }

  static void _positiva(int cantidad) {
    if (cantidad <= 0) {
      throw ArgumentError.value(cantidad, 'cantidad', 'tiene que ser al menos 1');
    }
  }

  /// Entró mercadería al depósito. [deDonde] es obligatorio.
  factory MovimientoDeStock.entrada({
    required String eventoId,
    required String productoId,
    required int cantidad,
    required String deDonde,
    String? hechoPor,
    required DateTime ahora,
  }) {
    _positiva(cantidad);
    if (comoTextoONull(deDonde) == null) {
      throw ArgumentError.value(deDonde, 'deDonde', 'hace falta decir de dónde vino');
    }
    return _nuevo(
      eventoId: eventoId,
      productoId: productoId,
      tipo: TipoMovimientoDeStock.entrada,
      cantidad: cantidad,
      hacia: kDeposito,
      nota: deDonde,
      hechoPor: hechoPor,
      ahora: ahora,
    );
  }

  /// Del depósito a [barra]. Si dejó dicho cuántas quedan ([contadas], con la [foto] de
  /// lo que sabía antes de reponer), es también un conteo; si no daba la cuenta,
  /// [ajuste] y [motivo].
  factory MovimientoDeStock.reposicion({
    required String eventoId,
    required String productoId,
    required String barra,
    required int cantidad,
    int? contadas,
    FotoDeStock? foto,
    int ajuste = 0,
    String? motivo,
    String? nota,
    String? respondeA,
    String? hechoPor,
    required DateTime ahora,
  }) {
    _positiva(cantidad);
    return _nuevo(
      eventoId: eventoId,
      productoId: productoId,
      tipo: TipoMovimientoDeStock.reposicion,
      cantidad: cantidad,
      desde: kDeposito,
      hacia: _barra(barra),
      contadas: contadas,
      foto: foto,
      ajuste: ajuste,
      motivo: motivo,
      nota: nota,
      respondeA: respondeA,
      hechoPor: hechoPor,
      ahora: ahora,
    );
  }

  /// De [desdeBarra] a [haciaBarra]. [porque] es obligatorio.
  factory MovimientoDeStock.traspaso({
    required String eventoId,
    required String productoId,
    required String desdeBarra,
    required String haciaBarra,
    required int cantidad,
    required String porque,
    int? contadas,
    FotoDeStock? foto,
    int ajuste = 0,
    String? motivo,
    String? respondeA,
    String? hechoPor,
    required DateTime ahora,
  }) {
    _positiva(cantidad);
    final desde = _barra(desdeBarra), hacia = _barra(haciaBarra);
    if (claveDeBarra(desde) == claveDeBarra(hacia)) {
      throw ArgumentError.value(haciaBarra, 'haciaBarra', 'tiene que ser otra barra');
    }
    if (comoTextoONull(porque) == null) {
      throw ArgumentError.value(porque, 'porque', 'hace falta decir por qué');
    }
    return _nuevo(
      eventoId: eventoId,
      productoId: productoId,
      tipo: TipoMovimientoDeStock.traspaso,
      cantidad: cantidad,
      desde: desde,
      hacia: hacia,
      contadas: contadas,
      foto: foto,
      ajuste: ajuste,
      motivo: motivo,
      nota: porque,
      respondeA: respondeA,
      hechoPor: hechoPor,
      ahora: ahora,
    );
  }

  /// Lo que falta en [lugar] (una barra o el depósito) y no es una venta. [motivo] es
  /// obligatorio.
  factory MovimientoDeStock.faltante({
    required String eventoId,
    required String productoId,
    required String lugar,
    required int cantidad,
    required String motivo,
    String? nota,
    String? hechoPor,
    required DateTime ahora,
  }) {
    _positiva(cantidad);
    if (comoTextoONull(motivo) == null) {
      throw ArgumentError.value(motivo, 'motivo', 'hace falta el motivo');
    }
    return _nuevo(
      eventoId: eventoId,
      productoId: productoId,
      tipo: TipoMovimientoDeStock.faltante,
      cantidad: cantidad,
      desde: lugarDeStock(lugar),
      motivo: motivo,
      nota: nota,
      hechoPor: hechoPor,
      ahora: ahora,
    );
  }

  /// "Anotar lo que hay" en [lugar]: [contadas], con la [foto] de lo que sabía el equipo.
  /// Si no daba la cuenta, [ajuste] y su [motivo].
  factory MovimientoDeStock.conteo({
    required String eventoId,
    required String productoId,
    required String lugar,
    required int contadas,
    required FotoDeStock foto,
    int ajuste = 0,
    String? motivo,
    String? nota,
    String? hechoPor,
    required DateTime ahora,
  }) =>
      _nuevo(
        eventoId: eventoId,
        productoId: productoId,
        tipo: TipoMovimientoDeStock.conteo,
        cantidad: 0,
        hacia: lugarDeStock(lugar),
        contadas: contadas,
        foto: foto,
        ajuste: ajuste,
        motivo: motivo,
        nota: nota,
        hechoPor: hechoPor,
        ahora: ahora,
      );

  /// "Voy en camino" a [barra] con [productoId]. [avisosPrevios]: cuántas reposiciones y
  /// traspasos hacia esa barra y ese producto hizo **este equipo**
  /// (`StockPorBarra.llegadasDesde`).
  factory MovimientoDeStock.enCamino({
    required String eventoId,
    required String productoId,
    required String barra,
    required int avisosPrevios,
    String? hechoPor,
    required DateTime ahora,
  }) =>
      _nuevo(
        eventoId: eventoId,
        productoId: productoId,
        tipo: TipoMovimientoDeStock.enCamino,
        cantidad: 0,
        hacia: _barra(barra),
        avisosPrevios: avisosPrevios,
        hechoPor: hechoPor,
        ahora: ahora,
      );

  /// "Ya no voy": saca el "voy en camino" [aviso] (no hay en el depósito, o lo repuso
  /// otro).
  factory MovimientoDeStock.yaNoVoy({
    required MovimientoDeStock aviso,
    String? nota,
    String? hechoPor,
    required DateTime ahora,
  }) {
    if (aviso.tipo != TipoMovimientoDeStock.enCamino) {
      throw ArgumentError.value(aviso.tipoClave, 'aviso', 'solo se saca un "voy en camino"');
    }
    return _nuevo(
      eventoId: aviso.eventoId,
      productoId: aviso.productoId,
      tipo: TipoMovimientoDeStock.enCaminoNo,
      cantidad: 0,
      hacia: aviso.hacia,
      respondeA: aviso.id,
      nota: nota,
      hechoPor: hechoPor,
      ahora: ahora,
    );
  }

  /// El mismo movimiento, con el equipo que lo anotó: lo pone el repositorio.
  MovimientoDeStock conEquipo(String? equipo) => MovimientoDeStock(
        id: id,
        eventoId: eventoId,
        productoId: productoId,
        tipoClave: tipoClave,
        cantidad: cantidad,
        desde: desde,
        hacia: hacia,
        contadas: contadas,
        ajuste: ajuste,
        motivo: motivo,
        nota: nota,
        conocido: conocido,
        avisosPrevios: avisosPrevios,
        respondeA: respondeA,
        hechoPor: hechoPor,
        deviceId: equipo ?? deviceId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'producto_id': productoId,
        'tipo': tipoClave,
        'cantidad': cantidad,
        'desde': desde,
        'hacia': hacia,
        'contadas': contadas,
        'ajuste': ajuste,
        'motivo': motivo,
        'nota': nota,
        'conocido': conocido,
        'avisos_previos': avisosPrevios,
        'responde_a': respondeA,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory MovimientoDeStock.fromMap(Map<String, dynamic> m) {
    String? lugar(Object? x) {
      final t = comoTextoONull(x);
      if (t == null) return null;
      try {
        return lugarDeStock(t);
      } catch (_) {
        return null;
      }
    }

    return MovimientoDeStock(
      id: comoTexto(m['id']),
      eventoId: comoTexto(m['evento_id']),
      productoId: comoTexto(m['producto_id']),
      tipoClave: comoTexto(m['tipo']),
      cantidad: comoInt(m['cantidad']),
      desde: lugar(m['desde']),
      hacia: lugar(m['hacia']),
      contadas: comoIntONull(m['contadas']),
      ajuste: comoInt(m['ajuste']),
      motivo: comoTextoONull(m['motivo']),
      nota: comoTextoONull(m['nota']),
      conocido: comoTextoONull(m['conocido']),
      avisosPrevios: comoIntONull(m['avisos_previos']),
      respondeA: comoTextoONull(m['responde_a']),
      hechoPor: comoTextoONull(m['hecho_por']),
      deviceId: comoTextoONull(m['device_id']),
      createdAt: comoTexto(m['created_at']),
      updatedAt: comoTexto(m['updated_at']),
    );
  }
}
