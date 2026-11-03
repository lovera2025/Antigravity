import '../datos/venta_barra.dart';
import 'pesos.dart';

/// El mixto: parte en efectivo y parte por transferencia, en dos casilleros atados.
/// Escribir uno completa el otro para que sumen el total, y **los dos se pueden
/// corregir**: el último que se tocó manda.
class PartidoMixto {
  final double total;
  final double efectivo;

  const PartidoMixto._(this.total, this.efectivo);

  /// Empieza todo por transferencia: la cajera escribe cuánto le dan en efectivo.
  factory PartidoMixto.de(double total) => PartidoMixto._(total, 0);

  double get transferencia => deCentavos(centavos(total) - centavos(efectivo));

  /// Lo que se escriba de más queda en el total; lo negativo, en cero.
  PartidoMixto conEfectivo(double e) =>
      PartidoMixto._(total, deCentavos(centavos(e).clamp(0, centavos(total))));

  PartidoMixto conTransferencia(double t) => PartidoMixto._(
        total,
        deCentavos(centavos(total) - centavos(t).clamp(0, centavos(total))),
      );

  /// Un mixto lleva las dos partes; si una queda en cero, es efectivo o transferencia.
  bool get lasDosPartes => centavos(efectivo) > 0 && centavos(transferencia) > 0;
}

/// Lo que se cobra en COBRAR: el medio, lo que entrega en efectivo, la tilde del
/// comprobante y el mixto. Dice si se puede confirmar y, si no, **por qué**, con las
/// palabras que lee la cajera. No cambia nunca: cada cambio da un cobro nuevo.
///
/// Lo que confirma arma una venta que cierra (`VentaBarra.nueva`): un test lo prueba
/// con todos los medios.
class CobroBarra {
  final double total;
  final MedioBarra medio;

  /// Lo que entrega en efectivo, para el vuelto. Null: no se anotó (paga justo).
  final double? recibe;
  final bool comprobanteVisto;
  final PartidoMixto mixto;

  const CobroBarra._({
    required this.total,
    required this.medio,
    required this.recibe,
    required this.comprobanteVisto,
    required this.mixto,
  });

  /// Un cobro nuevo, en efectivo, sin nada anotado.
  factory CobroBarra.de(double total) => CobroBarra._(
        total: total,
        medio: MedioBarra.efectivo,
        recibe: null,
        comprobanteVisto: false,
        mixto: PartidoMixto.de(total),
      );

  CobroBarra _con({
    MedioBarra? medio,
    double? recibe,
    bool sinRecibe = false,
    bool? comprobanteVisto,
    PartidoMixto? mixto,
  }) =>
      CobroBarra._(
        total: total,
        medio: medio ?? this.medio,
        recibe: sinRecibe ? null : (recibe ?? this.recibe),
        comprobanteVisto: comprobanteVisto ?? this.comprobanteVisto,
        mixto: mixto ?? this.mixto,
      );

  /// Cambiar de medio deja lo demás como estaba, por si vuelve.
  CobroBarra conMedio(MedioBarra m) {
    if (m == MedioBarra.otro) throw ArgumentError.value(m, 'medio', 'no se cobra así');
    return _con(medio: m);
  }

  /// Null o un casillero vacío: paga justo.
  CobroBarra conRecibe(double? r) => r == null ? _con(sinRecibe: true) : _con(recibe: r);

  CobroBarra conComprobante(bool visto) => _con(comprobanteVisto: visto);

  CobroBarra conEfectivoDelMixto(double e) => _con(mixto: mixto.conEfectivo(e));

  CobroBarra conTransferenciaDelMixto(double t) => _con(mixto: mixto.conTransferencia(t));

  double get efectivo => switch (medio) {
        MedioBarra.efectivo => total,
        MedioBarra.mixto => mixto.efectivo,
        MedioBarra.transferencia || MedioBarra.otro => 0,
      };

  double get transferencia => deCentavos(centavos(total) - centavos(efectivo));

  /// Lo que entregó, si cuenta: por transferencia no se entrega efectivo.
  double? get recibeQueCuenta => medio == MedioBarra.transferencia ? null : recibe;

  /// Lo que se le devuelve. Null si no anotó lo que entrega.
  double? get vuelto {
    final r = recibeQueCuenta;
    if (r == null || centavos(r) < centavos(efectivo)) return null;
    return deCentavos(centavos(r) - centavos(efectivo));
  }

  /// Por qué no se puede confirmar todavía. Null: se puede.
  String? get falta {
    if (centavos(total) <= 0) return 'La cuenta está vacía';
    if (medio == MedioBarra.mixto && !mixto.lasDosPartes) {
      return 'El mixto lleva una parte en efectivo y otra por transferencia';
    }
    final r = recibeQueCuenta;
    if (r != null && centavos(r) < centavos(efectivo)) {
      return medio == MedioBarra.mixto
          ? 'Entrega menos que la parte en efectivo'
          : 'Entrega menos que el total';
    }
    if (centavos(transferencia) > 0 && !comprobanteVisto) {
      return 'Falta tildar "Vi el comprobante"';
    }
    return null;
  }

  bool get puedeConfirmar => falta == null;
}
