/// Período con que `AppRoleNotifier._startHeartbeat` publica el latido de una
/// sesión activa. Los umbrales de abajo se derivan de acá: no son números
/// elegidos a dedo.
const Duration kLatidoSesionPeriodo = Duration(seconds: 60);

/// Una caja realmente en uso nunca puede tener un latido más viejo que el
/// período más un margen. Por debajo de esto se puede **afirmar** que otra
/// máquina la está usando ahora mismo.
const Duration kLatidoSesionVivo = Duration(seconds: 90);

/// Por encima de esto la sesión quedó abierta y nadie la está tocando (PC
/// apagada, o cerrada sin red). Entre ambos umbrales **no se sabe**, y el
/// programa no debe afirmar nada.
const Duration kLatidoSesionMuerto = Duration(minutes: 5);

// ── Notas de cierre generadas por el sistema ────────────────────────────────
// Se declaran como constantes para poder distinguir un cierre automático de uno
// hecho por una persona sin agregar columnas a la base.

const String kNotaCierreCambioDiaJefe = 'Cierre automático por cambio de día';
const String kNotaCierreCambioDiaCaja =
    'Cierre automático por cambio de día · sin arqueo';
const String kNotaCierreTomadaOtraPc =
    'Cerrada al tomar la caja en otra PC · sin arqueo';
const String kNotaCierreDuplicada = 'Duplicada por apertura sin conexión';

/// Incluye las notas de versiones anteriores para que las sesiones ya cerradas
/// también queden bien clasificadas en el cierre de caja.
const Set<String> kNotasCierreAutomatico = {
  kNotaCierreCambioDiaJefe,
  kNotaCierreCambioDiaCaja,
  kNotaCierreTomadaOtraPc,
  kNotaCierreDuplicada,
  'Cerrada al iniciar jornada (modo jefe)',
  'Cerrada al eliminar operador',
  'Cerrada: operador inactivo o eliminado',
};

class SesionCaja {
  final String id;
  final String operadorId;
  final DateTime abiertaAt;
  final DateTime? cerradaAt;
  final double cambioInicial;
  final String? notaApertura;
  final String? etiqueta;
  final double? arqueoCierre;
  final String? notaCierre;
  final String? deviceId;
  final DateTime? lastHeartbeat;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Nombre denormalizado para UI (join local).
  final String? operadorNombre;

  const SesionCaja({
    required this.id,
    required this.operadorId,
    required this.abiertaAt,
    this.cerradaAt,
    required this.cambioInicial,
    this.notaApertura,
    this.etiqueta,
    this.arqueoCierre,
    this.notaCierre,
    this.deviceId,
    this.lastHeartbeat,
    required this.createdAt,
    required this.updatedAt,
    this.operadorNombre,
  });

  bool get estaAbierta => cerradaAt == null;

  /// Antigüedad del último latido.
  ///
  /// Una antigüedad negativa significa que el reloj del otro equipo está
  /// adelantado; se trata como cero porque con relojes desfasados no se puede
  /// afirmar nada, y equivocarse hacia "recién vista" solo cuesta un clic.
  Duration antiguedadLatido({DateTime? ahora}) {
    final hb = (lastHeartbeat ?? abiertaAt).toUtc();
    final d = (ahora ?? DateTime.now().toUtc()).difference(hb);
    return d.isNegative ? Duration.zero : d;
  }

  /// Alguien la está usando **ahora**. Es lo único que el latido permite
  /// afirmar; fuera de esta ventana solo se puede informar.
  bool enUsoAhora({DateTime? ahora}) =>
      estaAbierta && antiguedadLatido(ahora: ahora) < kLatidoSesionVivo;

  /// Quedó abierta y hace rato que no da señales.
  bool sinSenales({DateTime? ahora}) =>
      estaAbierta && antiguedadLatido(ahora: ahora) > kLatidoSesionMuerto;

  /// Nadie contó la plata al cerrar.
  bool get sinArqueo => !estaAbierta && arqueoCierre == null;

  /// La cerró el sistema, no una persona.
  bool get cierreAutomatico =>
      !estaAbierta &&
      kNotasCierreAutomatico.contains((notaCierre ?? '').trim());

  factory SesionCaja.fromMap(Map<String, dynamic> m) {
    return SesionCaja(
      id: m['id'] as String,
      operadorId: m['operador_id'] as String,
      abiertaAt:
          DateTime.tryParse(m['abierta_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      cerradaAt: m['cerrada_at'] != null
          ? DateTime.tryParse(m['cerrada_at'].toString())
          : null,
      cambioInicial: (m['cambio_inicial'] as num?)?.toDouble() ?? 0,
      notaApertura: m['nota_apertura'] as String?,
      etiqueta: m['etiqueta'] as String?,
      arqueoCierre: (m['arqueo_cierre'] as num?)?.toDouble(),
      notaCierre: m['nota_cierre'] as String?,
      deviceId: m['device_id'] as String?,
      lastHeartbeat: m['last_heartbeat'] != null
          ? DateTime.tryParse(m['last_heartbeat'].toString())
          : null,
      createdAt:
          DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse(m['updated_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      operadorNombre: m['operador_nombre'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'operador_id': operadorId,
    'abierta_at': abiertaAt.toUtc().toIso8601String(),
    'cerrada_at': cerradaAt?.toUtc().toIso8601String(),
    'cambio_inicial': cambioInicial,
    'nota_apertura': notaApertura,
    'etiqueta': etiqueta,
    'arqueo_cierre': arqueoCierre,
    'nota_cierre': notaCierre,
    'device_id': deviceId,
    'last_heartbeat': lastHeartbeat?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toSyncPayload() => toMap();

  SesionCaja copyWith({
    DateTime? cerradaAt,
    double? arqueoCierre,
    String? notaCierre,
    DateTime? lastHeartbeat,
    DateTime? updatedAt,
    String? operadorNombre,
    bool clearCerrada = false,
  }) {
    return SesionCaja(
      id: id,
      operadorId: operadorId,
      abiertaAt: abiertaAt,
      cerradaAt: clearCerrada ? null : (cerradaAt ?? this.cerradaAt),
      cambioInicial: cambioInicial,
      notaApertura: notaApertura,
      etiqueta: etiqueta,
      arqueoCierre: arqueoCierre ?? this.arqueoCierre,
      notaCierre: notaCierre ?? this.notaCierre,
      deviceId: deviceId,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      operadorNombre: operadorNombre ?? this.operadorNombre,
    );
  }
}
