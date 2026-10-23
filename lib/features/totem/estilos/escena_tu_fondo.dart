import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/contenido_bienvenida.dart';
import 'escena_totem.dart';
import 'fuentes_totem.dart';
import 'totem_estilo.dart';
import 'tu_fondo.dart';

/// "Tu fondo": sobre la imagen del evento (la pinta `FondoPropio`), los
/// efectos que tocan (destellos, polvo de luz, bokeh, titileo, barrido, el
/// marco que respira, bruma; el glitch va en el shader) y el texto en las
/// letras y los colores que salieron de la imagen.
///
/// Con una imagen clara que casi no se oscurece (un pastel) el texto va
/// oscuro, sin brillo de neón, y detrás se aclara apenas.
class EscenaTuFondo extends EscenaEstilo {
  const EscenaTuFondo();

  @override
  List<Widget> capasDeFondo(DatosEscena d) {
    final r = RecetaDibujada.de(d.cfg);
    // Detrás del texto, la imagen se aclara (texto oscuro) o se oscurece un
    // poco más (texto claro), según qué tan clara sea ahí: un dorado brillante
    // al medio se tapaba con el saludo dorado.
    final luz = (d.cfg.fondoLuz ?? 30) / 100;
    final sombra = (0.12 + (luz - 0.2) * 0.8).clamp(0.12, 0.45);
    return [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.15),
            radius: 0.8,
            colors: r.textoOscuro
                ? const [Color(0x6BFFFFFF), Color(0x00FFFFFF)]
                : [
                    Colors.black.withValues(alpha: sombra),
                    Colors.black.withValues(alpha: 0),
                  ],
          ),
        ),
      ),
      if (r.efectos.any((e) => e != EfectoFondo.glitch))
        IgnorePointer(
          child: CustomPaint(
            painter: PintorEfectos(receta: r, reloj: d.reloj, u: d.u),
            child: const SizedBox.expand(),
          ),
        ),
    ];
  }

  @override
  Widget espera(DatosEscena d) {
    final u = d.u;
    final r = RecetaDibujada.de(d.cfg);
    final t = _Textos.de(r);
    final titulo = partirTitulo(d.cfg.titulo);
    final qr = d.qrUrl;
    return Centrado(
      margen: EdgeInsets.fromLTRB(u * 2, u * 2.2, u * 2, u * (qr == null ? 3.4 : 1.4)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: r.textoOscuro
                  ? const []
                  : [
                      BoxShadow(
                        color: r.colores.brillo.withValues(alpha: 0.45),
                        blurRadius: u * 1.2,
                      ),
                    ],
            ),
            child: FotoEvento(
              imagen: d.foto,
              lado: u * 5.2,
              borde: r.colores.brillo,
              grosor: u * 0.12,
            ),
          ),
          SizedBox(height: u * 1.3),
          if (titulo.chico != null)
            Text(
              titulo.chico!,
              textAlign: TextAlign.center,
              style: t.estilo(
                r.letras.chico,
                tamano: u * 1.15,
                color: t.chico,
                sombras: t.suaves(u),
              ).copyWith(letterSpacing: u * 0.45),
            ),
          Text(
            titulo.grande,
            textAlign: TextAlign.center,
            style: t.estilo(
              r.letras.titulo,
              tamano: u * (titulo.chico == null ? 2.8 : 5.0),
              color: t.grande,
              alto: 1.0,
              sombras: t.brillo(u),
            ).copyWith(
              letterSpacing:
                  r.letras == LetrasFondo.moderna ? u * 0.25 : null,
            ),
          ),
          if (d.cfg.subtitulo.isNotEmpty) ...[
            SizedBox(height: u * 0.4),
            Text(
              d.cfg.subtitulo,
              textAlign: TextAlign.center,
              style: t.estilo(
                r.letras.saludo,
                tamano: u * 1.5,
                color: t.saludo,
                sombras: t.suaves(u),
              ),
            ),
          ],
          SizedBox(height: u * 0.9),
          Text(
            d.cfg.mensajeBienvenida,
            textAlign: TextAlign.center,
            style: t.estilo(
              r.letras.saludo,
              tamano: u * 2.6,
              color: t.saludo,
              sombras: t.brilloSaludo(u),
            ),
          ),
          if (qr != null) ...[
            SizedBox(height: u * 1.2),
            QrDelTotem(
              url: qr,
              texto: d.cfg.mensajeQr,
              u: u,
              marco: r.colores.brillo,
              colorTexto: t.suave,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget llegada(DatosEscena d, ContenidoBienvenida c) {
    final u = d.u;
    final r = RecetaDibujada.de(d.cfg);
    final t = _Textos.de(r);
    final con = conQuienDe(c);

    /// Entra subiendo apenas, en el tramo [desde]–[hasta] de la entrada.
    Widget entra(double desde, double hasta, Widget hijo) {
      final p = d.tramo(desde, hasta);
      return Opacity(
        opacity: p,
        child: Transform.translate(offset: Offset(0, (1 - p) * u * 1.2), child: hijo),
      );
    }

    final contenido = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        entra(
          0,
          0.3,
          Text(
            c.saludo,
            textAlign: TextAlign.center,
            style: t.estilo(
              r.letras.saludo,
              tamano: u * 3.0,
              color: t.saludo,
              sombras: t.brilloSaludo(u),
            ),
          ),
        ),
        SizedBox(height: u * 0.4),
        for (final (i, n) in c.nombres.indexed) ...[
          if (i > 0) SizedBox(height: u * 0.25),
          entra(
            0.2,
            0.5,
            Text(
              n,
              textAlign: TextAlign.center,
              style: t.estilo(
                r.letras.titulo,
                tamano: u * (c.nombres.length > 1 ? 1.7 : 2.1),
                color: t.grande,
                alto: 1.1,
                sombras: t.brillo(u, fuerza: 0.7),
              ),
            ),
          ),
        ],
        if (con != null) ...[
          SizedBox(height: u * 0.4),
          entra(
            0.3,
            0.6,
            Text(
              con,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: FuentesTotem.linea,
                fontSize: u * 1.0,
                color: t.suave,
                shadows: t.suaves(u),
              ),
            ),
          ),
        ],
        if (c.mesa != null) ...[
          SizedBox(height: u * 1.0),
          entra(0.45, 0.8, _tarjeta(d, c, r, t)),
        ] else if (c.musica != null)
          Opacity(
            opacity: d.tramo(0.6, 0.9),
            child: sillasYMusica(
              c,
              d,
              familia: FuentesTotem.linea,
              colorMusica: t.musica,
            ),
          ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: CustomPaint(
            painter: _Chispas(
              progreso: d.tramo(0.05, 0.45, curva: Curves.linear),
              color: r.colores.brillo,
              u: u,
            ),
          ),
        ),
        Centrado(
          margen: EdgeInsets.fromLTRB(u * 1.6, u * 2.2, u * 1.6, u * 2.6),
          child: contenido,
        ),
      ],
    );
  }

  /// La tarjeta de la mesa: el número grande y, al lado, las sillas y la
  /// música. En el color de la tarjeta de la imagen, con el borde del brillo.
  Widget _tarjeta(DatosEscena d, ContenidoBienvenida c, RecetaDibujada r, _Textos t) {
    final u = d.u;
    final mesa = c.mesa!;
    final derecha = <Widget>[
      if (c.sillas != null)
        Text(
          c.sillas!,
          style: TextStyle(
            fontFamily: FuentesTotem.linea,
            fontSize: u * 0.85,
            color: t.suave,
          ),
        ),
      if (c.musica != null) ...[
        if (c.sillas != null) SizedBox(height: u * 0.35),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded, size: u * 0.95, color: t.musica),
            SizedBox(width: u * 0.25),
            Flexible(
              child: Text(
                c.musica!,
                style: TextStyle(
                  fontFamily: FuentesTotem.linea,
                  fontSize: u * 0.9,
                  color: t.musica,
                ),
              ),
            ),
          ],
        ),
      ],
    ];
    return Container(
      padding: EdgeInsets.symmetric(horizontal: u * 1.3, vertical: u * 0.6),
      decoration: BoxDecoration(
        color: r.textoOscuro
            ? Colors.white.withValues(alpha: 0.62)
            : r.colores.tarjeta.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(u * 1.1),
        border: Border.all(color: r.colores.brillo, width: math.max(1, u * 0.07)),
        boxShadow: [
          BoxShadow(
            color: r.colores.brillo.withValues(alpha: 0.25),
            blurRadius: u * 1.5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.rotuloMesa.toUpperCase(),
                style: TextStyle(
                  fontFamily: FuentesTotem.linea,
                  fontWeight: FontWeight.w700,
                  fontSize: u * 0.7,
                  letterSpacing: u * 0.2,
                  color: t.suave,
                ),
              ),
              Text(
                mesa,
                style: t.estilo(
                  r.letras.titulo,
                  tamano: u * (mesa.length > 3 ? 2.0 : 3.2),
                  color: t.grande,
                  alto: 1.0,
                  sombras: t.brillo(u, fuerza: 0.8),
                ),
              ),
            ],
          ),
          if (derecha.isNotEmpty) ...[
            SizedBox(width: u * 1.0),
            Container(
              width: math.max(1, u * 0.06),
              height: u * 3.2,
              color: r.colores.brillo.withValues(alpha: 0.5),
            ),
            SizedBox(width: u * 1.0),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: derecha,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Los colores del texto, claros sobre la imagen oscurecida u oscuros sobre
/// una clara.
class _Textos {
  final RecetaDibujada r;
  final Color grande;
  final Color chico;
  final Color saludo;
  final Color suave;
  final Color musica;

  _Textos._(this.r, this.grande, this.chico, this.saludo, this.suave, this.musica);

  factory _Textos.de(RecetaDibujada r) {
    final s = r.colores.saludo;
    if (r.textoOscuro) {
      return _Textos._(
        r,
        Color.lerp(s, const Color(0xFF000000), 0.45)!,
        Color.lerp(s, const Color(0xFF000000), 0.25)!,
        s,
        Color.lerp(s, const Color(0xFF000000), 0.35)!,
        s,
      );
    }
    final calido = Color.lerp(s, const Color(0xFFFFFFFF), 0.7)!;
    return _Textos._(
      r,
      Color.lerp(s, const Color(0xFFFFFFFF), 0.82)!,
      calido,
      s,
      Colors.white.withValues(alpha: 0.86),
      r.colores.brillo,
    );
  }

  TextStyle estilo(
    LetraFondo letra, {
    required double tamano,
    required Color color,
    double? alto,
    List<Shadow>? sombras,
  }) =>
      TextStyle(
        fontFamily: letra.familia,
        fontWeight: letra.peso,
        fontStyle: letra.estilo,
        // Las cifras alineadas en la serif de Gala: "12" se leía "I2".
        fontFeatures: letra.familia == FuentesTotem.gala
            ? const [FontFeature.liningFigures()]
            : null,
        fontSize: tamano,
        height: alto,
        color: color,
        shadows: sombras,
      );

  /// Una sombra oscura y suave que despega el texto claro de la imagen.
  Shadow _despega(double u) =>
      Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: u * 0.7);

  /// El resplandor del título: el de neón, en el brillo de la imagen, sobre
  /// la sombra que lo despega. Con el texto oscuro, una sombra clara.
  List<Shadow> brillo(double u, {double fuerza = 0.75}) => r.textoOscuro
      ? [Shadow(color: Colors.white.withValues(alpha: 0.85), blurRadius: u * 1.3)]
      : [_despega(u), ...brilloNeon(r.colores.brillo, u, fuerza: fuerza)];

  List<Shadow> brilloSaludo(double u) => r.textoOscuro
      ? [Shadow(color: Colors.white.withValues(alpha: 0.7), blurRadius: u * 0.8)]
      : [
          _despega(u),
          Shadow(
            color: r.colores.brillo.withValues(alpha: 0.6),
            blurRadius: u * 0.9,
          ),
        ];

  /// Para lo chico (el subtítulo, "con…"): solo la sombra que lo despega.
  List<Shadow>? suaves(double u) => r.textoOscuro ? null : [_despega(u)];
}

/// Los efectos que van encima de la imagen, dibujados con el reloj de la
/// escena (da vueltas cada 60 s: cada período divide a 60, así no salta).
///
/// Lo que varía de una imagen a otra (dónde nace cada destello, para dónde se
/// corre) sale de [RecetaDibujada.semilla].
class PintorEfectos extends CustomPainter {
  final RecetaDibujada receta;
  final double reloj;
  final double u;

  PintorEfectos({required this.receta, required this.reloj, required this.u});

  /// Períodos que dividen a 60 s.
  static const _rapidos = [5.0, 6.0, 7.5, 10.0, 12.0];
  static const _lentos = [12.0, 15.0, 20.0];
  static const _titileos = [2.0, 2.5, 3.0, 4.0, 5.0];

  @override
  void paint(Canvas canvas, Size size) {
    final e = receta.intensidadEfectos;
    for (final efecto in receta.efectos) {
      final azar = _Azar(receta.semilla ^ (efecto.index * 0x9E3779B1));
      switch (efecto) {
        case EfectoFondo.destellos:
          _suben(canvas, size, azar, (10 + 30 * e).round(), 0.13, 0.3, _rapidos, 0.7, 3.5);
        case EfectoFondo.polvo:
          _suben(canvas, size, azar, (16 + 40 * e).round(), 0.05, 0.12, _lentos, 0.5, 3);
        case EfectoFondo.bokeh:
          _bokeh(canvas, size, azar, (4 + 10 * e).round());
        case EfectoFondo.titileo:
          _titileo(canvas, size, azar, (14 + 40 * e).round());
        case EfectoFondo.barrido:
          _barrido(canvas, size, e);
        case EfectoFondo.marco:
          _marco(canvas, size, e);
        case EfectoFondo.bruma:
          _bruma(canvas, size, azar, e);
        case EfectoFondo.glitch:
          break; // Lo hace el shader: necesita la imagen.
      }
    }
  }

  Color _color(_Azar azar, double alfa) {
    final c = receta.colores;
    final elegido = [c.brillo, c.saludo, Colors.white][azar.entero(3)];
    return elegido.withValues(alpha: alfa.clamp(0.0, 1.0));
  }

  static double _vaiven(double t, double periodo) =>
      0.5 - 0.5 * math.cos(2 * math.pi * t / periodo);

  void _punto(Canvas canvas, Offset c, double radio, Color color, double brillo) {
    canvas.drawCircle(
      c,
      radio * brillo * 0.6,
      Paint()
        ..color = color.withValues(alpha: color.a * 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radio * brillo * 0.5),
    );
    canvas.drawCircle(c, radio, Paint()..color = color);
  }

  /// Destellos y polvo de luz: nacen abajo y suben, apareciendo y yéndose.
  void _suben(
    Canvas canvas,
    Size size,
    _Azar azar,
    int n,
    double minimo,
    double maximo,
    List<double> periodos,
    double alfaMinima,
    double brillo,
  ) {
    for (var k = 0; k < n; k++) {
      final x0 = azar.real();
      final radio = u * (minimo + azar.real() * (maximo - minimo)) / 2;
      final periodo = periodos[azar.entero(periodos.length)];
      final fase = azar.real();
      final deriva = u * (azar.real() * 3.2 - 1.6);
      final alfa = alfaMinima + azar.real() * (1 - alfaMinima);
      final color = _color(azar, alfa);
      final p = (reloj / periodo + fase) % 1;
      final aparece = p < 0.12 ? p / 0.12 : (p > 0.72 ? (1 - p) / 0.28 : 1.0);
      final centro = Offset(
        x0 * size.width + deriva * p,
        size.height * (1.04 - 1.10 * p),
      );
      _punto(
        canvas,
        centro,
        radio * (0.6 + 0.4 * p),
        color.withValues(alpha: color.a * aparece),
        brillo,
      );
    }
  }

  /// Luces grandes y desenfocadas que flotan en el lugar.
  void _bokeh(Canvas canvas, Size size, _Azar azar, int n) {
    for (var k = 0; k < n; k++) {
      final base = Offset(azar.real() * 0.92 * size.width, (0.04 + azar.real() * 0.7) * size.height);
      final radio = u * (0.6 + azar.real() * 1.6);
      final periodo = _rapidos[azar.entero(_rapidos.length)];
      final fase = azar.real() * periodo;
      final ida = Offset((azar.real() * 2 - 1) * u * 1.6, (azar.real() * 2 - 1) * u * 1.6);
      final c = receta.colores;
      final color = [Colors.white, c.brillo, c.tarjeta][azar.entero(3)];
      final alfa = 0.22 + azar.real() * 0.3;
      final v = _vaiven(reloj + fase, periodo);
      canvas.drawCircle(
        base + ida * v,
        radio,
        Paint()
          ..color = color.withValues(alpha: alfa * (0.55 + 0.45 * v))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radio * 0.18),
      );
    }
  }

  /// Puntos que se prenden y se apagan en el lugar, en los dos tercios de
  /// arriba.
  void _titileo(Canvas canvas, Size size, _Azar azar, int n) {
    for (var k = 0; k < n; k++) {
      final c = Offset(azar.real() * size.width, azar.real() * 0.7 * size.height);
      final radio = u * (0.025 + azar.real() * 0.04);
      final periodo = _titileos[azar.entero(_titileos.length)];
      final fase = azar.real() * periodo;
      final alfa = 0.6 + azar.real() * 0.4;
      final color = _color(azar, alfa);
      final v = _vaiven(reloj + fase, periodo);
      _punto(canvas, c, radio * (0.5 + 0.5 * v), color.withValues(alpha: color.a * (0.05 + 0.95 * v)), 3);
    }
  }

  /// Una franja de luz que cruza en diagonal y descansa antes de volver.
  void _barrido(Canvas canvas, Size size, double e) {
    final periodo = e > 0.6 ? 7.5 : 10.0;
    final q = (reloj / periodo) % 1;
    final p = q < 0.55 ? Curves.easeInOut.transform(q / 0.55) : 1.0;
    final ancho = size.width * 0.16;
    final cx = size.width * (-0.3 + 1.6 * p);
    canvas.save();
    canvas.translate(cx, size.height / 2);
    canvas.rotate(0.35);
    final franja = Rect.fromCenter(
      center: Offset.zero,
      width: ancho,
      height: size.height * 1.6,
    );
    canvas.drawRect(
      franja,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = LinearGradient(
          colors: [
            receta.colores.brillo.withValues(alpha: 0),
            receta.colores.brillo.withValues(alpha: 0.14 + 0.32 * e),
            receta.colores.brillo.withValues(alpha: 0),
          ],
        ).createShader(franja),
    );
    canvas.restore();
  }

  /// El borde que se enciende y se apaga.
  void _marco(Canvas canvas, Size size, double e) {
    final v = _vaiven(reloj, 7.5);
    final alfa = (0.2 + 0.2 * e) + v * (0.3 + 0.3 * e);
    final margen = math.min(size.width, size.height) * 0.032;
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(margen),
      Radius.circular(u * 0.9),
    );
    final color = receta.colores.brillo;
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.3
        ..color = color.withValues(alpha: alfa * 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * (0.3 + 0.6 * v)),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, u * 0.12)
        ..color = Color.lerp(color, Colors.white, 0.3)!.withValues(alpha: alfa),
    );
  }

  /// Tres manchas de luz grandes que cruzan despacio por abajo.
  void _bruma(Canvas canvas, Size size, _Azar azar, double e) {
    final c = receta.colores;
    final colores = [c.brillo, Colors.white, c.saludo];
    const periodos = [20.0, 30.0, 20.0];
    for (var k = 0; k < 3; k++) {
      final ancho = size.width * (0.9 + azar.real() * 0.4);
      final alto = size.height * (0.12 + azar.real() * 0.08);
      final x0 = size.width * (-0.25 + azar.real() * 0.3);
      final y0 = size.height * (0.52 + k * 0.12);
      final fase = azar.real() * periodos[k];
      final v = _vaiven(reloj + fase, periodos[k]);
      final dx = size.width * 0.16 * (2 * v - 1);
      final rect = Rect.fromLTWH(x0 + dx, y0, ancho, alto);
      final alfa = (0.1 + 0.25 * e) * (0.5 + 0.5 * v);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colores[k].withValues(alpha: alfa),
              colores[k].withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(PintorEfectos old) =>
      old.reloj != reloj || old.u != u || old.receta != receta;
}

/// Las chispas de la llegada: salen del medio de arriba, con el fogonazo.
class _Chispas extends CustomPainter {
  final double progreso;
  final Color color;
  final double u;

  _Chispas({required this.progreso, required this.color, required this.u});

  @override
  void paint(Canvas canvas, Size size) {
    if (progreso <= 0 || progreso >= 1) return;
    final centro = Offset(size.width / 2, size.height * 0.3);
    final alfa = progreso < 0.1 ? progreso / 0.1 : (1 - progreso);
    for (var k = 0; k < 12; k++) {
      final a = k * math.pi / 6;
      final lejos = u * 10 * Curves.easeOut.transform(progreso);
      final c = centro + Offset(math.cos(a), math.sin(a)) * lejos;
      final radio = u * (k % 3 == 0 ? 0.22 : 0.14);
      final tono = k.isEven ? color : Colors.white;
      canvas.drawCircle(
        c,
        radio * 2,
        Paint()
          ..color = tono.withValues(alpha: 0.35 * alfa)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radio),
      );
      canvas.drawCircle(c, radio, Paint()..color = tono.withValues(alpha: alfa));
    }
  }

  @override
  bool shouldRepaint(_Chispas old) =>
      old.progreso != progreso || old.color != color || old.u != u;
}

/// Un azar que da siempre lo mismo para la misma semilla (xorshift de 32 bits,
/// igual en la PC y en la web).
class _Azar {
  int _s;

  _Azar(int semilla) : _s = (semilla & 0xFFFFFFFF) == 0 ? 0x9E3779B9 : semilla & 0xFFFFFFFF;

  int _siguiente() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _s = x & 0xFFFFFFFF;
    return _s;
  }

  /// De 0 a 1.
  double real() => _siguiente() / 4294967296;

  int entero(int hasta) => _siguiente() % hasta;
}
