import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'tu_fondo.dart';

/// El shader de "Tu fondo" (`pubspec.yaml`, `shaders:`).
const shaderTuFondo = 'shaders/totem_tu_fondo.frag';

/// La imagen de "Tu fondo", lista para dibujar: decodificada hasta 1.920 px de
/// lado, y su copia chica y borrosa para los costados de una tele horizontal.
/// Avisa cuando está, o si no se pudo (la escena pasa a la apariencia del
/// tipo).
///
/// Las suelta al cambiar de imagen y en [dispose]: son las imágenes más
/// grandes del tótem (una story de 1080 × 1920 son unos 8 MB en la placa).
class CargaDelFondo extends ChangeNotifier {
  ImageProvider? _de;
  ImageStream? _stream;
  ImageStreamListener? _oyente;
  ImageInfo? _info;
  ui.Image? _chica;
  bool _fallo = false;
  bool _soltada = false;

  /// El lado más largo con que se decodifica.
  static const ladoMaximo = 1920;

  /// El ancho de la copia chica: estirada, ya queda borrosa.
  static const anchoChica = 48;

  ui.Image? get imagen => _info?.image;
  ui.Image? get chica => _chica;

  /// La imagen no está en la PC ni baja.
  bool get fallo => _fallo;

  ImageProvider? get de => _de;

  /// Empieza a cargar [proveedor]. El mismo de antes no hace nada; null
  /// suelta lo que había.
  void cargar(ImageProvider? proveedor) {
    if (_soltada || proveedor == _de) return;
    _soltar();
    _de = proveedor;
    _fallo = false;
    if (proveedor == null) {
      notifyListeners();
      return;
    }
    final oyente = ImageStreamListener(
      (info, _) {
        if (_soltada) {
          info.dispose();
          return;
        }
        _info?.dispose();
        _chica?.dispose();
        _info = info;
        _chica = achicar(info.image);
        _fallo = false;
        notifyListeners();
      },
      onError: (e, _) {
        debugPrint('El fondo del tótem no se pudo cargar; va la apariencia '
            'del tipo de evento: $e');
        _fallo = true;
        if (!_soltada) notifyListeners();
      },
    );
    _oyente = oyente;
    _stream = ResizeImage(
      proveedor,
      width: ladoMaximo,
      height: ladoMaximo,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    ).resolve(ImageConfiguration.empty)
      ..addListener(oyente);
  }

  /// La copia chica de [imagen], con un poco de desenfoque: estirada a toda la
  /// pantalla queda como un fondo de luz, sin costo en cada cuadro.
  static ui.Image achicar(ui.Image imagen) {
    final ancho = anchoChica;
    final alto = (imagen.height * ancho / imagen.width).round().clamp(1, 400);
    final grabador = ui.PictureRecorder();
    ui.Canvas(grabador).drawImageRect(
      imagen,
      Rect.fromLTWH(0, 0, imagen.width.toDouble(), imagen.height.toDouble()),
      Rect.fromLTWH(0, 0, ancho.toDouble(), alto.toDouble()),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 2,
          sigmaY: 2,
          tileMode: TileMode.clamp,
        ),
    );
    final cuadro = grabador.endRecording();
    final chica = cuadro.toImageSync(ancho, alto);
    cuadro.dispose();
    return chica;
  }

  void _soltar() {
    final oyente = _oyente;
    if (oyente != null) _stream?.removeListener(oyente);
    _stream = null;
    _oyente = null;
    _info?.dispose();
    _info = null;
    _chica?.dispose();
    _chica = null;
  }

  @override
  void dispose() {
    _soltada = true;
    _soltar();
    super.dispose();
  }
}

/// El fondo de "Tu fondo": la imagen con su animación y su glitch (el shader
/// `totem_tu_fondo.frag`) y el oscurecido.
///
/// **Nunca una pantalla rota:** si el shader no carga en esta PC (o falla con
/// la imagen, como puede pasar en un navegador), va la imagen quieta con el
/// mismo oscurecido. "Quieta" sin glitch también va así: no hace falta el
/// shader. Sin imagen, negro: quien la usa decide (`EscenaTotem` cae a la
/// apariencia del tipo si la imagen no está).
class FondoPropio extends StatefulWidget {
  final ui.Image? imagen;
  final ui.Image? chica;
  final RecetaDibujada receta;

  /// Como en `FondoTotem`: 1 en la espera, 0,55 durante una llegada.
  final double atenuado;

  /// El fogonazo de la llegada, de 0 a 1.
  final double fogonazo;

  /// Un instante fijo, en segundos: sin animación (tests y muestras).
  final double? tiempoFijo;

  const FondoPropio({
    super.key,
    required this.imagen,
    required this.chica,
    required this.receta,
    this.atenuado = 1,
    this.fogonazo = 0,
    this.tiempoFijo,
  });

  static Future<ui.FragmentProgram?>? _programa;
  static ui.FragmentProgram? _listo;
  static bool _roto = false;

  /// Cómo se carga el shader. Solo los tests lo cambian.
  @visibleForTesting
  static Future<ui.FragmentProgram> Function(String asset) cargar =
      ui.FragmentProgram.fromAsset;

  /// Carga el shader si no está (al abrir el tótem, para que la primera
  /// llegada no espere); null si no se pudo.
  static Future<ui.FragmentProgram?> programa() => _programa ??= () async {
        try {
          final p = await cargar(shaderTuFondo);
          _listo = p;
          return p;
        } catch (e) {
          debugPrint('El fondo "Tu fondo" no carga; va la imagen quieta: $e');
          _listo = null;
          return null;
        }
      }();

  static Future<void> precargar() => programa();

  /// Olvida lo cargado. Solo los tests.
  @visibleForTesting
  static void olvidar() {
    _programa = null;
    _listo = null;
    _roto = false;
    cargar = ui.FragmentProgram.fromAsset;
  }

  /// Si el shader está cargado y anda (false: imagen quieta).
  @visibleForTesting
  static bool get tieneShader => _listo != null && !_roto;

  /// Si [receta] necesita el shader: todo lo que se mueve, y el glitch.
  static bool necesitaShader(RecetaDibujada receta) =>
      receta.animacion != AnimacionFondo.quieta ||
      receta.tiene(EfectoFondo.glitch);

  /// Cubre la pantalla, salvo que la imagen tenga otra forma (una story en
  /// una tele horizontal, o al revés): entera al medio y alrededor la copia
  /// chica.
  static bool contener(Size pantalla, ui.Image imagen) {
    final aspP = pantalla.width / pantalla.height;
    final aspI = imagen.width / imagen.height;
    final r = aspI > aspP ? aspI / aspP : aspP / aspI;
    return r > 1.25;
  }

  @override
  State<FondoPropio> createState() => _FondoPropioState();
}

class _FondoPropioState extends State<FondoPropio>
    with SingleTickerProviderStateMixin {
  final _tiempo = ValueNotifier<double>(0);
  Ticker? _ticker;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _prepararShader();
    if (widget.tiempoFijo == null) {
      _ticker = createTicker((d) => _tiempo.value = d.inMicroseconds / 1e6)
        ..start();
    } else {
      _tiempo.value = widget.tiempoFijo!;
    }
  }

  @override
  void didUpdateWidget(covariant FondoPropio old) {
    super.didUpdateWidget(old);
    if (widget.tiempoFijo != null) _tiempo.value = widget.tiempoFijo!;
  }

  void _prepararShader() {
    final listo = FondoPropio._listo;
    if (listo != null) {
      _shader = listo.fragmentShader();
      return;
    }
    FondoPropio.programa().then((p) {
      if (!mounted || p == null) return;
      setState(() => _shader = p.fragmentShader());
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _shader?.dispose();
    _tiempo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imagen = widget.imagen;
    if (imagen == null) return const ColoredBox(color: Colors.black);
    final conShader = _shader != null &&
        !FondoPropio._roto &&
        FondoPropio.necesitaShader(widget.receta);
    return RepaintBoundary(
      child: CustomPaint(
        painter: conShader
            ? _PintorConShader(
                tiempo: _tiempo,
                shader: _shader!,
                imagen: imagen,
                chica: widget.chica ?? imagen,
                receta: widget.receta,
                atenuado: widget.atenuado,
                fogonazo: widget.fogonazo,
              )
            : PintorFondoQuieto(
                imagen: imagen,
                chica: widget.chica ?? imagen,
                oscurecer: widget.receta.oscurecer,
                brillo: widget.receta.colores.brillo,
                atenuado: widget.atenuado,
                fogonazo: widget.fogonazo,
              ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PintorConShader extends CustomPainter {
  final ValueListenable<double> tiempo;
  final ui.FragmentShader shader;
  final ui.Image imagen;
  final ui.Image chica;
  final RecetaDibujada receta;
  final double atenuado;
  final double fogonazo;

  _PintorConShader({
    required this.tiempo,
    required this.shader,
    required this.imagen,
    required this.chica,
    required this.receta,
    required this.atenuado,
    required this.fogonazo,
  }) : super(repaint: tiempo);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = receta;
    try {
      shader
        ..setImageSampler(0, imagen, filterQuality: FilterQuality.medium)
        ..setImageSampler(1, chica, filterQuality: FilterQuality.low);
    } catch (e) {
      // En un navegador puede no andar: de ahí en más, la imagen quieta.
      debugPrint('"Tu fondo" no puede leer la imagen en el shader; va quieta: $e');
      FondoPropio._roto = true;
      PintorFondoQuieto(
        imagen: imagen,
        chica: chica,
        oscurecer: r.oscurecer,
        brillo: r.colores.brillo,
        atenuado: atenuado,
        fogonazo: fogonazo,
      ).paint(canvas, size);
      return;
    }
    final foco = r.foco;
    final glitch = r.tiene(EfectoFondo.glitch) ? 0.3 + 0.7 * r.intensidadEfectos : 0.0;
    // El orden de los uniformes es el del .frag (ver su cabecera).
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, tiempo.value)
      ..setFloat(3, r.colores.brillo.r)
      ..setFloat(4, r.colores.brillo.g)
      ..setFloat(5, r.colores.brillo.b)
      ..setFloat(6, fogonazo)
      ..setFloat(7, atenuado)
      ..setFloat(8, imagen.width.toDouble())
      ..setFloat(9, imagen.height.toDouble())
      ..setFloat(10, r.animacion.index.toDouble())
      ..setFloat(11, r.intensidad)
      ..setFloat(12, r.oscurecer)
      ..setFloat(13, FondoPropio.contener(size, imagen) ? 1 : 0)
      ..setFloat(14, foco.dx)
      ..setFloat(15, foco.dy)
      ..setFloat(16, r.semilla.isEven ? 1 : -1)
      ..setFloat(17, glitch);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PintorConShader old) =>
      old.shader != shader ||
      old.imagen != imagen ||
      old.chica != chica ||
      old.receta.animacion != receta.animacion ||
      old.receta.intensidad != receta.intensidad ||
      old.receta.oscurecer != receta.oscurecer ||
      old.receta.foco != receta.foco ||
      old.receta.colores != receta.colores ||
      old.receta.efectos.length != receta.efectos.length ||
      old.receta.intensidadEfectos != receta.intensidadEfectos ||
      old.atenuado != atenuado ||
      old.fogonazo != fogonazo;
}

/// "Tu fondo" sin shader: la imagen quieta (cubriendo, o entera al medio con
/// la copia chica alrededor), el oscurecido, la atenuación y el fogonazo.
/// Es "Quieta", y el respaldo si el shader no anda: **tiene que dar lo mismo
/// que el shader sin animación**.
class PintorFondoQuieto extends CustomPainter {
  final ui.Image imagen;
  final ui.Image chica;

  /// De 0 a 0,8.
  final double oscurecer;
  final Color brillo;
  final double atenuado;
  final double fogonazo;

  PintorFondoQuieto({
    required this.imagen,
    required this.chica,
    required this.oscurecer,
    required this.brillo,
    this.atenuado = 1,
    this.fogonazo = 0,
  });

  /// El oscurecido de arriba a abajo, como en el shader: lo que se le saca a
  /// la luz, por la parte de [oscurecer].
  static const _paradas = [0.0, 0.4, 0.72, 1.0];
  static const _fuerzas = [0.85, 0.45, 0.6, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fuente = Rect.fromLTWH(
      0,
      0,
      imagen.width.toDouble(),
      imagen.height.toDouble(),
    );
    final cubre = _cubriendo(size, imagen);
    if (FondoPropio.contener(size, imagen)) {
      canvas.drawImageRect(
        chica,
        Rect.fromLTWH(0, 0, chica.width.toDouble(), chica.height.toDouble()),
        cubre,
        Paint()
          ..filterQuality = FilterQuality.low
          ..colorFilter = const ColorFilter.matrix([
            0.55, 0, 0, 0, 0, //
            0, 0.55, 0, 0, 0,
            0, 0, 0.55, 0, 0,
            0, 0, 0, 1, 0,
          ]),
      );
      final entera = _entera(size, imagen);
      canvas.saveLayer(entera, Paint());
      canvas.drawImageRect(
        imagen,
        fuente,
        entera,
        Paint()..filterQuality = FilterQuality.medium,
      );
      // Los bordes, fundidos en la copia chica (el 12 % de la imagen).
      final horizontal = entera.width < size.width;
      canvas.drawRect(
        entera,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
            end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
            colors: const [
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000),
            ],
            stops: const [0, 0.12, 0.88, 1],
          ).createShader(entera),
      );
      canvas.restore();
    } else {
      canvas.drawImageRect(
        imagen,
        fuente,
        cubre,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    if (oscurecer > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              for (final f in _fuerzas)
                Colors.black.withValues(alpha: (oscurecer * f).clamp(0.0, 1.0)),
            ],
            stops: _paradas,
          ).createShader(rect),
      );
    }
    if (atenuado < 1) {
      canvas.drawRect(
        rect,
        Paint()..color = Colors.black.withValues(alpha: (1 - atenuado).clamp(0.0, 1.0)),
      );
    }
    if (fogonazo > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = brillo.withValues(alpha: (0.25 * fogonazo).clamp(0.0, 1.0)),
      );
    }
  }

  /// La imagen agrandada hasta cubrir [pantalla], centrada.
  static Rect _cubriendo(Size pantalla, ui.Image imagen) {
    final escala = (pantalla.width / imagen.width) > (pantalla.height / imagen.height)
        ? pantalla.width / imagen.width
        : pantalla.height / imagen.height;
    final tam = Size(imagen.width * escala, imagen.height * escala);
    return Offset((pantalla.width - tam.width) / 2, (pantalla.height - tam.height) / 2) &
        tam;
  }

  /// La imagen entera dentro de [pantalla], centrada.
  static Rect _entera(Size pantalla, ui.Image imagen) {
    final escala = (pantalla.width / imagen.width) < (pantalla.height / imagen.height)
        ? pantalla.width / imagen.width
        : pantalla.height / imagen.height;
    final tam = Size(imagen.width * escala, imagen.height * escala);
    return Offset((pantalla.width - tam.width) / 2, (pantalla.height - tam.height) / 2) &
        tam;
  }

  @override
  bool shouldRepaint(PintorFondoQuieto old) =>
      old.imagen != imagen ||
      old.chica != chica ||
      old.oscurecer != oscurecer ||
      old.brillo != brillo ||
      old.atenuado != atenuado ||
      old.fogonazo != fogonazo;
}
