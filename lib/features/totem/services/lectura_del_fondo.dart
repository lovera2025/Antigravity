import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:material_color_utilities/material_color_utilities.dart' as mcu;

import '../../../models/totem_config.dart';
import '../estilos/tu_fondo.dart';

/// Lo que se lee de una imagen para armar "Tu fondo": sus colores, qué tan
/// clara, colorida y cálida es, cuánto detalle tiene y dónde está lo
/// importante. De eso sale la receta ([receta]) y los tres colores
/// ([paleta]).
///
/// **Se lee una vez, al cargar la imagen en Personalizar**, sobre una copia
/// chica (unos 72 × 128 píxeles), y lo que sale se guarda con la config: la
/// PC y el tótem por el navegador muestran lo mismo sin volver a leerla.
@immutable
class LecturaDelFondo {
  /// Los colores de la imagen, el más representativo primero (los de
  /// `material_color_utilities`: Celebi y Score). Al menos uno.
  final List<Color> colores;

  /// Qué tan clara es, de 0 a 1 (la luminosidad L* de su luz media).
  final double luz;

  /// Qué tan clara es donde va el texto (el centro: de 15 % a 85 % a lo
  /// ancho, de 30 % a 75 % a lo alto). Con esta se mide si el saludo se lee:
  /// una imagen oscura con un brillo al medio (un dorado) es clara justo ahí.
  final double luzCentro;

  /// Qué tan colorida es, de 0 a 1 (Hasler y Süsstrunk).
  final double color;

  /// Cuántos colores distintos tiene, de 0 (uno solo, como un dorado) a 1
  /// (todos, como las luces de una fiesta). Sin color, 0.
  final double variedad;

  /// Cálida si es positiva (rojos, dorados), fría si es negativa (azules).
  final double calidez;

  /// Cuánto detalle tiene: el cambio medio de luz entre píxeles vecinos.
  final double detalle;

  /// Dónde está lo importante (lo de más detalle y luz), de 0 a 1.
  final Offset foco;

  const LecturaDelFondo({
    required this.colores,
    required this.luz,
    double? luzCentro,
    required this.color,
    required this.variedad,
    required this.calidez,
    required this.detalle,
    required this.foco,
  }) : luzCentro = luzCentro ?? luz;

  /// El ancho de la copia que se lee. Los umbrales de abajo están medidos a
  /// este tamaño.
  static const anchoDeLectura = 72;

  bool get clara => luz > 0.6;
  bool get oscura => luz < 0.38;
  bool get calida => calidez > 0.04;
  bool get fria => calidez < -0.05;
  /// Muchos colores distintos y vivos. Un dorado fuerte no: es uno solo.
  bool get colorida => variedad > 0.2 && color > 0.25;
  bool get apagada => color < 0.12;
  bool get muchoDetalle => detalle > 0.035;
  bool get lisa => detalle < 0.012;

  /// Lo que se dice en Personalizar: "Oscura", "Cálida", "Lo importante al
  /// centro".
  List<String> get palabras => [
        if (clara) 'Clara' else if (oscura) 'Oscura' else 'Media luz',
        if (calida) 'Cálida' else if (fria) 'Fría',
        if (colorida) 'Muy colorida' else if (apagada) 'Suave',
        if (muchoDetalle) 'Mucho detalle' else if (lisa) 'Lisa',
        'Lo importante ${_donde(foco)}',
      ];

  static String _donde(Offset f) {
    final vertical = f.dy < 0.36 ? 'arriba' : (f.dy > 0.64 ? 'abajo' : '');
    final horizontal =
        f.dx < 0.36 ? 'a la izquierda' : (f.dx > 0.64 ? 'a la derecha' : '');
    if (vertical.isEmpty && horizontal.isEmpty) return 'al centro';
    return [vertical, horizontal].where((s) => s.isNotEmpty).join(' ');
  }

  /// La receta que le toca a esta imagen ("Automático · según la imagen").
  ///
  /// - **Clara** (un pastel): respira, con bokeh, sin oscurecer y el texto
  ///   oscuro.
  /// - **Cálida** (dorados, rojos): se acerca despacio a lo importante, con
  ///   polvo de luz y un barrido.
  /// - **Fría** (azules, de noche): recorre hacia lo importante si está lejos
  ///   del centro, y si no ondula; con titileo y bruma.
  /// - **Muy colorida** (una fiesta): flota, con destellos de sus colores y el
  ///   marco que respira.
  /// - Lo demás: se acerca, con polvo de luz.
  ///
  /// Con mucho detalle se mueve menos (si no, tiembla); lisa, admite más.
  RecetaFondo receta() {
    final AnimacionFondo animacion;
    final List<EfectoFondo> efectos;
    final LetrasFondo letras;
    if (clara) {
      animacion = AnimacionFondo.respirar;
      efectos = const [EfectoFondo.bokeh];
      letras = LetrasFondo.suave;
    } else if (calida) {
      animacion = AnimacionFondo.acercarse;
      efectos = const [EfectoFondo.polvo, EfectoFondo.barrido];
      letras = LetrasFondo.clasica;
    } else if (fria) {
      final lejos = (foco - const Offset(0.5, 0.5)).distance > 0.22;
      animacion = lejos ? AnimacionFondo.recorrer : AnimacionFondo.ondular;
      efectos = const [EfectoFondo.titileo, EfectoFondo.bruma];
      letras = LetrasFondo.moderna;
    } else if (colorida) {
      animacion = AnimacionFondo.flotar;
      efectos = const [EfectoFondo.destellos, EfectoFondo.marco];
      letras = LetrasFondo.fiesta;
    } else {
      animacion = AnimacionFondo.acercarse;
      efectos = const [EfectoFondo.polvo];
      letras = LetrasFondo.clasica;
    }
    var intensidad = 40;
    if (muchoDetalle) intensidad = 30;
    if (lisa) intensidad = 50;
    // Recorrer ya mueve mucho la imagen: un poco menos, salvo que el detalle
    // ya la haya bajado.
    if (animacion == AnimacionFondo.recorrer && !muchoDetalle) intensidad -= 10;
    final oscurecer = clara
        ? 0
        : (luz > 0.45 ? 40 : (fria ? 20 : TotemConfig.oscurecerPorDefecto));
    return RecetaFondo(
      animacion: animacion,
      efectos: efectos,
      intensidad: intensidad.clamp(20, 60),
      intensidadEfectos: colorida && !clara ? 70 : 50,
      oscurecer: oscurecer,
      letras: letras,
    );
  }

  /// Los tres colores para el tótem, con [oscurecer] (0 a 80) como va a
  /// quedar la imagen.
  ///
  /// Sobre el fondo oscurecido, el brillo y el saludo se aclaran para que
  /// brillen; sobre una imagen clara que casi no se oscurece (el texto va
  /// oscuro, [textoOscuroSobre]) se oscurecen. **El saludo tiene que leerse**:
  /// si no llega al contraste 4,5 contra la luz del fondo, va blanco (o casi
  /// negro, con el texto oscuro).
  ColoresDelFondo paleta({required int oscurecer}) {
    final oscuro = textoOscuroSobre(luz: luzEntera, oscurecer: oscurecer);
    final elegidos = _tresDistintos();
    final a = mcu.Hct.fromInt(elegidos[0].toARGB32());
    final b = mcu.Hct.fromInt(elegidos[1].toARGB32());
    final c = mcu.Hct.fromInt(elegidos[2].toARGB32());
    // La luz del fondo detrás del saludo: el centro de la imagen, con el
    // oscurecido que hay a esa altura (la mitad del de arriba y el de abajo).
    final yFondo =
        mcu.ColorUtils.yFromLstar(luzCentro * 100) * (1 - 0.5 * oscurecer / 100);
    final tonoFondo = mcu.ColorUtils.lstarFromY(yFondo);

    Color hct(double tono, mcu.Hct de, {double? croma}) => Color(
          mcu.Hct.from(de.hue, croma ?? de.chroma, tono.clamp(0, 100)).toInt(),
        );

    if (oscuro) {
      final brillo = hct(62, a, croma: math.max(a.chroma, 30));
      var tono = math.min(b.tone, 38.0);
      while (tono > 10 && mcu.Contrast.ratioOfTones(tono, tonoFondo) < 4.5) {
        tono -= 2;
      }
      final saludo = mcu.Contrast.ratioOfTones(tono, tonoFondo) >= 4.5
          ? hct(tono, b, croma: math.max(b.chroma, 36))
          : const Color(0xFF1C1418);
      final tarjeta = hct(97, c, croma: math.min(c.chroma, 10));
      return ColoresDelFondo(brillo, saludo, tarjeta);
    }

    final brillo = hct(math.max(a.tone, 72), a, croma: math.max(a.chroma, 36));
    var tono = math.max(b.tone, 85.0);
    while (tono < 98 && mcu.Contrast.ratioOfTones(tono, tonoFondo) < 4.5) {
      tono += 2;
    }
    final saludo = mcu.Contrast.ratioOfTones(tono, tonoFondo) >= 4.5
        ? hct(tono, b)
        : const Color(0xFFFFFFFF);
    final tarjeta = hct(30, c, croma: math.min(c.chroma, 48));
    return ColoresDelFondo(brillo, saludo, tarjeta);
  }

  /// La luz detrás del texto, de 0 a 100, como se guarda (`fondo_luz`): con
  /// ella decide el tótem si el texto va oscuro y cuánto se oscurece detrás.
  int get luzEntera => (luzCentro * 100).round().clamp(0, 100);

  /// Tres colores distintos entre sí (en tono o en matiz). Si la imagen no
  /// tiene tres, se arman a partir del primero.
  List<Color> _tresDistintos() {
    final lista = <mcu.Hct>[];
    for (final col in colores) {
      final h = mcu.Hct.fromInt(col.toARGB32());
      final distinto = lista.every((o) {
        final dh = (h.hue - o.hue).abs();
        final matiz = math.min(dh, 360 - dh);
        final conColor = h.chroma > 12 && o.chroma > 12;
        return (h.tone - o.tone).abs() > 18 || (conColor && matiz > 24);
      });
      if (distinto) lista.add(h);
      if (lista.length == 3) break;
    }
    final base = lista.first;
    if (lista.length < 2) {
      lista.add(mcu.Hct.from((base.hue + 32) % 360, base.chroma, 85));
    }
    if (lista.length < 3) {
      lista.add(mcu.Hct.from(base.hue, math.min(base.chroma, 40), 25));
    }
    return [for (final h in lista) Color(h.toInt())];
  }

  // ── Cómo se lee ───────────────────────────────────────────────────────────

  /// Lee los bytes de un JPG, PNG o WEBP (los de Personalizar, recién
  /// elegidos).
  static Future<LecturaDelFondo> deBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: anchoDeLectura,
    );
    final cuadro = await codec.getNextFrame();
    codec.dispose();
    try {
      return await deImagen(cuadro.image);
    } finally {
      cuadro.image.dispose();
    }
  }

  /// Lee una imagen ya cargada (la que se ve en Personalizar). La achica a
  /// [anchoDeLectura] antes; la de entrada no se toca ni se suelta.
  static Future<LecturaDelFondo> deImagen(ui.Image imagen) async {
    final ancho = anchoDeLectura;
    final alto = math.max(
      1,
      (imagen.height * ancho / math.max(1, imagen.width)).round(),
    );
    final grabador = ui.PictureRecorder();
    ui.Canvas(grabador).drawImageRect(
      imagen,
      Rect.fromLTWH(0, 0, imagen.width.toDouble(), imagen.height.toDouble()),
      Rect.fromLTWH(0, 0, ancho.toDouble(), alto.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final cuadro = grabador.endRecording();
    final chica = await cuadro.toImage(ancho, alto);
    cuadro.dispose();
    try {
      final datos = await chica.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (datos == null) {
        throw StateError('No se pudieron leer los píxeles de la imagen');
      }
      return deRgba(datos.buffer.asUint8List(), ancho, alto);
    } finally {
      chica.dispose();
    }
  }

  /// La lectura en sí, sobre los píxeles RGBA de [ancho] × [alto] (en los
  /// tests, armados a mano).
  static Future<LecturaDelFondo> deRgba(
    Uint8List rgba,
    int ancho,
    int alto,
  ) async {
    final n = ancho * alto;
    final argb = List<int>.filled(n, 0);
    final gris = Float64List(n);
    var sumaY = 0.0;
    var sumaYCentro = 0.0;
    var nCentro = 0;
    var sumaCalidez = 0.0;
    var sumaRg = 0.0, sumaYb = 0.0, sumaRg2 = 0.0, sumaYb2 = 0.0;
    // La variedad: el matiz de cada píxel con color, como una flecha; si
    // apuntan todas para el mismo lado (un dorado) la suma es larga, y si
    // apuntan para todos lados (una fiesta) se anulan.
    var sumaCos = 0.0, sumaSen = 0.0, sumaPeso = 0.0;
    for (var i = 0; i < n; i++) {
      final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
      argb[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
      final y = 0.2126 * mcu.ColorUtils.linearized(r) +
          0.7152 * mcu.ColorUtils.linearized(g) +
          0.0722 * mcu.ColorUtils.linearized(b);
      sumaY += y;
      final px = i % ancho, py = i ~/ ancho;
      if (px >= ancho * 0.15 &&
          px < ancho * 0.85 &&
          py >= alto * 0.3 &&
          py < alto * 0.75) {
        sumaYCentro += y;
        nCentro++;
      }
      gris[i] = mcu.ColorUtils.lstarFromY(y) / 100;
      final maximo = math.max(r, math.max(g, b));
      final minimo = math.min(r, math.min(g, b));
      final saturacion = maximo == 0 ? 0.0 : (maximo - minimo) / maximo;
      sumaCalidez += (r - b) / 255 * saturacion;
      if (saturacion > 0.25 && maximo > 50) {
        final peso = saturacion * maximo / 255;
        final matiz = _matiz(r, g, b, maximo, minimo);
        sumaCos += peso * math.cos(matiz);
        sumaSen += peso * math.sin(matiz);
        sumaPeso += peso;
      }
      final rg = (r - g).toDouble();
      final yb = 0.5 * (r + g) - b;
      sumaRg += rg;
      sumaYb += yb;
      sumaRg2 += rg * rg;
      sumaYb2 += yb * yb;
    }

    // Qué tan colorida (Hasler y Süsstrunk, 2003), llevado a 0..1.
    final mRg = sumaRg / n, mYb = sumaYb / n;
    final sRg = math.sqrt(math.max(0, sumaRg2 / n - mRg * mRg));
    final sYb = math.sqrt(math.max(0, sumaYb2 / n - mYb * mYb));
    final colorido = math.sqrt(sRg * sRg + sYb * sYb) +
        0.3 * math.sqrt(mRg * mRg + mYb * mYb);

    // El detalle y dónde está: el cambio de luz con el vecino de la derecha y
    // el de abajo, por casilla de una grilla de 6 × 8; gana la de más detalle,
    // con un poco de la luz (lo que brilla también llama la mirada).
    const columnas = 6, filas = 8;
    final energia = Float64List(columnas * filas);
    final luzCasilla = Float64List(columnas * filas);
    final cuenta = Int32List(columnas * filas);
    var sumaDetalle = 0.0;
    var cantidad = 0;
    for (var y = 0; y < alto; y++) {
      for (var x = 0; x < ancho; x++) {
        final i = y * ancho + x;
        final casilla = (y * filas ~/ alto) * columnas + (x * columnas ~/ ancho);
        luzCasilla[casilla] += gris[i];
        cuenta[casilla]++;
        if (x + 1 < ancho && y + 1 < alto) {
          final d = (gris[i + 1] - gris[i]).abs() + (gris[i + ancho] - gris[i]).abs();
          energia[casilla] += d;
          sumaDetalle += d;
          cantidad++;
        }
      }
    }
    var mejor = 0;
    var mejorPuntaje = -1.0;
    for (var k = 0; k < columnas * filas; k++) {
      if (cuenta[k] == 0) continue;
      final puntaje = (energia[k] + 0.25 * luzCasilla[k]) / cuenta[k];
      if (puntaje > mejorPuntaje) {
        mejorPuntaje = puntaje;
        mejor = k;
      }
    }
    final foco = Offset(
      ((mejor % columnas) + 0.5) / columnas,
      ((mejor ~/ columnas) + 0.5) / filas,
    );

    // Con muy poco color no hay variedad que medir.
    final variedad = sumaPeso < n * 0.03
        ? 0.0
        : 1 - math.sqrt(sumaCos * sumaCos + sumaSen * sumaSen) / sumaPeso;

    return LecturaDelFondo(
      colores: await _colores(argb),
      luz: mcu.ColorUtils.lstarFromY(sumaY / n) / 100,
      luzCentro: nCentro == 0
          ? null
          : mcu.ColorUtils.lstarFromY(sumaYCentro / nCentro) / 100,
      color: (colorido / 110).clamp(0.0, 1.0),
      variedad: variedad.clamp(0.0, 1.0),
      calidez: sumaCalidez / n,
      detalle: cantidad == 0 ? 0 : sumaDetalle / cantidad,
      foco: foco,
    );
  }

  /// El matiz de un píxel, en radianes.
  static double _matiz(int r, int g, int b, int maximo, int minimo) {
    final d = (maximo - minimo).toDouble();
    if (d == 0) return 0;
    double h;
    if (maximo == r) {
      h = ((g - b) / d) % 6;
    } else if (maximo == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    return h / 6 * 2 * math.pi;
  }

  /// Los colores de la imagen: los que elige Score entre los de Celebi y,
  /// detrás, los más abundantes. Score descarta los grises (una imagen casi
  /// blanca): **se le da un respaldo propio**, porque el suyo es el azul de
  /// Google, que no está en la imagen.
  static Future<List<Color>> _colores(List<int> argb) async {
    final cuantizado = await mcu.QuantizerCelebi().quantize(argb, 16);
    final conteo = cuantizado.colorToCount;
    const respaldo = 0x00000000;
    final puntuados = mcu.Score.score(
      conteo,
      desired: 4,
      fallbackColorARGB: respaldo,
    ).where((c) => c != respaldo);
    final porCantidad = conteo.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    final vistos = <int>{};
    final lista = <Color>[];
    for (final c in [...puntuados, ...porCantidad.map((e) => e.key)]) {
      if (vistos.add(c)) lista.add(Color(0xFF000000 | (c & 0xFFFFFF)));
    }
    if (lista.isEmpty) lista.add(TotemConfig.acentoPorDefecto);
    return lista;
  }
}

/// La receta de "Tu fondo": lo que se guarda en la config además de la
/// imagen y los colores.
@immutable
class RecetaFondo {
  final AnimacionFondo animacion;
  final List<EfectoFondo> efectos;

  /// De 0 a 100.
  final int intensidad;
  final int intensidadEfectos;

  /// De 0 a 80.
  final int oscurecer;
  final LetrasFondo letras;

  const RecetaFondo({
    required this.animacion,
    required this.efectos,
    required this.intensidad,
    required this.intensidadEfectos,
    required this.oscurecer,
    required this.letras,
  });

  /// "Acercarse · Polvo de luz y Barrido de luz".
  String get resumen {
    final fx = efectos.map((e) => e.nombre).toList();
    final conFx = fx.isEmpty
        ? 'sin efectos'
        : (fx.length == 1
            ? fx.single
            : '${fx.sublist(0, fx.length - 1).join(', ')} y ${fx.last}');
    return '${animacion.nombre} · $conFx';
  }
}

/// [cfg] con todo lo que sale de la imagen: la receta (si es automática), la
/// paleta, el foco y la luz. La paleta se rehace siempre: depende del
/// oscurecido, que se puede cambiar a mano.
TotemConfig conLaLectura(
  TotemConfig cfg,
  LecturaDelFondo lectura, {
  required bool automatico,
}) {
  final r = lectura.receta();
  final oscurecer = automatico ? r.oscurecer : cfg.fondoOscurecer;
  return cfg.copyWith(
    fondoAutomatico: automatico,
    fondoAnimacion: automatico ? r.animacion.clave : null,
    fondoEfectos: automatico ? [for (final e in r.efectos) e.clave] : null,
    fondoIntensidad: automatico ? r.intensidad : null,
    fondoIntensidadEfectos: automatico ? r.intensidadEfectos : null,
    fondoOscurecer: oscurecer,
    fondoLetras: r.letras.clave,
    fondoPaleta: lectura.paleta(oscurecer: oscurecer).lista,
    fondoFoco: lectura.foco,
    fondoLuz: lectura.luzEntera,
  );
}
