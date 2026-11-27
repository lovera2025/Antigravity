import '../../../core/utils/uuid_utils.dart';
import 'lectura_de_filas.dart';

/// Qué pasó con la plata de una caja de barra, además de vender.
enum TipoMovimientoDeCaja {
  /// La encargada (o el jefe) se llevó efectivo de la caja, con el porqué.
  retiro('retiro'),

  /// La encargada le dio más cambio a una caja abierta.
  cambio('cambio'),

  /// Se corrige el cambio con que abrió (se anotó mal): más o menos, con el porqué.
  ajusteCambio('ajuste_cambio');

  final String clave;
  const TipoMovimientoDeCaja(this.clave);

  /// Null: una clave que esta versión no conoce (no se cuenta).
  static TipoMovimientoDeCaja? deClave(String? clave) {
    for (final t in values) {
      if (t.clave == clave) return t;
    }
    return null;
  }
}

/// Un retiro de efectivo o un cambio dado a una caja de barra (`barra_caja_movimientos`,
/// v84; plan del 4-dic, "quién puede qué": solo la encargada y el jefe). **Solo se
/// agregan filas**: corregir es otro movimiento. Entra en el efectivo que tiene que haber
/// al cerrar (`CierreDeBarra.efectivoEsperado`) y viaja por la red del salón.
class MovimientoDeCaja {
  final String id;
  final String eventoId;
  final String cajaBarraId;
  final TipoMovimientoDeCaja? tipo;

  /// En pesos. Retiro y cambio, siempre más que 0; el ajuste, más o menos (nunca 0).
  final double monto;

  /// El porqué. Obligatorio.
  final String motivo;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const MovimientoDeCaja({
    required this.id,
    required this.eventoId,
    required this.cajaBarraId,
    required this.tipo,
    required this.monto,
    required this.motivo,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MovimientoDeCaja.nuevo({
    required String eventoId,
    required String cajaBarraId,
    required TipoMovimientoDeCaja tipo,
    required double monto,
    required String motivo,
    String? hechoPor,
    required DateTime ahora,
  }) {
    if (monto.isNaN || monto == 0 || (tipo != TipoMovimientoDeCaja.ajusteCambio && monto < 0)) {
      throw ArgumentError.value(monto, 'monto', 'no es un monto válido para ${tipo.clave}');
    }
    if (motivo.trim().isEmpty) throw ArgumentError.value(motivo, 'motivo', 'falta el porqué');
    final iso = isoDe(ahora);
    return MovimientoDeCaja(
      id: UuidUtils.generate(),
      eventoId: eventoId,
      cajaBarraId: cajaBarraId,
      tipo: tipo,
      monto: monto,
      motivo: motivo.trim(),
      hechoPor: hechoPor,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  /// Lo que suma al efectivo de la caja (en centavos): el retiro resta.
  int get efectoEnCentavos {
    final c = (monto * 100).round();
    return switch (tipo) {
      TipoMovimientoDeCaja.retiro => -c,
      TipoMovimientoDeCaja.cambio || TipoMovimientoDeCaja.ajusteCambio => c,
      null => 0,
    };
  }

  MovimientoDeCaja sellado({String? hechoPor, String? deviceId, required DateTime ahora}) => MovimientoDeCaja(
        id: id,
        eventoId: eventoId,
        cajaBarraId: cajaBarraId,
        tipo: tipo,
        monto: monto,
        motivo: motivo,
        hechoPor: hechoPor ?? this.hechoPor,
        deviceId: deviceId,
        createdAt: createdAt,
        updatedAt: isoDe(ahora),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'caja_barra_id': cajaBarraId,
        'tipo': tipo?.clave,
        'monto': monto,
        'motivo': motivo,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory MovimientoDeCaja.fromMap(Map<String, dynamic> m) => MovimientoDeCaja(
        id: comoTexto(m['id']),
        eventoId: comoTexto(m['evento_id']),
        cajaBarraId: comoTexto(m['caja_barra_id']),
        tipo: TipoMovimientoDeCaja.deClave(comoTextoONull(m['tipo'])),
        monto: comoDouble(m['monto']),
        motivo: comoTexto(m['motivo']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
