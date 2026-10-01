import 'dart:convert';

import '../core/utils/uuid_utils.dart';
import '../features/plano/estilos/estilo_plano.dart';
import '../features/plano/modelo/armado_salon.dart';
import '../features/plano/modelo/medidas_salon.dart';

/// Cómo se sortea la fiesta sobre su plano.
enum ModoSorteo {
  /// Toda la escuela junta, como hasta ahora.
  entera('entera'),

  /// Cada división en su bloque de mesas seguidas.
  bloques('bloques');

  final String clave;
  const ModoSorteo(this.clave);

  static ModoSorteo deClave(String? clave) =>
      clave == 'bloques' ? ModoSorteo.bloques : ModoSorteo.entera;
}

DateTime? _fecha(Object? v) => v is String ? DateTime.tryParse(v) : null;
String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

/// Un texto del JSON, o null si vino otra cosa. Un `as String?` tiraría con un
/// número, y un solo dato mal escrito dejaría trabado el sorteo de la fiesta.
String? _texto(Object? v) => v is String ? v : null;

/// Una mesa reservada para una familia antes del sorteo (por ejemplo, una
/// silla de ruedas cerca del ingreso).
class MesaFijada {
  final String alumnoId;
  final String? motivo;
  final String? por;
  final DateTime? cuando;

  const MesaFijada({required this.alumnoId, this.motivo, this.por, this.cuando});

  Map<String, dynamic> toMap() => {
        'alumno': alumnoId,
        if (motivo != null) 'motivo': motivo,
        if (por != null) 'por': por,
        if (cuando != null) 'cuando': _iso(cuando),
      };

  static MesaFijada? fromMap(Object? v) {
    if (v is! Map) return null;
    final alumno = v['alumno'];
    if (alumno is! String || alumno.isEmpty) return null;
    return MesaFijada(
      alumnoId: alumno,
      motivo: _texto(v['motivo']),
      por: _texto(v['por']),
      cuando: _fecha(v['cuando']),
    );
  }
}

/// Una mesa que se deja sin usar: el sorteo no la da.
class MesaLibre {
  final String? motivo;
  final String? por;
  final DateTime? cuando;

  const MesaLibre({this.motivo, this.por, this.cuando});

  Map<String, dynamic> toMap() => {
        if (motivo != null) 'motivo': motivo,
        if (por != null) 'por': por,
        if (cuando != null) 'cuando': _iso(cuando),
      };

  static MesaLibre fromMap(Object? v) => v is Map
      ? MesaLibre(
          motivo: _texto(v['motivo']),
          por: _texto(v['por']),
          cuando: _fecha(v['cuando']),
        )
      : const MesaLibre();
}

/// El rango de mesas que le tocó a una división en un sorteo por bloques.
class BloqueDivision {
  final String division;
  final int desde;
  final int hasta;

  const BloqueDivision(this.division, this.desde, this.hasta);

  bool contiene(int n) => n >= desde && n <= hasta;

  Map<String, dynamic> toMap() =>
      {'division': division, 'desde': desde, 'hasta': hasta};

  static BloqueDivision? fromMap(Object? v) {
    if (v is! Map) return null;
    final d = v['division'];
    final a = v['desde'];
    final b = v['hasta'];
    if (d is! String || a is! num || b is! num) return null;
    return BloqueDivision(d, a.toInt(), b.toInt());
  }
}

/// Lo que se configura del plano de una fiesta. Viaja como un JSON en la
/// columna `config`.
///
/// Las claves que esta versión no conoce **se conservan** al guardar: una
/// versión más nueva puede agregar algo sin que la vieja se lo borre.
class ConfigPlano {
  final Map<int, MesaFijada> fijadas;
  final Map<int, MesaLibre> libres;
  final List<String> ordenDivisiones;
  final List<BloqueDivision> bloques;

  /// División → índice en la paleta del estilo.
  final Map<String, int> colores;
  final String? titulo;
  final String? subtitulo;

  /// Cuánto lugar pide cada mesa y cómo es el playón. Sin tocar, son las de
  /// fábrica, y así no se guardan: si se corrige la medida del playón en el
  /// programa, las fiestas que no la cambiaron la toman.
  final MedidasPlano medidas;
  final Map<String, dynamic> otras;

  const ConfigPlano({
    this.fijadas = const {},
    this.libres = const {},
    this.ordenDivisiones = const [],
    this.bloques = const [],
    this.colores = const {},
    this.titulo,
    this.subtitulo,
    this.medidas = const MedidasPlano(),
    this.otras = const {},
  });

  static const vacia = ConfigPlano();

  static const _conocidas = {
    'fijadas',
    'libres',
    'orden_divisiones',
    'bloques',
    'colores',
    'titulo',
    'subtitulo',
    'medidas',
  };

  /// Las mesas fijadas, agrupadas por familia.
  Map<String, List<int>> get fijadasPorAlumno {
    final r = <String, List<int>>{};
    for (final e in fijadas.entries) {
      r.putIfAbsent(e.value.alumnoId, () => []).add(e.key);
    }
    for (final l in r.values) {
      l.sort();
    }
    return r;
  }

  /// Un JSON roto o de otra forma no rompe nada: queda la configuración vacía.
  factory ConfigPlano.fromJson(String? texto) {
    if (texto == null || texto.trim().isEmpty) return vacia;
    Object? crudo;
    try {
      crudo = jsonDecode(texto);
    } catch (_) {
      return vacia;
    }
    if (crudo is! Map) return vacia;
    final m = Map<String, dynamic>.from(crudo);

    Map<int, T> porNumero<T>(Object? v, T? Function(Object?) leer) {
      final r = <int, T>{};
      if (v is Map) {
        for (final e in v.entries) {
          final n = int.tryParse(e.key.toString());
          final x = leer(e.value);
          if (n != null && x != null) r[n] = x;
        }
      }
      return r;
    }

    final colores = <String, int>{};
    final c = m['colores'];
    if (c is Map) {
      for (final e in c.entries) {
        final v = e.value;
        if (v is num) colores[e.key.toString()] = v.toInt();
      }
    }

    return ConfigPlano(
      fijadas: porNumero(m['fijadas'], MesaFijada.fromMap),
      libres: porNumero(m['libres'], MesaLibre.fromMap),
      ordenDivisiones: [
        for (final d in (m['orden_divisiones'] is List
            ? m['orden_divisiones'] as List
            : const []))
          if (d is String) d,
      ],
      bloques: [
        for (final b in (m['bloques'] is List ? m['bloques'] as List : const []))
          ?BloqueDivision.fromMap(b),
      ],
      colores: colores,
      titulo: _texto(m['titulo']),
      subtitulo: _texto(m['subtitulo']),
      medidas: MedidasPlano.fromMap(m['medidas']),
      otras: {
        for (final e in m.entries)
          if (!_conocidas.contains(e.key)) e.key: e.value,
      },
    );
  }

  String toJson() => jsonEncode({
        ...otras,
        'fijadas': {
          for (final e in fijadas.entries) '${e.key}': e.value.toMap(),
        },
        'libres': {
          for (final e in libres.entries) '${e.key}': e.value.toMap(),
        },
        'orden_divisiones': ordenDivisiones,
        'bloques': [for (final b in bloques) b.toMap()],
        'colores': colores,
        if (titulo != null) 'titulo': titulo,
        if (subtitulo != null) 'subtitulo': subtitulo,
        if (medidas != const MedidasPlano()) 'medidas': medidas.toMap(),
      });

  ConfigPlano copyWith({
    Map<int, MesaFijada>? fijadas,
    Map<int, MesaLibre>? libres,
    List<String>? ordenDivisiones,
    List<BloqueDivision>? bloques,
    Map<String, int>? colores,
    String? titulo,
    String? subtitulo,
    MedidasPlano? medidas,
    bool borrarTitulo = false,
    bool borrarSubtitulo = false,
  }) =>
      ConfigPlano(
        fijadas: fijadas ?? this.fijadas,
        libres: libres ?? this.libres,
        ordenDivisiones: ordenDivisiones ?? this.ordenDivisiones,
        bloques: bloques ?? this.bloques,
        colores: colores ?? this.colores,
        titulo: borrarTitulo ? null : (titulo ?? this.titulo),
        subtitulo: borrarSubtitulo ? null : (subtitulo ?? this.subtitulo),
        medidas: medidas ?? this.medidas,
        otras: otras,
      );
}

/// El plano de una fiesta: una fila por evento en `planos_evento`, con id fijo
/// (`UuidUtils.planoEventoId`).
///
/// Una fiesta sin fila funciona exactamente como antes del plano.
class PlanoEvento {
  final String id;
  final String eventoId;

  /// La clave del armado de fábrica del que salió (`normal_2a_p3@1`).
  final String armadoClave;

  /// La copia del armado, en JSON: es la que manda para esta fiesta.
  final String armadoJson;

  /// La clave del estilo. Uno que esta versión no conoce no se pierde al
  /// guardar; la pantalla pide elegir de nuevo.
  final String estilo;
  final ModoSorteo modoSorteo;
  final ConfigPlano config;
  final String? hechoPor;
  final DateTime createdAt;
  final DateTime updatedAt;

  PlanoEvento({
    required this.id,
    required this.eventoId,
    required this.armadoClave,
    required this.armadoJson,
    required this.estilo,
    required this.modoSorteo,
    this.config = ConfigPlano.vacia,
    this.hechoPor,
    required this.createdAt,
    required this.updatedAt,
  });

  /// El id no lo elige quien llama: es el fijo de la fiesta, así las dos PCs
  /// escriben la misma fila. Con otro, la nube lo rechaza por el
  /// `unique (evento_id)` y el plano no sube nunca.
  factory PlanoEvento.nuevo({
    required String eventoId,
    required ArmadoSalon armado,
    required EstiloPlano estilo,
    required ModoSorteo modo,
    String? hechoPor,
    required DateTime ahora,
  }) =>
      PlanoEvento(
        id: UuidUtils.planoEventoId(eventoId),
        eventoId: eventoId,
        armadoClave: armado.clave,
        armadoJson: jsonEncode(armado.toJson()),
        estilo: estilo.name,
        modoSorteo: modo,
        hechoPor: hechoPor,
        createdAt: ahora,
        updatedAt: ahora,
      );

  EstiloPlano? get estiloPlano => EstiloPlano.deClave(estilo);

  /// Si lleva el id fijo de su fiesta. Uno que no lo lleva no se guarda.
  bool get tieneIdFijo => id == UuidUtils.planoEventoId(eventoId);

  /// El armado de esta fiesta, o null si su copia no se puede leer (un
  /// `armado_json` roto o sin mesas). Quien lo use tiene que avisar y pedir
  /// que se elija el armado de nuevo, no romper.
  late final ArmadoSalon? armadoONull = _leerArmado();

  ArmadoSalon? _leerArmado() {
    try {
      final crudo = jsonDecode(armadoJson);
      if (crudo is! Map) return null;
      final a = ArmadoSalon.fromJson(Map<String, dynamic>.from(crudo));
      return a.mesas.isEmpty ? null : a;
    } catch (_) {
      return null;
    }
  }

  /// El armado, para quien ya comprobó [armadoONull].
  ArmadoSalon get armado =>
      armadoONull ??
      (throw StateError('El armado del plano de la fiesta no se puede leer.'));

  /// Cambia si cambia el contenido del plano: el sorteo la mira para saber si
  /// alguien lo tocó mientras el diálogo estaba abierto.
  ///
  /// No lleva `updatedAt` a propósito: esa fecha la reescribe el trigger de la
  /// nube al subir, y con el mismo plano daba un "la lista cambió" falso.
  String get huella =>
      '$armadoClave|$estilo|${modoSorteo.clave}|'
      '${config.toJson().hashCode}|${armadoJson.hashCode}';

  PlanoEvento copyWith({
    ArmadoSalon? armado,
    EstiloPlano? estilo,
    ModoSorteo? modoSorteo,
    ConfigPlano? config,
    String? hechoPor,
    required DateTime ahora,
  }) =>
      PlanoEvento(
        id: id,
        eventoId: eventoId,
        armadoClave: armado?.clave ?? armadoClave,
        armadoJson: armado == null ? armadoJson : jsonEncode(armado.toJson()),
        estilo: estilo?.name ?? this.estilo,
        modoSorteo: modoSorteo ?? this.modoSorteo,
        config: config ?? this.config,
        hechoPor: hechoPor ?? this.hechoPor,
        createdAt: createdAt,
        updatedAt: ahora,
      );

  /// La fila para SQLite y para la cola. Ninguna columna NOT NULL va vacía:
  /// en la nube una fila rechazada queda trabada en la cola.
  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'armado': armadoClave,
        'armado_json': armadoJson,
        'estilo': estilo,
        'modo_sorteo': modoSorteo.clave,
        'config': config.toJson(),
        'hecho_por': hechoPor,
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
      };

  factory PlanoEvento.fromMap(Map<String, dynamic> m) {
    final creado =
        _fecha(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return PlanoEvento(
      id: m['id'] as String,
      eventoId: m['evento_id'] as String,
      armadoClave: (m['armado'] as String?) ?? '',
      armadoJson: (m['armado_json'] as String?) ?? '{}',
      estilo: (m['estilo'] as String?) ?? '',
      modoSorteo: ModoSorteo.deClave(m['modo_sorteo'] as String?),
      config: ConfigPlano.fromJson(m['config'] as String?),
      hechoPor: m['hecho_por'] as String?,
      createdAt: creado,
      updatedAt: _fecha(m['updated_at']) ?? creado,
    );
  }
}
