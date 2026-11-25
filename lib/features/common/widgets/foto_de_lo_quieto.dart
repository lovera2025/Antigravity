import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// **Lo quieto, como foto** (la tele es el tótem, 25-nov-2026).
///
/// En Android, Flutter dibuja con Impeller, que rehace la pantalla entera en
/// cada imagen sin guardar nada de la anterior. El tótem pide 60 imágenes por
/// segundo, así que el brillo de las letras (sombras borrosas) y el salón se
/// volvían a calcular 60 veces por segundo aunque estuvieran quietos, y la
/// placa de video chica de una tele no llegaba.
///
/// Esto dibuja a su hijo **una vez** en una imagen, a la resolución de la
/// pantalla, y después pinta esa imagen, que es lo más barato que hay. Se ve
/// igual: es el mismo dibujo.
///
/// - **Se da cuenta sola de cuándo cambió lo de adentro** (algo de adentro pide
///   dibujarse de nuevo, o cambia de tamaño): saca otra foto. No hace falta
///   decirle nada.
/// - **Si lo de adentro cambia en cada imagen** (una animación), se dibuja en
///   vivo hasta que se queda quieto, y ahí saca la foto. Así nunca cuesta más
///   que sin foto.
/// - [huella]: un cambio que se sabe que va y viene (la letra floja de Neón,
///   prendida o apagada). Guarda una foto por huella y cambia entre ellas sin
///   volver a dibujar.
/// - [margen]: lo que se ve afuera de su lugar (el brillo de unas letras).
///
/// Adentro no puede haber un `RepaintBoundary`: lo que cambia ahí adentro no le
/// avisa, y la foto quedaría vieja.
class FotoDeLoQuieto extends SingleChildRenderObjectWidget {
  const FotoDeLoQuieto({
    super.key,
    this.huella,
    this.margen = 0,
    this.activa = true,
    super.child,
  });

  final Object? huella;
  final double margen;

  /// False: se dibuja en vivo, sin foto (lo de adentro está por moverse, o
  /// tiene algo que cambia por su cuenta). Sirve para no cambiar el árbol: el
  /// salón de la tele va en foto mientras está apagado detrás del nombre, y en
  /// vivo cuando se enciende la mesa y se dibuja el camino.
  final bool activa;

  /// Cuántas fotos se sacaron, de todas. Solo los tests: para comprobar que no
  /// se saca una por imagen.
  @visibleForTesting
  static int fotosSacadas = 0;

  /// Cuántas veces se dibujó en vivo porque lo de adentro cambió, de todas.
  /// Solo los tests: lo quieto no tiene que pasar por acá en cada imagen (se
  /// escapó una vez: el plano se volvía a acomodar en cada imagen y su foto
  /// no servía nunca).
  @visibleForTesting
  static int dibujosEnVivo = 0;

  @override
  RenderFotoDeLoQuieto createRenderObject(BuildContext context) =>
      RenderFotoDeLoQuieto(
        huella: huella,
        margen: margen,
        pixeles: View.maybeOf(context)?.devicePixelRatio ?? 1,
      )..activa = activa;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFotoDeLoQuieto renderObject,
  ) {
    renderObject
      ..huella = huella
      ..margen = margen
      ..pixeles = View.maybeOf(context)?.devicePixelRatio ?? 1
      ..activa = activa;
  }
}

/// Una foto sacada: la imagen y con cuántos píxeles por punto.
class _Foto {
  _Foto(this.imagen, this.porPunto, this.rect, this.fase);
  final ui.Image imagen;
  final double porPunto;

  /// Lo que abarca, en el lugar del hijo (con el margen), corrido para que
  /// cada píxel de la foto caiga justo en uno de la pantalla.
  final Rect rect;

  /// Cuánto de un píxel de la pantalla caía el borde cuando se sacó.
  final Offset fase;

  void soltar() => imagen.dispose();
}

/// Lo que dibuja [FotoDeLoQuieto]. [NombreQueSePrende] lo usa para tomar las
/// letras de la foto.
class RenderFotoDeLoQuieto extends RenderProxyBox {
  RenderFotoDeLoQuieto({
    Object? huella,
    double margen = 0,
    double pixeles = 1,
  })  : _huella = huella,
        _margen = margen,
        _pixeles = pixeles;

  Object? _huella;
  set huella(Object? v) {
    if (v == _huella) return;
    _huella = v;
    // El cambio de adentro que llega con esto ya está explicado.
    _cambioLaHuella = true;
    _repintarPorMi();
  }

  double _margen;
  set margen(double v) {
    if (v == _margen) return;
    _margen = v;
    _olvidarTodo();
    _repintarPorMi();
  }

  double _pixeles;
  set pixeles(double v) {
    if (v == _pixeles) return;
    _pixeles = v;
    _olvidarTodo();
    _repintarPorMi();
  }

  bool _activa = true;
  set activa(bool v) {
    if (v == _activa) return;
    _activa = v;
    // Lo de adentro pudo cambiar mientras iba en vivo: foto nueva.
    _olvidarTodo();
    _repintarPorMi();
  }

  /// Las fotos, una por huella. Dos alcanzan (prendida y apagada).
  final _fotos = <Object?, _Foto>{};

  bool _cambioAdentro = true;
  bool _cambioLaHuella = false;
  bool _porMi = false;

  /// No se puede sacar foto (hay algo adentro que no se deja, como una vista
  /// de la plataforma): siempre en vivo.
  bool _nunca = false;

  /// Cuándo cambió lo de adentro la última vez, y cuántas veces seguidas.
  Duration? _ultimoCambio;
  int _seguidos = 0;

  /// La escala de la última vez que se dibujó: si se queda quieta y es mucho
  /// más chica que la de la foto, se saca otra (más nítida al achicarse).
  double? _ultimaEscala;

  /// Y la fase: si quedó quieto en otro pedazo de píxel que la foto, se saca
  /// otra (si no, los bordes se verían apenas corridos).
  Offset? _ultimaFase;

  Timer? _esperarQuieto;

  /// Lo que se espera sin cambios para sacar la foto después de una animación.
  static const quietoDespuesDe = Duration(milliseconds: 250);

  /// Dos cambios así de juntos: es una animación, va en vivo.
  static const _seguidosSi = Duration(milliseconds: 120);

  void _repintarPorMi() {
    _porMi = true;
    try {
      markNeedsPaint();
    } finally {
      _porMi = false;
    }
  }

  @override
  void markNeedsPaint() {
    // Si no lo pido yo, lo pide algo de adentro (o un cambio de tamaño): lo de
    // adentro ya no es lo de la foto.
    if (!_porMi) _cambioAdentro = true;
    super.markNeedsPaint();
  }

  void _olvidarTodo() {
    for (final f in _fotos.values) {
      f.soltar();
    }
    _fotos.clear();
  }

  @override
  void detach() {
    _esperarQuieto?.cancel();
    _esperarQuieto = null;
    _olvidarTodo();
    _cambioAdentro = true;
    super.detach();
  }

  @override
  void dispose() {
    _esperarQuieto?.cancel();
    _olvidarTodo();
    super.dispose();
  }

  /// La hora de la imagen que se está dibujando (en los tests, la de `pump`).
  Duration _ahora() => SchedulerBinding.instance.currentFrameTimeStamp;

  /// Cuántos píxeles de la pantalla mide un punto acá: los de la pantalla por
  /// lo que agranden o achiquen los de arriba (el nombre en grande que se
  /// achica hacia el cuadro).
  double _escalaEnPantalla(Matrix4 transformacion) {
    final m = transformacion.storage;
    // El más grande de los dos lados: una tarjeta que se da vuelta (Cristal)
    // se achica de un lado solo, y la foto tiene que servir de frente.
    final sx = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    final sy = math.sqrt(m[4] * m[4] + m[5] * m[5]);
    final s = math.max(sx, sy);
    return _pixeles * (s.isFinite && s > 0 ? s : 1.0);
  }

  /// Si va en vivo ahora (lo de adentro se está moviendo).
  bool get enVivo => _seguidos >= 2;

  void _anotarCambio(Duration ahora) {
    final antes = _ultimoCambio;
    _seguidos = antes != null && ahora - antes < _seguidosSi ? _seguidos + 1 : 1;
    _ultimoCambio = ahora;
    if (_seguidos >= 2) {
      // Cuando deje de moverse, la foto.
      _esperarQuieto?.cancel();
      _esperarQuieto = Timer(quietoDespuesDe, () {
        _esperarQuieto = null;
        _seguidos = 0;
        if (attached) _repintarPorMi();
      });
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty) return;
    if (_nunca || !_activa) {
      _cambioAdentro = false;
      super.paint(context, offset);
      return;
    }
    if (_cambioAdentro) {
      _cambioAdentro = false;
      if (!_cambioLaHuella) {
        _olvidarTodo();
        _anotarCambio(_ahora());
      }
    }
    _cambioLaHuella = false;
    if (enVivo) {
      FotoDeLoQuieto.dibujosEnVivo++;
      super.paint(context, offset);
      return;
    }
    final m = getTransformTo(null);
    final escala = _escalaEnPantalla(m);
    final fase = _faseEnPantalla(m);
    final quieta = _ultimaEscala != null &&
        (escala - _ultimaEscala!).abs() < 1e-3 &&
        (fase - _ultimaFase!).distance < 1e-3;
    _ultimaEscala = escala;
    _ultimaFase = fase;
    var foto = _fotos[_huella];
    if (foto != null &&
        (escala > foto.porPunto * 1.05 ||
            (quieta &&
                (escala < foto.porPunto * 0.7 ||
                    (fase - foto.fase).distance > 0.05)))) {
      _fotos.remove(_huella)?.soltar();
      foto = null;
    }
    foto ??= _sacar(escala, fase);
    if (foto == null) {
      super.paint(context, offset);
      return;
    }
    dibujarFoto(context.canvas, offset, foto.imagen, foto.rect, foto.porPunto);
  }

  /// En qué pedazo de un píxel de la pantalla cae el borde de la foto.
  Offset _faseEnPantalla(Matrix4 m) {
    final p = MatrixUtils.transformPoint(m, Offset(-_margen, -_margen)) * _pixeles;
    if (!p.dx.isFinite || !p.dy.isFinite) return Offset.zero;
    return Offset(p.dx - p.dx.floorToDouble(), p.dy - p.dy.floorToDouble());
  }

  _Foto? _sacar(double escala, Offset fase) {
    // Corrido lo que le falta al borde para caer justo en un píxel: así cada
    // píxel de la foto es uno de la pantalla, y los bordes quedan como en
    // vivo.
    final rect = (Offset.zero & size)
        .inflate(_margen)
        .shift(Offset(-fase.dx / escala, -fase.dy / escala));
    // Que no pase de lo que aguanta una placa chica.
    final porPunto = math.min(escala, 4096 / math.max(rect.width, rect.height));
    final capa = OffsetLayer();
    final ctx = PaintingContext(capa, rect);
    super.paint(ctx, Offset.zero);
    // ignore: invalid_use_of_protected_member
    ctx.stopRecordingIfNeeded();
    if (!capa.supportsRasterization()) {
      capa.dispose();
      _nunca = true;
      return null;
    }
    final imagen = capa.toImageSync(rect, pixelRatio: porPunto);
    capa.dispose();
    FotoDeLoQuieto.fotosSacadas++;
    // Dos huellas como mucho: la de antes y la de ahora.
    if (_fotos.length >= 2) {
      final vieja = _fotos.keys.firstWhere((k) => k != _huella, orElse: () => _huella);
      _fotos.remove(vieja)?.soltar();
    }
    return _fotos[_huella] = _Foto(imagen, porPunto, rect, fase);
  }

  /// Pinta la foto en su lugar. [NombreQueSePrende] la pinta de a letras.
  @protected
  void dibujarFoto(
    Canvas canvas,
    Offset offset,
    ui.Image imagen,
    Rect rect,
    double porPunto,
  ) {
    canvas.drawImageRect(
      imagen,
      Rect.fromLTWH(0, 0, rect.width * porPunto, rect.height * porPunto),
      rect.shift(offset),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
}

/// Un nombre que **se enciende letra por letra, tomado de su foto**: el hijo es
/// el nombre entero, con su brillo, y cada letra se pinta de la foto con su
/// opacidad, como `letraPorLetra` (cada una aparece en tres tiempos, una
/// detrás de la otra). Ninguna sombra se vuelve a calcular mientras se prende.
class NombreQueSePrende extends SingleChildRenderObjectWidget {
  const NombreQueSePrende({
    super.key,
    required this.progreso,
    this.margen = 0,
    required super.child,
  });

  /// De 0 (no se ve nada) a 1 (entero).
  final double progreso;
  final double margen;

  /// Cuánto se ve la letra [i] de [n], con [progreso]: lo mismo que
  /// `letraPorLetra`.
  static double opacidadDeLetra(double progreso, int i, int n) =>
      ((progreso * (n + 3) - i) / 3).clamp(0.0, 1.0);

  @override
  RenderNombreQueSePrende createRenderObject(BuildContext context) =>
      RenderNombreQueSePrende(
        progreso: progreso,
        margen: margen,
        pixeles: View.maybeOf(context)?.devicePixelRatio ?? 1,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderNombreQueSePrende renderObject,
  ) {
    renderObject
      ..progreso = progreso
      ..margen = margen
      ..pixeles = View.maybeOf(context)?.devicePixelRatio ?? 1;
  }
}

class RenderNombreQueSePrende extends RenderFotoDeLoQuieto {
  RenderNombreQueSePrende({
    required double progreso,
    super.margen,
    super.pixeles,
  }) : _progreso = progreso;

  double _progreso;
  set progreso(double v) {
    if (v == _progreso) return;
    _progreso = v;
    _repintarPorMi();
  }

  /// Las franjas de cada letra, en el lugar del hijo (se arman una vez por
  /// foto).
  List<Rect>? _franjas;
  Rect? _franjasDe;

  @override
  void markNeedsPaint() {
    if (!_porMi) _franjas = null;
    super.markNeedsPaint();
  }

  @override
  void dibujarFoto(
    Canvas canvas,
    Offset offset,
    ui.Image imagen,
    Rect rect,
    double porPunto,
  ) {
    if (_progreso >= 1) {
      super.dibujarFoto(canvas, offset, imagen, rect, porPunto);
      return;
    }
    if (_progreso <= 0) return;
    if (_franjas == null || _franjasDe != rect) {
      _franjas = _armarFranjas(rect);
      _franjasDe = rect;
    }
    final franjas = _franjas!;
    final n = franjas.length;
    if (n == 0) {
      super.dibujarFoto(canvas, offset, imagen, rect, porPunto);
      return;
    }
    for (var i = 0; i < n; i++) {
      final a = NombreQueSePrende.opacidadDeLetra(_progreso, i, n);
      if (a <= 0) continue;
      final f = franjas[i];
      final desde = f.shift(-rect.topLeft);
      canvas.drawImageRect(
        imagen,
        Rect.fromLTRB(
          desde.left * porPunto,
          desde.top * porPunto,
          desde.right * porPunto,
          desde.bottom * porPunto,
        ),
        f.shift(offset),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(0, 0, 0, a),
      );
    }
  }

  /// Una franja por letra, sin huecos ni encimadas: de la mitad entre una letra
  /// y la anterior a la mitad con la siguiente, y de arriba abajo de su
  /// renglón (la primera y la última llegan al borde, con el brillo).
  List<Rect> _armarFranjas(Rect todo) {
    RenderParagraph? texto;
    void buscar(RenderObject o) {
      if (texto != null) return;
      if (o is RenderParagraph) {
        texto = o;
        return;
      }
      o.visitChildren(buscar);
    }

    final hijo = child;
    if (hijo == null) return const [];
    buscar(hijo);
    final p = texto;
    if (p == null) return const [];
    final m = p.getTransformTo(this);
    final cadena = p.text.toPlainText(includeSemanticsLabels: false);
    final cajas = <Rect>[];
    var desde = 0;
    for (final letra in cadena.characters) {
      final hasta = desde + letra.length;
      final bs = p.getBoxesForSelection(
        TextSelection(baseOffset: desde, extentOffset: hasta),
      );
      Rect? caja;
      for (final b in bs) {
        final r = MatrixUtils.transformRect(m, b.toRect());
        caja = caja == null ? r : caja.expandToInclude(r);
      }
      // Una letra sin caja (un salto de renglón): pegada a la anterior.
      cajas.add(caja ??
          (cajas.isEmpty
              ? Rect.fromLTWH(todo.left, todo.top, 0, 0)
              : Rect.fromLTWH(cajas.last.right, cajas.last.top, 0, cajas.last.height)));
      desde = hasta;
    }
    // Los renglones: las cajas con la misma altura.
    final renglon = <int>[];
    var r = 0;
    for (var i = 0; i < cajas.length; i++) {
      if (i > 0 && cajas[i].top > cajas[i - 1].bottom - 1) r++;
      renglon.add(r);
    }
    final ultimo = r;
    // Arriba y abajo de cada renglón.
    final arriba = <int, double>{}, abajo = <int, double>{};
    for (var i = 0; i < cajas.length; i++) {
      final k = renglon[i];
      arriba[k] = math.min(arriba[k] ?? double.infinity, cajas[i].top);
      abajo[k] = math.max(abajo[k] ?? -double.infinity, cajas[i].bottom);
    }
    double techo(int k) => k == 0 ? todo.top : (abajo[k - 1]! + arriba[k]!) / 2;
    double piso(int k) => k == ultimo ? todo.bottom : (abajo[k]! + arriba[k + 1]!) / 2;
    return [
      for (var i = 0; i < cajas.length; i++)
        Rect.fromLTRB(
          i == 0 || renglon[i - 1] != renglon[i]
              ? todo.left
              : (cajas[i - 1].right + cajas[i].left) / 2,
          techo(renglon[i]),
          i == cajas.length - 1 || renglon[i + 1] != renglon[i]
              ? todo.right
              : (cajas[i].right + cajas[i + 1].left) / 2,
          piso(renglon[i]),
        ),
    ];
  }
}

/// **El mismo hijo mientras no cambie [clave]**: lo que va en foto no se
/// vuelve a armar en cada imagen. Hace falta porque el tótem arma la escena
/// entera en cada imagen, y algo que se vuelve a acomodar (un `LayoutBuilder`,
/// como el del plano) avisa que cambió aunque no haya cambiado nada: la foto
/// se tiraba y el salón se dibujaba entero en cada imagen. Con el mismo hijo,
/// Flutter ni lo mira. [clave] tiene que llevar todo lo que cambia lo que se
/// ve.
class MismoHijo extends StatefulWidget {
  const MismoHijo({super.key, required this.clave, required this.child});

  final Object? clave;
  final Widget child;

  @override
  State<MismoHijo> createState() => _MismoHijoState();
}

class _MismoHijoState extends State<MismoHijo> {
  late Object? _clave = widget.clave;
  late Widget _hijo = widget.child;

  @override
  Widget build(BuildContext context) {
    if (widget.clave != _clave) {
      _clave = widget.clave;
      _hijo = widget.child;
    }
    return _hijo;
  }
}

/// Un círculo que se dibuja de a poco, **descubierto como un barrido** desde
/// arriba en el sentido del reloj: el hijo es el círculo entero (en la tele, en
/// foto) y [progreso] dice cuánto se ve, de 0 a 1.
class BarridoDeCirculo extends StatelessWidget {
  const BarridoDeCirculo({
    super.key,
    required this.progreso,
    required this.child,
  });

  final double progreso;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipPath(
        // Siempre el mismo árbol: así la foto de adentro no se vuelve a sacar
        // al terminar el barrido.
        clipBehavior: progreso >= 1 ? Clip.none : Clip.antiAlias,
        clipper: _Barrido(progreso.clamp(0.0, 1.0)),
        child: child,
      );
}

class _Barrido extends CustomClipper<Path> {
  _Barrido(this.progreso);
  final double progreso;

  @override
  Path getClip(Size size) {
    final c = size.center(Offset.zero);
    // Grande de sobra: el brillo del círculo se sale de su lugar.
    final r = size.longestSide * 1.5;
    if (progreso <= 0) return Path();
    return Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
          2 * math.pi * progreso, false)
      ..close();
  }

  @override
  bool shouldReclip(_Barrido old) => old.progreso != progreso;
}

/// Lo que se ve afuera de un texto por su brillo: el desenfoque más grande, con
/// lugar de sobra.
double margenDelBrillo(TextStyle? estilo) {
  var m = 0.0;
  for (final s in estilo?.shadows ?? const <Shadow>[]) {
    m = math.max(m, s.blurRadius * 2 + s.offset.distance + 2);
  }
  return m;
}
