import 'dart:math' as math;

/// Un número finito entre [min] y [max], o null si vino otra cosa. Un `as
/// double` tiraría con un texto, y una medida mal escrita no puede dejar el
/// plano sin abrir.
double? _entre(Object? v, double min, double max) =>
    v is num && v.isFinite && v >= min && v <= max ? v.toDouble() : null;

/// El hormigón donde se arman las mesas: un trapecio simétrico que arranca
/// contra el escenario ([frenteM]) y termina en el fondo ([fondoM]).
class PlayonReal {
  final double frenteM;
  final double fondoM;
  final double profundidadM;

  /// Las medidas no salieron de una cinta: la pantalla lo dice.
  final bool aproximado;

  const PlayonReal({
    required this.frenteM,
    required this.fondoM,
    required this.profundidadM,
    this.aproximado = false,
  });

  /// El playón del Predio Costa Surubí (Goya), frente al Escenario Mayor Juan
  /// Melero, medido el 1-oct-2026 sobre la foto satelital (±10 %). La nota de
  /// goyasurubi.com habla de 900 m², pero es solo la primera etapa. Falta
  /// medirlo con cinta: por eso va como aproximado.
  static const costaSurubi = PlayonReal(
    frenteM: 30,
    fondoM: 46,
    profundidadM: 39,
    aproximado: true,
  );

  static const double ladoMinimoM = 5;
  static const double ladoMaximoM = 300;

  double get superficieM2 => (frenteM + fondoM) / 2 * profundidadM;

  /// El ancho del hormigón a [profundidad] metros del escenario.
  double anchoA(double profundidad) =>
      frenteM +
      (fondoM - frenteM) * (profundidad / profundidadM).clamp(0.0, 1.0);

  /// Cuánto se abre cada costado por metro de profundidad (negativo si se
  /// cierra).
  double get aperturaPorMetro => (fondoM - frenteM) / (2 * profundidadM);

  /// Lo que mide cada costado, que va inclinado. Es lo que da la cinta: con
  /// ella se miden los cuatro lados, no la profundidad.
  double get costadoM {
    final medio = (fondoM - frenteM) / 2;
    return math.sqrt(profundidadM * profundidadM + medio * medio);
  }

  /// El playón a partir de lo que se mide con cinta: el frente, el fondo y un
  /// costado. Null si con esas medidas no cierra un trapecio.
  static PlayonReal? conCostado({
    required double frenteM,
    required double fondoM,
    required double costadoM,
    bool aproximado = false,
  }) {
    final medio = (fondoM - frenteM) / 2;
    final resto = costadoM * costadoM - medio * medio;
    if (frenteM <= 0 || fondoM <= 0 || resto <= 0) return null;
    return PlayonReal(
      frenteM: frenteM,
      fondoM: fondoM,
      profundidadM: math.sqrt(resto),
      aproximado: aproximado,
    );
  }

  PlayonReal copyWith({
    double? frenteM,
    double? fondoM,
    double? profundidadM,
    bool? aproximado,
  }) =>
      PlayonReal(
        frenteM: frenteM ?? this.frenteM,
        fondoM: fondoM ?? this.fondoM,
        profundidadM: profundidadM ?? this.profundidadM,
        aproximado: aproximado ?? this.aproximado,
      );

  Map<String, dynamic> toMap() => {
        'frente': frenteM,
        'fondo': fondoM,
        'profundidad': profundidadM,
        if (aproximado) 'aprox': true,
      };

  /// Null si falta un lado o alguno no tiene sentido.
  static PlayonReal? fromMap(Object? v) {
    if (v is! Map) return null;
    final frente = _entre(v['frente'], ladoMinimoM, ladoMaximoM);
    final fondo = _entre(v['fondo'], ladoMinimoM, ladoMaximoM);
    final prof = _entre(v['profundidad'], ladoMinimoM, ladoMaximoM);
    if (frente == null || fondo == null || prof == null) return null;
    return PlayonReal(
      frenteM: frente,
      fondoM: fondo,
      profundidadM: prof,
      aproximado: v['aprox'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlayonReal &&
      other.frenteM == frenteM &&
      other.fondoM == fondoM &&
      other.profundidadM == profundidadM &&
      other.aproximado == aproximado;

  @override
  int get hashCode => Object.hash(frenteM, fondoM, profundidadM, aproximado);
}

/// Las medidas del plano de una fiesta: cuánto lugar pide cada mesa y cómo es
/// el playón. Viajan dentro de `config`, en la clave `medidas`.
class MedidasPlano {
  /// El círculo que ocupa una mesa con sus 8 sillas, de centro a centro.
  final double lugarMesaM;

  /// Cuánto más pide por cada silla extra (hasta [maxSillasExtra]).
  final double extraPorSillaM;
  final PlayonReal playon;

  const MedidasPlano({
    this.lugarMesaM = lugarPorDefectoM,
    this.extraPorSillaM = extraPorSillaPorDefectoM,
    this.playon = PlayonReal.costaSurubi,
  });

  static const double lugarPorDefectoM = 2.0;
  static const double extraPorSillaPorDefectoM = 0.15;
  static const double lugarMinimoM = 1.5;
  static const double lugarMaximoM = 5.0;

  /// Una mesa lleva hasta 2 sillas extra (regla del salón).
  static const int maxSillasExtra = 2;

  /// El círculo que pide una mesa con [sillasExtra] sillas de más: 2 m con
  /// ocho sillas, 2,15 m con nueve y 2,3 m con diez.
  double lugarM(int sillasExtra) =>
      lugarMesaM + extraPorSillaM * sillasExtra.clamp(0, maxSillasExtra);

  MedidasPlano copyWith({
    double? lugarMesaM,
    double? extraPorSillaM,
    PlayonReal? playon,
  }) =>
      MedidasPlano(
        lugarMesaM: lugarMesaM ?? this.lugarMesaM,
        extraPorSillaM: extraPorSillaM ?? this.extraPorSillaM,
        playon: playon ?? this.playon,
      );

  Map<String, dynamic> toMap() => {
        'lugar': lugarMesaM,
        'extra_silla': extraPorSillaM,
        'playon': playon.toMap(),
      };

  /// Lo que no se pueda leer queda en su valor de fábrica.
  static MedidasPlano fromMap(Object? v) {
    if (v is! Map) return const MedidasPlano();
    return MedidasPlano(
      lugarMesaM:
          _entre(v['lugar'], lugarMinimoM, lugarMaximoM) ?? lugarPorDefectoM,
      extraPorSillaM:
          _entre(v['extra_silla'], 0, 1) ?? extraPorSillaPorDefectoM,
      playon: PlayonReal.fromMap(v['playon']) ?? PlayonReal.costaSurubi,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MedidasPlano &&
      other.lugarMesaM == lugarMesaM &&
      other.extraPorSillaM == extraPorSillaM &&
      other.playon == playon;

  @override
  int get hashCode => Object.hash(lugarMesaM, extraPorSillaM, playon);
}
