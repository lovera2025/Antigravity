import 'dart:math' as math;

/// Un rectángulo en las coordenadas del plano (las del Canva del jefe, en la
/// misma escala para todos los armados: una mesa mide ~76 de diámetro).
class RectPlano {
  final double x;
  final double y;
  final double ancho;
  final double alto;

  const RectPlano(this.x, this.y, this.ancho, this.alto);

  double get derecha => x + ancho;
  double get abajo => y + alto;
  double get centroX => x + ancho / 2;
  double get centroY => y + alto / 2;

  bool contieneCirculo(double cx, double cy, double r) =>
      cx - r >= x - 0.01 &&
      cx + r <= derecha + 0.01 &&
      cy - r >= y - 0.01 &&
      cy + r <= abajo + 0.01;

  /// Cuánto se mete un círculo adentro del rectángulo (0 si no lo toca).
  double solapeConCirculo(double cx, double cy, double r) {
    final px = cx.clamp(x, derecha);
    final py = cy.clamp(y, abajo);
    final d = math.sqrt((cx - px) * (cx - px) + (cy - py) * (cy - py));
    return d >= r ? 0 : r - d;
  }

  RectPlano mover(double dx, double dy) =>
      RectPlano(x + dx, y + dy, ancho, alto);

  List<double> toJson() => [x, y, ancho, alto];

  static RectPlano fromJson(Object? v) {
    final l = (v as List).map((e) => (e as num).toDouble()).toList();
    return RectPlano(l[0], l[1], l[2], l[3]);
  }

  @override
  bool operator ==(Object other) =>
      other is RectPlano &&
      other.x == x &&
      other.y == y &&
      other.ancho == ancho &&
      other.alto == alto;

  @override
  int get hashCode => Object.hash(x, y, ancho, alto);
}

/// Cuántos metros es una unidad del plano en la escala del Canva del jefe: de
/// centro a centro de mesa hay 105 unidades, que son 2 m (la mesa sola queda
/// de 1,45 m).
const double kMetrosPorUnidadCanva = 2.0 / 105;

/// El borde del hormigón en una hoja: un polígono, en coordenadas del plano.
///
/// Solo lo llevan los armados hechos a medida del playón. Los del Canva no:
/// su geometría sale de fotos, y un "queda fuera del hormigón" sobre los
/// dibujos del jefe sería un aviso falso.
class ContornoPlano {
  final List<({double x, double y})> puntos;

  const ContornoPlano(this.puntos);

  /// Los lados, de punto a punto, cerrando con el primero.
  Iterable<(({double x, double y}), ({double x, double y}))> get lados sync* {
    for (var i = 0; i < puntos.length; i++) {
      yield (puntos[i], puntos[(i + 1) % puntos.length]);
    }
  }

  bool contiene(double x, double y) {
    var adentro = false;
    for (final (a, b) in lados) {
      if ((a.y > y) != (b.y > y) &&
          x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) {
        adentro = !adentro;
      }
    }
    return adentro;
  }

  /// La distancia del punto al lado más cercano.
  double distanciaAlBorde(double x, double y) {
    var mejor = double.infinity;
    for (final (a, b) in lados) {
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final largo2 = dx * dx + dy * dy;
      final t = largo2 == 0
          ? 0.0
          : (((x - a.x) * dx + (y - a.y) * dy) / largo2).clamp(0.0, 1.0);
      final px = a.x + dx * t;
      final py = a.y + dy * t;
      final d = math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
      if (d < mejor) mejor = d;
    }
    return mejor;
  }

  /// El círculo entra entero (se tolera un roce).
  bool contieneCirculo(double x, double y, double r) =>
      puntos.length >= 3 &&
      contiene(x, y) &&
      distanciaAlBorde(x, y) >= r - 0.01;

  List<List<double>> toJson() => [
        for (final p in puntos) [p.x, p.y],
      ];

  /// Null si no hay al menos tres puntos legibles.
  static ContornoPlano? fromJson(Object? v) {
    if (v is! List) return null;
    final puntos = <({double x, double y})>[];
    for (final p in v) {
      if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
        puntos.add((x: (p[0] as num).toDouble(), y: (p[1] as num).toDouble()));
      }
    }
    return puntos.length >= 3 ? ContornoPlano(puntos) : null;
  }
}

/// Una hoja del plano. El Canva parte algunos salones en dos (A arriba, B
/// abajo); cada hoja tiene su propio dibujo y sus propias coordenadas.
class HojaPlano {
  final String id;
  final String titulo;
  final RectPlano caja;

  /// El borde del hormigón, si el armado se hizo a medida del playón.
  final ContornoPlano? contorno;

  const HojaPlano({
    required this.id,
    required this.titulo,
    required this.caja,
    this.contorno,
  });

  HojaPlano copyWith({RectPlano? caja, ContornoPlano? contorno}) => HojaPlano(
        id: id,
        titulo: titulo,
        caja: caja ?? this.caja,
        contorno: contorno ?? this.contorno,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'caja': caja.toJson(),
        if (contorno != null) 'borde': contorno!.toJson(),
      };

  static HojaPlano fromJson(Map<String, dynamic> m) => HojaPlano(
        id: m['id'] as String,
        titulo: (m['titulo'] as String?) ?? '',
        caja: RectPlano.fromJson(m['caja']),
        contorno: ContornoPlano.fromJson(m['borde']),
      );
}

/// Una mesa del salón: su número (el que sale en el sorteo), en qué hoja está y
/// dónde. Las del pasto se usan solo si faltan mesas comunes.
class MesaPlano {
  final int numero;
  final String hoja;
  final double x;
  final double y;
  final bool pasto;

  const MesaPlano({
    required this.numero,
    required this.hoja,
    required this.x,
    required this.y,
    this.pasto = false,
  });

  double distanciaA(MesaPlano o) =>
      math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));

  MesaPlano copyWith({String? hoja, double? x, double? y, bool? pasto}) =>
      MesaPlano(
        numero: numero,
        hoja: hoja ?? this.hoja,
        x: x ?? this.x,
        y: y ?? this.y,
        pasto: pasto ?? this.pasto,
      );

  Map<String, dynamic> toJson() => {
        'n': numero,
        'h': hoja,
        'x': x,
        'y': y,
        if (pasto) 'p': true,
      };

  static MesaPlano fromJson(Map<String, dynamic> m) => MesaPlano(
        numero: (m['n'] as num).toInt(),
        hoja: m['h'] as String,
        x: (m['x'] as num).toDouble(),
        y: (m['y'] as num).toDouble(),
        pasto: m['p'] == true,
      );
}

enum TipoSector {
  escenario,
  pasarela,
  ingreso,
  brindis,
  barra,
  cajas,
  banos,
  pista,
  otro;

  static TipoSector deClave(String? c) => TipoSector.values
      .firstWhere((t) => t.name == c, orElse: () => TipoSector.otro);
}

/// Un sector del salón que no es mesa: escenario, pista, barras, baños.
class SectorPlano {
  final TipoSector tipo;
  final String texto;
  final String hoja;
  final RectPlano caja;

  /// El texto va parado (sectores angostos y altos, como "Sector brindis").
  final bool vertical;

  const SectorPlano({
    required this.tipo,
    required this.texto,
    required this.hoja,
    required this.caja,
    this.vertical = false,
  });

  SectorPlano copyWith({String? texto, RectPlano? caja, bool? vertical}) =>
      SectorPlano(
        tipo: tipo,
        texto: texto ?? this.texto,
        hoja: hoja,
        caja: caja ?? this.caja,
        vertical: vertical ?? this.vertical,
      );

  Map<String, dynamic> toJson() => {
        't': tipo.name,
        'texto': texto,
        'h': hoja,
        'caja': caja.toJson(),
        if (vertical) 'v': true,
      };

  static SectorPlano fromJson(Map<String, dynamic> m) => SectorPlano(
        tipo: TipoSector.deClave(m['t'] as String?),
        texto: (m['texto'] as String?) ?? '',
        hoja: m['h'] as String,
        caja: RectPlano.fromJson(m['caja']),
        vertical: m['v'] == true,
      );
}

/// Un número mayor que cero, o null si vino otra cosa.
double? _positivo(Object? v) =>
    v is num && v.isFinite && v > 0 ? v.toDouble() : null;

/// Un punto en una hoja (el ingreso, de donde el tótem va a trazar el camino).
class PuntoPlano {
  final String hoja;
  final double x;
  final double y;

  const PuntoPlano(this.hoja, this.x, this.y);

  Map<String, dynamic> toJson() => {'h': hoja, 'x': x, 'y': y};

  static PuntoPlano fromJson(Map<String, dynamic> m) => PuntoPlano(
        m['h'] as String,
        (m['x'] as num).toDouble(),
        (m['y'] as num).toDouble(),
      );
}

/// El armado de un salón: dónde está cada mesa, con qué número, y los sectores.
///
/// Los armados de fábrica salen del Canva del jefe
/// ([ArmadosPredefinidos](armados_predefinidos.dart)). Cuando una fiesta elige
/// uno, se guarda **una copia** en su fila de `planos_evento`: así un arreglo
/// posterior del armado de fábrica no le mueve las mesas a una fiesta que ya
/// sorteó, y lo que se acomode a mano queda solo en esa fiesta.
///
/// Los números consecutivos son mesas pegadas (la serpentina del jefe), salvo
/// en los [cortes]: ahí n y n+1 no se tocan (otra hoja, o del otro lado de la
/// pasarela). El sorteo usa los cortes para no partir una familia.
class ArmadoSalon {
  static const int formato = 1;

  /// Qué armado de fábrica es y en qué versión (`normal_2a_p3@1`). Una
  /// numeración publicada no se cambia: un arreglo es una versión nueva.
  final String clave;
  final String nombre;
  final String descripcion;
  final double radio;

  /// Cuántos metros es una unidad de este plano. Con esto el plano mide: la
  /// regla, lo que ocupa y cuánto lugar tiene cada mesa.
  final double metrosPorUnidad;

  /// Hasta qué distancia de centro a centro (en unidades) dos mesas cuentan
  /// como pegadas. Null: [pegadasHastaRadios] radios, como en el Canva. Un
  /// armado a medida con las mesas más separadas trae la suya: si no, toda
  /// diagonal de la serpentina sería un corte.
  final double? distanciaPegadas;
  final List<HojaPlano> hojas;
  final List<MesaPlano> mesas;
  final List<SectorPlano> sectores;
  final PuntoPlano? ingreso;

  ArmadoSalon({
    required this.clave,
    required this.nombre,
    this.descripcion = '',
    this.radio = 38,
    this.metrosPorUnidad = kMetrosPorUnidadCanva,
    this.distanciaPegadas,
    required this.hojas,
    required List<MesaPlano> mesas,
    this.sectores = const [],
    this.ingreso,
  }) : mesas = List.unmodifiable(
          [...mesas]..sort((a, b) => a.numero.compareTo(b.numero)),
        );

  /// Dos mesas están pegadas si están en la misma hoja y a menos de 4,2
  /// radios de centro a centro (alcanza para la diagonal de la serpentina y
  /// deja afuera lo que está del otro lado de una pasarela).
  static const double pegadasHastaRadios = 4.2;

  double get _pegadasHasta => distanciaPegadas ?? pegadasHastaRadios * radio;

  /// Hasta qué distancia de centro a centro, en unidades, dos mesas cuentan
  /// como pegadas en este armado.
  double get pegadasHastaU => _pegadasHasta;

  double aMetros(double unidades) => unidades * metrosPorUnidad;
  double aUnidades(double metros) => metros / metrosPorUnidad;

  /// Se armó a medida del playón: alguna hoja trae el borde del hormigón.
  bool get tieneBorde => hojas.any((h) => h.contorno != null);

  /// Lo que mide la mesa sola, sin las sillas.
  double get diametroMesaM => aMetros(2 * radio);

  /// De centro a centro, en metros. Null si alguna no existe o están en
  /// hojas distintas (cada hoja tiene sus propias coordenadas).
  double? distanciaM(int a, int b) {
    final ma = _porNumero[a];
    final mb = _porNumero[b];
    if (ma == null || mb == null || ma.hoja != mb.hoja) return null;
    return aMetros(ma.distanciaA(mb));
  }

  late final Map<int, MesaPlano> _porNumero = {
    for (final m in mesas) m.numero: m,
  };

  MesaPlano? mesa(int numero) => _porNumero[numero];

  bool existe(int numero) => _porNumero.containsKey(numero);

  List<int> get numeros => [for (final m in mesas) m.numero];

  Set<int> get pasto => {
        for (final m in mesas)
          if (m.pasto) m.numero,
      };

  int get cantidadComunes => mesas.where((m) => !m.pasto).length;
  int get cantidadPasto => mesas.where((m) => m.pasto).length;

  List<MesaPlano> mesasDeHoja(String hoja) =>
      [for (final m in mesas) if (m.hoja == hoja) m];

  List<SectorPlano> sectoresDeHoja(String hoja) =>
      [for (final s in sectores) if (s.hoja == hoja) s];

  HojaPlano? hoja(String id) {
    for (final h in hojas) {
      if (h.id == id) return h;
    }
    return null;
  }

  bool pegadas(int a, int b) {
    final ma = _porNumero[a];
    final mb = _porNumero[b];
    if (ma == null || mb == null) return false;
    if (ma.hoja != mb.hoja) return false;
    return ma.distanciaA(mb) <= _pegadasHasta + 0.01;
  }

  /// Los n tales que n y n+1 existen pero no están pegadas.
  late final Set<int> cortes = {
    for (final m in mesas)
      if (_porNumero.containsKey(m.numero + 1) &&
          !pegadas(m.numero, m.numero + 1))
        m.numero,
  };

  /// Lo que está mal en el armado, en palabras. Vacío si está bien.
  List<String> problemas() {
    final p = <String>[];
    final vistos = <int>{};
    for (final m in mesas) {
      if (m.numero <= 0) p.add('La mesa ${m.numero} no tiene número válido.');
      if (!vistos.add(m.numero)) p.add('La mesa ${m.numero} está dos veces.');
      final h = hoja(m.hoja);
      if (h == null) {
        p.add('La mesa ${m.numero} está en una hoja que no existe (${m.hoja}).');
      } else if (!h.caja.contieneCirculo(m.x, m.y, radio)) {
        p.add('La mesa ${m.numero} se sale de la hoja ${m.hoja}.');
      } else if (!m.pasto &&
          h.contorno != null &&
          !h.contorno!.contieneCirculo(m.x, m.y, radio)) {
        p.add('La mesa ${m.numero} queda fuera del hormigón.');
      }
    }
    for (var i = 0; i < mesas.length; i++) {
      for (var j = i + 1; j < mesas.length; j++) {
        final a = mesas[i];
        final b = mesas[j];
        if (a.hoja == b.hoja && a.distanciaA(b) < 2 * radio - 0.5) {
          p.add('Las mesas ${a.numero} y ${b.numero} se pisan.');
        }
      }
    }
    for (final s in sectores) {
      if (hoja(s.hoja) == null) {
        p.add('El sector "${s.texto}" está en una hoja que no existe.');
        continue;
      }
      for (final m in mesasDeHoja(s.hoja)) {
        // Se tolera un roce; tapar media mesa no.
        if (s.caja.solapeConCirculo(m.x, m.y, radio) > radio * 0.25) {
          p.add('El sector "${s.texto.isEmpty ? s.tipo.name : s.texto}" '
              'tapa la mesa ${m.numero}.');
        }
      }
    }
    return p;
  }

  ArmadoSalon copyWith({
    List<MesaPlano>? mesas,
    List<SectorPlano>? sectores,
    List<HojaPlano>? hojas,
    double? distanciaPegadas,
  }) =>
      ArmadoSalon(
        clave: clave,
        nombre: nombre,
        descripcion: descripcion,
        radio: radio,
        metrosPorUnidad: metrosPorUnidad,
        distanciaPegadas: distanciaPegadas ?? this.distanciaPegadas,
        hojas: hojas ?? this.hojas,
        mesas: mesas ?? this.mesas,
        sectores: sectores ?? this.sectores,
        ingreso: ingreso,
      );

  Map<String, dynamic> toJson() => {
        'formato': formato,
        'clave': clave,
        'nombre': nombre,
        'descripcion': descripcion,
        'radio': radio,
        'm_u': metrosPorUnidad,
        if (distanciaPegadas != null) 'pegadas_u': distanciaPegadas,
        'hojas': [for (final h in hojas) h.toJson()],
        'mesas': [for (final m in mesas) m.toJson()],
        'sectores': [for (final s in sectores) s.toJson()],
        if (ingreso != null) 'ingreso': ingreso!.toJson(),
      };

  static ArmadoSalon fromJson(Map<String, dynamic> m) => ArmadoSalon(
        clave: (m['clave'] as String?) ?? '',
        nombre: (m['nombre'] as String?) ?? '',
        descripcion: (m['descripcion'] as String?) ?? '',
        radio: (m['radio'] as num?)?.toDouble() ?? 38,
        metrosPorUnidad: _positivo(m['m_u']) ?? kMetrosPorUnidadCanva,
        distanciaPegadas: _positivo(m['pegadas_u']),
        hojas: [
          for (final h in (m['hojas'] as List? ?? const []))
            HojaPlano.fromJson(Map<String, dynamic>.from(h as Map)),
        ],
        mesas: [
          for (final x in (m['mesas'] as List? ?? const []))
            MesaPlano.fromJson(Map<String, dynamic>.from(x as Map)),
        ],
        sectores: [
          for (final s in (m['sectores'] as List? ?? const []))
            SectorPlano.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        ingreso: m['ingreso'] == null
            ? null
            : PuntoPlano.fromJson(Map<String, dynamic>.from(m['ingreso'] as Map)),
      );
}
