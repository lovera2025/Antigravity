import '../../../core/utils/uuid_utils.dart';
import 'caja_barra.dart';
import 'lectura_de_filas.dart';

/// Qué es cada fila de `barra_cierres`.
enum TipoPasoDelCierre {
  /// La cajera contó a ciegas y pide cerrar: lleva lo contado.
  pedido('pedido'),

  /// La encargada (o el jefe) aceptó: la tablet de la cajera cierra la caja.
  ok('ok'),

  /// La encargada pide que cuente de nuevo.
  recontar('recontar'),

  /// La cajera volvió a vender: el pedido ya no vale.
  cancelado('cancelado'),

  /// La cajera cerró sin esperar el OK (no había encargada, o no había red), con motivo.
  sinOk('sin_ok');

  final String clave;
  const TipoPasoDelCierre(this.clave);

  /// Null si la clave no se conoce (la escribió una versión más nueva): esa fila se
  /// ignora, no rompe nada.
  static TipoPasoDelCierre? deClave(String? clave) {
    for (final t in values) {
      if (t.clave == clave) return t;
    }
    return null;
  }
}

/// Un paso del cierre de una caja de barra (`barra_cierres`, v79; pedido del usuario del
/// 11-nov-2026): **la caja se cierra cuando la encargada acepta.**
///
/// La cajera cuenta a ciegas y su tablet anota el **pedido**; el aparato de la encargada
/// anota la **respuesta** (ok, o que cuente de nuevo), y con el ok la tablet de la cajera
/// cierra la caja. **Solo se agregan filas**, y `barra_cajas` no se toca hasta el cierre
/// de verdad: la caja la sigue cerrando su propio equipo.
///
/// Viaja como las ventas: por la central de la barra (el wifi del salón) y por la nube.
class PasoDelCierre {
  final String id;
  final String cajaBarraId;
  final String eventoId;

  /// La clave como está guardada. [tipo] la lee.
  final String tipoClave;

  /// De una respuesta: el pedido que contesta. Null en el pedido.
  final String? pedidoId;

  /// Del pedido: lo que contó la cajera.
  final double? efectivoContado;

  /// Del pedido, la nota de la cajera; de "sin ok", por qué no esperó.
  final String? nota;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const PasoDelCierre({
    required this.id,
    required this.cajaBarraId,
    required this.eventoId,
    required this.tipoClave,
    this.pedidoId,
    this.efectivoContado,
    this.nota,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  TipoPasoDelCierre? get tipo => TipoPasoDelCierre.deClave(tipoClave);

  bool get esPedido => tipo == TipoPasoDelCierre.pedido;

  /// La cajera contó y pide cerrar [caja].
  factory PasoDelCierre.pedir({
    required CajaBarra caja,
    required double efectivoContado,
    String? nota,
    String? hechoPor,
    required DateTime ahora,
  }) {
    if (efectivoContado.isNaN || efectivoContado < 0) {
      throw ArgumentError.value(efectivoContado, 'efectivoContado', 'no puede ser negativo');
    }
    final iso = isoDe(ahora);
    return PasoDelCierre(
      id: UuidUtils.generate(),
      cajaBarraId: caja.id,
      eventoId: caja.eventoId,
      tipoClave: TipoPasoDelCierre.pedido.clave,
      efectivoContado: efectivoContado,
      nota: comoTextoONull(nota),
      hechoPor: hechoPor,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  /// Lo que se le contesta a [pedido]. [tipo] no puede ser otro pedido.
  factory PasoDelCierre.responder({
    required PasoDelCierre pedido,
    required TipoPasoDelCierre tipo,
    String? nota,
    String? hechoPor,
    required DateTime ahora,
  }) {
    if (tipo == TipoPasoDelCierre.pedido) {
      throw ArgumentError.value(tipo, 'tipo', 'una respuesta no es otro pedido');
    }
    if (!pedido.esPedido) {
      throw ArgumentError.value(pedido.tipoClave, 'pedido', 'solo se contesta un pedido');
    }
    final iso = isoDe(ahora);
    return PasoDelCierre(
      id: UuidUtils.generate(),
      cajaBarraId: pedido.cajaBarraId,
      eventoId: pedido.eventoId,
      tipoClave: tipo.clave,
      pedidoId: pedido.id,
      nota: comoTextoONull(nota),
      hechoPor: hechoPor,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  /// El mismo paso, con el equipo que lo anotó: lo pone el repositorio.
  PasoDelCierre conEquipo(String? equipo) => PasoDelCierre(
        id: id,
        cajaBarraId: cajaBarraId,
        eventoId: eventoId,
        tipoClave: tipoClave,
        pedidoId: pedidoId,
        efectivoContado: efectivoContado,
        nota: nota,
        hechoPor: hechoPor,
        deviceId: equipo ?? deviceId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'caja_barra_id': cajaBarraId,
        'evento_id': eventoId,
        'tipo': tipoClave,
        'pedido_id': pedidoId,
        'efectivo_contado': efectivoContado,
        'nota': nota,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory PasoDelCierre.fromMap(Map<String, dynamic> m) => PasoDelCierre(
        id: comoTexto(m['id']),
        cajaBarraId: comoTexto(m['caja_barra_id']),
        eventoId: comoTexto(m['evento_id']),
        tipoClave: comoTexto(m['tipo']),
        pedidoId: comoTextoONull(m['pedido_id']),
        efectivoContado: comoDoubleONull(m['efectivo_contado']),
        nota: comoTextoONull(m['nota']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
