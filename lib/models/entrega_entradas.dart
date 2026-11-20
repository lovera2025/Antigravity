import '../core/utils/uuid_utils.dart';
import 'entradas_retiro.dart';

/// Las dos partes de lo que trae la mesa del contrato sin cargo, que llegan en
/// dos tandas (audio del jefe, 20-nov-2026): las pulseras VIP con cena (el
/// egresado y sus acompañantes) y las entradas generales que completan la mesa.
///
/// La [clave] es lo que se guarda en `entradas_entregas.parte`.
enum ParteEntrega {
  pulseras('pulseras', 'pulseras VIP con cena', 'pulsera VIP con cena'),
  generales('generales', 'entradas generales', 'entrada general');

  final String clave;

  /// Cómo se nombra en un aviso: "Ya se le entregaron las pulseras VIP…".
  final String nombre;

  /// Una sola: "1 pulsera VIP con cena".
  final String nombreDeUna;

  const ParteEntrega(this.clave, this.nombre, this.nombreDeUna);

  /// "1 pulsera VIP con cena", "3 pulseras VIP con cena", "1 entrada general":
  /// lo más común es una sola (el egresado solo), y "1 pulseras" se leía mal
  /// (revisión del 20-nov-2026).
  String cuantas(int n) => n == 1 ? '1 $nombreDeUna' : '$n $nombre';

  /// Null si la clave no es una de estas: una versión más nueva puede anotar
  /// algo que esta no conoce, y nunca se inventa qué fue.
  static ParteEntrega? deClave(String? clave) {
    for (final p in values) {
      if (p.clave == clave) return p;
    }
    return null;
  }
}

/// Qué se hizo con una parte. (No se llama `AccionEntrega`: ese nombre ya es el
/// de lo que elige quien atiende en el diálogo de la entrega.)
enum QueSeHizo {
  entrega('entrega'),
  anulacion('anulacion');

  final String clave;
  const QueSeHizo(this.clave);

  /// Null si la clave no es una de estas (ver [ParteEntrega.deClave]).
  static QueSeHizo? deClave(String? clave) {
    for (final q in values) {
      if (q.clave == clave) return q;
    }
    return null;
  }
}

/// Un renglón de `entradas_entregas` (v81): la entrega o la anulación de **una
/// parte** de lo sin cargo de un egresado.
///
/// **Solo se agregan renglones: nunca se editan ni se borran.** Anular una parte
/// es otro renglón, y el estado de cada parte es su último renglón
/// (`EstadoDeLaEntrega`). Así dos equipos que entregan partes distintas, con o
/// sin internet, nunca se pisan: cada uno sube su renglón.
///
/// La parte y lo que se hizo se guardan como texto ([parteClave],
/// [accionClave]) y se leen con [parte] y [accion]: un valor que esta versión
/// no conoce vuelve a la base igual que vino, y quien decide el estado lo
/// ignora.
class EntregaEntradas {
  final String id;
  final String contratoAlumnoId;
  final String? eventoId;
  final String parteClave;
  final String accionClave;

  /// Cuántas: las pulseras o las generales que se llevó (o las que se anularon).
  final int cantidad;

  /// Los números de las generales, si vienen numeradas. Opcionales: puede que
  /// el material de los alumnos no traiga número. En las pulseras, vacío.
  final List<TramoTalonario> tramos;

  /// Menores de 10: no llevan entrada ni ocupan lugar. Se anotan igual.
  final int menores10;

  final ParentescoRetiro? parentesco;

  /// Nombre y apellido de quien retiró, como lo escribió el operador.
  final String? retiroNombre;

  /// Solo para "otra persona": por qué no vino un familiar directo.
  final String? otraPersonaMotivo;
  final bool autorizacionFirmada;

  /// Quien retiró escribió su nombre y apellido en la planilla de papel de esa
  /// parte.
  final bool escribioEnPlanilla;

  /// Por qué se anuló. En una entrega, vacío (o la nota de una copia: ver
  /// [kCopiaDeLaFila]).
  final String? motivo;

  /// Quién lo anotó (el operador, o "Jefe").
  final String? hechoPor;
  final String? deviceId;

  final DateTime createdAt;
  final DateTime updatedAt;

  const EntregaEntradas({
    required this.id,
    required this.contratoAlumnoId,
    this.eventoId,
    required this.parteClave,
    required this.accionClave,
    required this.cantidad,
    this.tramos = const [],
    this.menores10 = 0,
    this.parentesco,
    this.retiroNombre,
    this.otraPersonaMotivo,
    this.autorizacionFirmada = false,
    this.escribioEnPlanilla = false,
    this.motivo,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// La nota de un renglón que copia lo que decía la fila de `entradas_retiro`
  /// (una entrega de una sola vez, o una anulación hecha desde una 6.9.x), justo
  /// antes de reescribir esa fila: si no, se perdería (`EntregaPorPartes`).
  static const kCopiaDeLaFila = 'Copia de la entrega de una sola vez';

  ParteEntrega? get parte => ParteEntrega.deClave(parteClave);
  QueSeHizo? get accion => QueSeHizo.deClave(accionClave);

  bool get esEntrega => accion == QueSeHizo.entrega;
  bool get esAnulacion => accion == QueSeHizo.anulacion;

  /// La entrega de una parte. Las pulseras van sin número: si llegan números,
  /// se descartan. El nombre se guarda como en `entradas_retiro`: sin espacios
  /// de más y en mayúsculas.
  factory EntregaEntradas.entrega({
    String? id,
    required String contratoAlumnoId,
    required String? eventoId,
    required ParteEntrega parte,
    required int cantidad,
    List<TramoTalonario> tramos = const [],
    int menores10 = 0,
    required ParentescoRetiro parentesco,
    required String nombre,
    String motivoOtraPersona = '',
    bool autorizacionFirmada = false,
    required bool escribioEnPlanilla,
    String? nota,
    required String? hechoPor,
    required String? deviceId,
    required DateTime ahora,
  }) {
    final otra = parentesco == ParentescoRetiro.otraPersona;
    return EntregaEntradas(
      id: id ?? UuidUtils.generate(),
      contratoAlumnoId: contratoAlumnoId,
      eventoId: eventoId,
      parteClave: parte.clave,
      accionClave: QueSeHizo.entrega.clave,
      cantidad: cantidad < 0 ? 0 : cantidad,
      tramos: parte == ParteEntrega.generales ? List.unmodifiable(tramos) : const [],
      menores10: menores10 < 0 ? 0 : menores10,
      parentesco: parentesco,
      retiroNombre: nombreDeQuienRetira(nombre),
      otraPersonaMotivo: otra ? motivoOtraPersona.trim() : null,
      autorizacionFirmada: otra && autorizacionFirmada,
      escribioEnPlanilla: escribioEnPlanilla,
      motivo: nota,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: ahora,
      updatedAt: ahora,
    );
  }

  /// La anulación de una parte: **solo del jefe, y con motivo**. Lleva lo que se
  /// anuló (cuántas y sus números), para que quede escrito.
  factory EntregaEntradas.anulacion({
    String? id,
    required String contratoAlumnoId,
    required String? eventoId,
    required ParteEntrega parte,
    required int cantidad,
    List<TramoTalonario> tramos = const [],
    required String motivo,
    required String? hechoPor,
    required String? deviceId,
    required DateTime ahora,
  }) {
    final m = motivo.trim();
    if (m.isEmpty) {
      throw ArgumentError.value(motivo, 'motivo', 'anular lleva motivo');
    }
    return EntregaEntradas(
      id: id ?? UuidUtils.generate(),
      contratoAlumnoId: contratoAlumnoId,
      eventoId: eventoId,
      parteClave: parte.clave,
      accionClave: QueSeHizo.anulacion.clave,
      cantidad: cantidad < 0 ? 0 : cantidad,
      tramos: parte == ParteEntrega.generales ? List.unmodifiable(tramos) : const [],
      motivo: m,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: ahora,
      updatedAt: ahora,
    );
  }

  /// "PÉREZ, ANA": como lo guarda `RetiroEntradas.nuevaEntrega`.
  static String nombreDeQuienRetira(String nombre) =>
      nombre.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

  /// Los renglones de cada alumno, del más viejo al más nuevo: por
  /// [createdAt] y, a la misma hora, por [id] (así dos equipos los ordenan
  /// igual).
  static Map<String, List<EntregaEntradas>> porAlumno(
    Iterable<EntregaEntradas> renglones,
  ) {
    final out = <String, List<EntregaEntradas>>{};
    for (final r in renglones) {
      out.putIfAbsent(r.contratoAlumnoId, () => []).add(r);
    }
    for (final lista in out.values) {
      lista.sort(enOrden);
    }
    return out;
  }

  /// El orden de los renglones: por [createdAt] y después por [id].
  static int enOrden(EntregaEntradas a, EntregaEntradas b) {
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

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

  static int _entero(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }

  static String? _textoONull(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  /// Venga de la base de la PC o de la nube. **Nunca tira:** una fila rara se
  /// lee con ceros, y una parte o una acción que no se conocen quedan como
  /// vinieron.
  factory EntregaEntradas.fromMap(Map<String, dynamic> map) => EntregaEntradas(
        id: map['id']?.toString() ?? '',
        contratoAlumnoId: map['contrato_alumno_id']?.toString() ?? '',
        eventoId: _textoONull(map['evento_id']),
        parteClave: map['parte']?.toString() ?? '',
        accionClave: map['accion']?.toString() ?? '',
        cantidad: _entero(map['cantidad']),
        tramos: TramoTalonario.deTexto(map['tramos']?.toString()),
        menores10: _entero(map['menores_10']),
        parentesco: ParentescoRetiro.deClave(map['parentesco']?.toString()),
        retiroNombre: _textoONull(map['retiro_nombre']),
        otraPersonaMotivo: _textoONull(map['otra_persona_motivo']),
        autorizacionFirmada: _si(map['autorizacion_firmada']),
        escribioEnPlanilla: _si(map['escribio_en_planilla']),
        motivo: _textoONull(map['motivo']),
        hechoPor: _textoONull(map['hecho_por']),
        deviceId: _textoONull(map['device_id']),
        createdAt: _fecha(map['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedAt: _fecha(map['updated_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  /// El renglón completo, con las casillas como 0/1 y las fechas en UTC ISO,
  /// como `entradas_retiro`. La cola de sync lo manda así.
  Map<String, dynamic> toMap() => {
        'id': id,
        'contrato_alumno_id': contratoAlumnoId,
        'evento_id': eventoId,
        'parte': parteClave,
        'accion': accionClave,
        'cantidad': cantidad,
        'tramos': TramoTalonario.aTexto(tramos),
        'menores_10': menores10,
        'parentesco': parentesco?.clave,
        'retiro_nombre': retiroNombre,
        'otra_persona_motivo': otraPersonaMotivo,
        'autorizacion_firmada': autorizacionFirmada ? 1 : 0,
        'escribio_en_planilla': escribioEnPlanilla ? 1 : 0,
        'motivo': motivo,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}
