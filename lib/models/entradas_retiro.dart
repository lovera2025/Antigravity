/// Quién puede retirar las entradas: un familiar directo del egresado, o, como
/// excepción, otra persona con autorización firmada por la familia.
///
/// La [clave] es lo que se guarda; la [etiqueta], lo que se lee en pantalla y
/// en la planilla.
enum ParentescoRetiro {
  egresado('egresado', 'Egresado/a'),
  madre('madre', 'Madre'),
  padre('padre', 'Padre'),
  tutor('tutor', 'Tutor/a'),
  hermanoMayor('hermano_mayor', 'Hermano/a mayor'),
  abuelo('abuelo', 'Abuelo/a'),
  otraPersona('otra_persona', 'Otra persona');

  final String clave;
  final String etiqueta;
  const ParentescoRetiro(this.clave, this.etiqueta);

  bool get esFamiliarDirecto => this != ParentescoRetiro.otraPersona;

  static ParentescoRetiro? deClave(String? clave) {
    for (final p in values) {
      if (p.clave == clave) return p;
    }
    return null;
  }
}

/// Números seguidos del talonario, del [desde] al [hasta] inclusive.
class TramoTalonario {
  final int desde;
  final int hasta;

  const TramoTalonario(this.desde, this.hasta);

  int get cantidad => hasta - desde + 1;

  bool seCruzaCon(TramoTalonario otro) =>
      !(hasta < otro.desde || desde > otro.hasta);

  /// "1043 al 1058", o "1043" si es un solo número.
  String get texto => desde == hasta ? '$desde' : '$desde al $hasta';

  @override
  bool operator ==(Object other) =>
      other is TramoTalonario && other.desde == desde && other.hasta == hasta;

  @override
  int get hashCode => Object.hash(desde, hasta);

  @override
  String toString() => texto;

  /// Cómo se guarda: "1043-1058,1101-1108".
  static String aTexto(List<TramoTalonario> tramos) =>
      tramos.map((t) => '${t.desde}-${t.hasta}').join(',');

  /// Lee lo guardado. Lo que no se entiende se descarta: nunca inventa números.
  static List<TramoTalonario> deTexto(String? texto) {
    final out = <TramoTalonario>[];
    for (final parte in (texto ?? '').split(',')) {
      final p = parte.trim();
      if (p.isEmpty) continue;
      final nums = p.split('-').map((s) => int.tryParse(s.trim())).toList();
      if (nums.length == 1 && nums.first != null) {
        out.add(TramoTalonario(nums.first!, nums.first!));
      } else if (nums.length == 2 &&
          nums[0] != null &&
          nums[1] != null &&
          nums[0]! <= nums[1]!) {
        out.add(TramoTalonario(nums[0]!, nums[1]!));
      }
    }
    return out;
  }

  /// "1043 al 1058 y 1101 al 1108".
  static String legible(List<TramoTalonario> tramos) {
    if (tramos.isEmpty) return '-';
    final textos = tramos.map((t) => t.texto).toList();
    if (textos.length == 1) return textos.single;
    return '${textos.sublist(0, textos.length - 1).join(', ')} y ${textos.last}';
  }
}

enum EstadoRetiro {
  entregado('entregado'),
  anulado('anulado');

  final String clave;
  const EstadoRetiro(this.clave);

  static EstadoRetiro deClave(String? clave) =>
      clave == anulado.clave ? anulado : entregado;
}

/// La entrega de entradas de un egresado: una fila por alumno.
///
/// Anular no borra la fila: queda con estado anulado, quién y por qué. Si
/// después se vuelve a entregar, se reescribe la misma fila.
class EntradasRetiro {
  final String id;
  final String contratoAlumnoId;
  final EstadoRetiro estado;

  /// Egresado y acompañantes: tienen cena. Sin número.
  final int vip;

  /// Entradas generales entregadas, con sus números del talonario.
  final int generales;
  final List<TramoTalonario> tramos;

  /// Menores de 10: no llevan entrada ni ocupan lugar. Se anotan igual.
  final int menores10;

  final ParentescoRetiro? parentesco;

  /// Nombre y apellido de quien retiró, como lo escribió el operador.
  final String? retiroNombre;

  /// Solo para "otra persona": por qué no vino un familiar directo.
  final String? otraPersonaMotivo;
  final bool autorizacionFirmada;

  /// Quien retiró escribió su nombre y apellido en la planilla de papel.
  final bool escribioEnPlanilla;

  final String? entregadoPor;
  final DateTime? entregadoAt;
  final String? anuladoPor;
  final DateTime? anuladoAt;
  final String? anuladoMotivo;

  final DateTime createdAt;
  final DateTime updatedAt;

  const EntradasRetiro({
    required this.id,
    required this.contratoAlumnoId,
    required this.estado,
    required this.vip,
    required this.generales,
    required this.tramos,
    this.menores10 = 0,
    this.parentesco,
    this.retiroNombre,
    this.otraPersonaMotivo,
    this.autorizacionFirmada = false,
    this.escribioEnPlanilla = false,
    this.entregadoPor,
    this.entregadoAt,
    this.anuladoPor,
    this.anuladoAt,
    this.anuladoMotivo,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get entregado => estado == EstadoRetiro.entregado;

  /// Entradas que se llevó: VIP más generales.
  int get entradas => vip + generales;

  static DateTime? _fecha(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : DateTime.tryParse(s);
  }

  static bool _si(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().trim().toLowerCase() ?? '';
    return s == 'true' || s == '1';
  }

  factory EntradasRetiro.fromMap(Map<String, dynamic> map) {
    int entero(Object? v) => (v as num?)?.toInt() ?? 0;
    return EntradasRetiro(
      id: map['id'] as String? ?? '',
      contratoAlumnoId: map['contrato_alumno_id'] as String,
      estado: EstadoRetiro.deClave(map['estado'] as String?),
      vip: entero(map['vip']),
      generales: entero(map['generales']),
      tramos: TramoTalonario.deTexto(map['tramos'] as String?),
      menores10: entero(map['menores_10']),
      parentesco: ParentescoRetiro.deClave(map['parentesco'] as String?),
      retiroNombre: map['retiro_nombre'] as String?,
      otraPersonaMotivo: map['otra_persona_motivo'] as String?,
      autorizacionFirmada: _si(map['autorizacion_firmada']),
      escribioEnPlanilla: _si(map['escribio_en_planilla']),
      entregadoPor: map['entregado_por'] as String?,
      entregadoAt: _fecha(map['entregado_at']),
      anuladoPor: map['anulado_por'] as String?,
      anuladoAt: _fecha(map['anulado_at']),
      anuladoMotivo: map['anulado_motivo'] as String?,
      createdAt: _fecha(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _fecha(map['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// La fila completa, con los booleanos como 0/1 para SQLite. La cola de sync
  /// los manda así también, igual que `notas_operativas_contrato.resuelto`.
  Map<String, dynamic> toMap() => {
        'id': id,
        'contrato_alumno_id': contratoAlumnoId,
        'estado': estado.clave,
        'vip': vip,
        'generales': generales,
        'tramos': TramoTalonario.aTexto(tramos),
        'menores_10': menores10,
        'parentesco': parentesco?.clave,
        'retiro_nombre': retiroNombre,
        'otra_persona_motivo': otraPersonaMotivo,
        'autorizacion_firmada': autorizacionFirmada ? 1 : 0,
        'escribio_en_planilla': escribioEnPlanilla ? 1 : 0,
        'entregado_por': entregadoPor,
        'entregado_at': entregadoAt?.toUtc().toIso8601String(),
        'anulado_por': anuladoPor,
        'anulado_at': anuladoAt?.toUtc().toIso8601String(),
        'anulado_motivo': anuladoMotivo,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}
