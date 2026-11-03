import '../datos/venta_barra.dart';
import 'pesos.dart';

/// El mixto: parte en efectivo y parte por transferencia, en dos casilleros atados.
/// Escribir uno completa el otro para que sumen el total, y **los dos se pueden
/// corregir**: el último que se tocó manda. Son las partes de lo que valen las bebidas:
/// el recargo va aparte, en [CobroBarra].
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

/// Cómo se calcula el recargo por transferencia: un porcentaje de lo transferido, o
/// unos pesos escritos a mano.
enum ModoRecargo { porcentaje, pesos }

/// Redondea a pesos enteros: en la barra no hay centavos.
double _aPesos(double v) => v.isNaN ? 0 : v.roundToDouble();

/// Lo que se cobra al tocar EFECTIVO, TRANSFERENCIA o MIXTO: lo que entrega en efectivo,
/// el mixto y el recargo por transferencia. Dice si se puede confirmar y, si no,
/// **por qué**, con las palabras que lee la cajera. No cambia nunca: cada cambio da un
/// cobro nuevo.
///
/// **Transferencia es todo lo que entra por Mercado Pago** (posnet con QR, débito o
/// transferencia): quien cobra lo ve en el momento, así que no hay comprobante que
/// tildar (decidido el 3-nov).
///
/// **El recargo va solo sobre lo que se transfiere** (en el mixto, sobre esa parte), en
/// pesos enteros. Lo que confirma arma una venta que cierra (`VentaBarra.nueva`), con
/// la transferencia ya con el recargo: un test lo prueba con todos los medios.
class CobroBarra {
  /// Lo que valen las bebidas.
  final double total;
  final MedioBarra medio;

  /// Lo que entrega en efectivo, para el vuelto. Null: no se anotó (paga justo).
  final double? recibe;
  final PartidoMixto mixto;

  /// El check del recargo.
  final bool recargoPrendido;
  final ModoRecargo modoRecargo;
  final double recargoPct;
  final double recargoPesos;

  const CobroBarra._({
    required this.total,
    required this.medio,
    required this.recibe,
    required this.mixto,
    required this.recargoPrendido,
    required this.modoRecargo,
    required this.recargoPct,
    required this.recargoPesos,
  });

  /// Un cobro nuevo por [medio], sin nada anotado, con el recargo como lo dejó este
  /// equipo la última vez.
  factory CobroBarra.de(
    double total, {
    MedioBarra medio = MedioBarra.efectivo,
    bool recargo = true,
    double recargoPct = 5,
  }) {
    if (medio == MedioBarra.otro) throw ArgumentError.value(medio, 'medio', 'no se cobra así');
    return CobroBarra._(
      total: total,
      medio: medio,
      recibe: null,
      mixto: PartidoMixto.de(total),
      recargoPrendido: recargo,
      modoRecargo: ModoRecargo.porcentaje,
      recargoPct: recargoPct,
      recargoPesos: 0,
    );
  }

  CobroBarra _con({
    MedioBarra? medio,
    double? recibe,
    bool sinRecibe = false,
    PartidoMixto? mixto,
    bool? recargoPrendido,
    ModoRecargo? modoRecargo,
    double? recargoPct,
    double? recargoPesos,
  }) =>
      CobroBarra._(
        total: total,
        medio: medio ?? this.medio,
        recibe: sinRecibe ? null : (recibe ?? this.recibe),
        mixto: mixto ?? this.mixto,
        recargoPrendido: recargoPrendido ?? this.recargoPrendido,
        modoRecargo: modoRecargo ?? this.modoRecargo,
        recargoPct: recargoPct ?? this.recargoPct,
        recargoPesos: recargoPesos ?? this.recargoPesos,
      );

  /// Cambiar de medio deja lo demás como estaba, por si vuelve.
  CobroBarra conMedio(MedioBarra m) {
    if (m == MedioBarra.otro) throw ArgumentError.value(m, 'medio', 'no se cobra así');
    return _con(medio: m);
  }

  /// Null o un casillero vacío: paga justo.
  CobroBarra conRecibe(double? r) => r == null ? _con(sinRecibe: true) : _con(recibe: r);

  CobroBarra conEfectivoDelMixto(double e) => _con(mixto: mixto.conEfectivo(e));

  /// La parte de las bebidas que se transfiere, sin el recargo.
  CobroBarra conTransferenciaDelMixto(double t) => _con(mixto: mixto.conTransferencia(t));

  /// Lo que la cajera escribe en "Por transferencia" del mixto: **con el recargo
  /// incluido**, que es lo que se ve. De ahí sale la parte de las bebidas.
  CobroBarra conTransfiereDelMixto(double t) {
    final liquido = !recargoPrendido
        ? t
        : switch (modoRecargo) {
            ModoRecargo.porcentaje => _aPesos(t / (1 + recargoPct.clamp(0, 100) / 100)),
            ModoRecargo.pesos => t - recargoPesos,
          };
    return conTransferenciaDelMixto(liquido);
  }

  CobroBarra conRecargo(bool prendido) => _con(recargoPrendido: prendido);
  CobroBarra conModoRecargo(ModoRecargo m) => _con(modoRecargo: m);

  /// Lo negativo queda en cero; más de 100 %, en 100.
  CobroBarra conRecargoPct(double pct) =>
      _con(recargoPct: pct.isNaN ? 0 : pct.clamp(0, 100).toDouble());
  CobroBarra conRecargoPesos(double p) =>
      _con(recargoPesos: p.isNaN || p < 0 ? 0 : _aPesos(p));

  double get efectivo => switch (medio) {
        MedioBarra.efectivo => total,
        MedioBarra.mixto => mixto.efectivo,
        MedioBarra.transferencia || MedioBarra.otro => 0,
      };

  /// La parte de las bebidas que se paga por transferencia, sin el recargo.
  double get transferencia => deCentavos(centavos(total) - centavos(efectivo));

  /// Lo que se cobra de más por transferir. Cero sin transferencia o con el check
  /// apagado.
  double get recargo {
    if (!recargoPrendido || centavos(transferencia) <= 0) return 0;
    return switch (modoRecargo) {
      ModoRecargo.porcentaje => _aPesos(transferencia * recargoPct / 100),
      ModoRecargo.pesos => recargoPesos,
    };
  }

  /// El porcentaje que queda anotado en la venta: null si fue en pesos o sin recargo.
  double? get recargoPctQueQueda =>
      centavos(recargo) > 0 && modoRecargo == ModoRecargo.porcentaje ? recargoPct : null;

  /// Lo que hay que transferir: la parte de las bebidas más el recargo.
  double get transfiere => deCentavos(centavos(transferencia) + centavos(recargo));

  /// Todo lo que paga, con el recargo.
  double get aCobrar => deCentavos(centavos(total) + centavos(recargo));

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
      return 'Poné cuánto es en efectivo y cuánto por transferencia';
    }
    if (recargoPrendido && centavos(transferencia) > 0) {
      if (modoRecargo == ModoRecargo.porcentaje && recargoPct <= 0) {
        return 'Poné el porcentaje del recargo';
      }
      if (modoRecargo == ModoRecargo.pesos && recargoPesos <= 0) {
        return 'Poné el recargo en pesos';
      }
    }
    final r = recibeQueCuenta;
    if (r != null && centavos(r) < centavos(efectivo)) {
      return medio == MedioBarra.mixto
          ? 'Entrega menos que la parte en efectivo'
          : 'Entrega menos que el total';
    }
    return null;
  }

  bool get puedeConfirmar => falta == null;
}
