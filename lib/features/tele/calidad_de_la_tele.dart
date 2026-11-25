import 'package:shared_preferences/shared_preferences.dart';

import 'fluidez.dart';

/// De cuánto se calcula el fondo animado en la tele (25-nov-2026). Lo demás
/// (las letras, el salón, el camino y la flecha) va siempre entero: esto toca
/// **solo el fondo**, que es bruma y luz.
enum FondoDeLaTele {
  /// En una imagen de la mitad de ancho y de alto: 4 veces menos trabajo, y
  /// no se nota. Así arranca toda tele.
  mitad(0.5),

  /// Un tercio: 9 veces menos.
  tercio(0.34),

  /// Quieto: se dibuja una vez.
  quieto(0.34);

  const FondoDeLaTele(this.escala);

  /// De cuánto se calcula ([EscenaTotem.escalaDelFondo]).
  final double escala;

  String get nombre => switch (this) {
        mitad => 'fondo a la mitad',
        tercio => 'fondo a un tercio',
        quieto => 'fondo quieto',
      };

  /// El escalón que sigue, o null si ya está quieto.
  FondoDeLaTele? get siguiente =>
      this == quieto ? null : FondoDeLaTele.values[index + 1];
}

/// **La tele se ajusta sola, callada**: si no llega a verse suave, baja un
/// escalón el fondo ([FondoDeLaTele]) y lo recuerda. Nunca dice nada en la
/// pantalla (pedido del usuario, 25-nov: en la noche no se ve ningún número).
class AjusteDeLaTele {
  AjusteDeLaTele([this.fondo = FondoDeLaTele.mitad]);

  FondoDeLaTele fondo;
  int _malas = 0;

  /// Recién bajó: lo de antes de bajar, para ver si ayudó.
  FondoDeLaTele? _probandoDesde;
  double? _antesDeBajar;

  /// Bajar no ayudó (lo que frena es otra cosa): no se prueba más. Se vio en
  /// el emulador: con el salón a pantalla completa el fondo ya está quieto, y
  /// bajarlo dejaba la tele con el fondo quieto de balde.
  bool _noAyuda = false;

  /// Lo que tiene que mejorar bajar un escalón para quedarse.
  static const mejoraQueAlcanza = 1.1;

  /// Anda suave si saca esta parte de las imágenes de la pantalla.
  static const suave = 0.83;

  /// Cuántas medidas malas seguidas antes de bajar: una o dos pueden ser un
  /// tirón (la primera llegada, que prepara sus fotos).
  static const malasParaBajar = 3;

  /// Con menos imágenes que esto, la medida no dice nada.
  static const imagenesQueAlcanzan = 60;

  /// Es la placa la que no llega: tarda en dibujar casi todo el tiempo de una
  /// imagen. Si no (en el emulador se vio: dibujaba en 11 ms y salían 50 por
  /// segundo), bajar el fondo no ayuda y lo dejaría quieto de balde.
  static bool esLaPlaca(MedidaDeFluidez m, double hz) => m.msDibujo > 1000 / hz * 0.85;

  /// Mira [m], con la pantalla de [hz] imágenes por segundo. Si hay que
  /// bajar, baja [fondo] y devuelve true.
  bool mirar(MedidaDeFluidez? m, {required double hz}) {
    if (m == null || m.imagenes < imagenesQueAlcanzan) return false;
    // Recién bajó: si no mejoró, vuelve a como estaba y no prueba más.
    final desde = _probandoDesde;
    if (desde != null) {
      _probandoDesde = null;
      if (m.porSegundo < _antesDeBajar! * mejoraQueAlcanza &&
          m.porSegundo < hz * suave) {
        fondo = desde;
        _noAyuda = true;
        return true;
      }
    }
    if (_noAyuda) return false;
    if (m.porSegundo >= hz * suave || !esLaPlaca(m, hz)) {
      _malas = 0;
      return false;
    }
    if (++_malas < malasParaBajar) return false;
    _malas = 0;
    final otro = fondo.siguiente;
    if (otro == null) return false;
    _probandoDesde = fondo;
    _antesDeBajar = m.porSegundo;
    fondo = otro;
    return true;
  }

  /// Dónde se recuerda, en la tele.
  static const clave = 'calidad_tele_v1';

  static Future<FondoDeLaTele> leer() async {
    try {
      final p = await SharedPreferences.getInstance();
      final n = p.getString(clave);
      return FondoDeLaTele.values.firstWhere(
        (f) => f.name == n,
        orElse: () => FondoDeLaTele.mitad,
      );
    } catch (_) {
      return FondoDeLaTele.mitad;
    }
  }

  static Future<void> guardar(FondoDeLaTele f) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(clave, f.name);
    } catch (_) {
      // Sin guardar, la próxima vez vuelve a medir: no se pierde nada.
    }
  }
}
