import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/contenido_bienvenida.dart';
import 'escena_totem.dart';
import 'forma_foto.dart';
import 'fuentes_totem.dart';
import 'totem_estilo.dart';

/// Las cifras alineadas. Las de Cormorant son de estilo antiguo: un 1 se lee
/// como una I ("12" parecía "I2"). En pantalla se le pueden pedir las otras;
/// en el PDF no, y por eso ahí los números de Gala van en Outfit.
const _cifras = [FontFeature.liningFigures()];

/// Gala: sobre la seda oscura con haces y polvo dorado, la foto en un anillo
/// que gira y el título en serif con un brillo que lo cruza. En la llegada el
/// nombre aparece letra por letra y la mesa va en un medallón que se dibuja.
class EscenaGala extends EscenaEstilo {
  const EscenaGala();

  @override
  Widget espera(DatosEscena d) {
    final u = d.u;
    final titulo = partirTitulo(d.cfg.titulo);
    final grande = Text(
      titulo.grande,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: FuentesTotem.gala,
        fontFeatures: _cifras,
        fontWeight: FontWeight.w600,
        fontSize: u * (titulo.chico == null ? 2.8 : 4.6),
        height: 1.0,
        color: Colors.white,
      ),
    );
    final foto = fotoDeLaEspera(
      d,
      lado: u * 5.4,
      borde: d.color.withValues(alpha: 0.7),
      grosor: u * 0.04,
      // El anillo que gira va con el círculo, y crece con la foto. Con otra
      // forma queda su borde dorado.
      alrededor: (foto, forma, medida) {
        if (forma != FormaFoto.circulo) return foto;
        final escala = medida.width / 5.4;
        return SizedBox(
          width: escala * 7,
          height: escala * 7,
          child: CustomPaint(
            painter: _Anillo(giro: d.reloj * 0.15, color: d.color, u: escala),
            child: Center(child: foto),
          ),
        );
      },
    );
    return Centrado(
      margen: EdgeInsets.symmetric(horizontal: u * 2, vertical: u * 2.4),
      ubicacion: d.ubicacionDeLaEspera,
      child: d.bloque(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (foto != null) ...[foto, SizedBox(height: u * 1.1)],
            d.frases([
              if (titulo.chico != null)
                Text(
                  titulo.chico!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FuentesTotem.gala,
                    fontFeatures: _cifras,
                    fontWeight: FontWeight.w600,
                    fontSize: u * 1.2,
                    letterSpacing: u * 0.35,
                    color: d.color,
                  ),
                ),
              // Un brillo cruza el título cada seis segundos.
              ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (r) {
                  final x = ((d.reloj % 6) / 6) * 3 - 1;
                  return LinearGradient(
                    begin: Alignment(x - 0.4, -0.3),
                    end: Alignment(x + 0.4, 0.3),
                    colors: [
                      Colors.white,
                      Color.lerp(d.color, Colors.white, 0.6)!,
                      Colors.white,
                    ],
                  ).createShader(r);
                },
                child: grande,
              ),
              if (d.cfg.subtitulo.isNotEmpty) ...[
                SizedBox(height: u * 0.4),
                Text(
                  d.cfg.subtitulo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FuentesTotem.gala,
                    fontFeatures: _cifras,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    fontSize: u * 1.3,
                    color: d.color,
                  ),
                ),
              ],
              SizedBox(height: u * 0.8),
              Text(
                d.cfg.mensajeBienvenida,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: FuentesTotem.gala,
                  fontFeatures: _cifras,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  fontSize: u * 1.6,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              if (d.qrUrl != null) ...[
                SizedBox(height: u * 1.1),
                QrDelTotem(
                  url: d.qrUrl!,
                  texto: d.cfg.mensajeQr,
                  u: u,
                  marco: d.color,
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget llegada(DatosEscena d, ContenidoBienvenida c) {
    final u = d.u;
    final nombre = d.tramo(0.15, 0.7, curva: Curves.linear);
    final medallon = d.tramo(0.5, 0.95);
    final con = conQuienDe(c);
    return Centrado(
      margen: EdgeInsets.symmetric(horizontal: u * 1.6, vertical: u * 2.4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: d.tramo(0, 0.25),
            child: Text(
              c.saludo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: FuentesTotem.gala,
                fontFeatures: _cifras,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                fontSize: u * 2.2,
                color: d.color,
              ),
            ),
          ),
          SizedBox(height: u * 0.3),
          for (final (i, n) in c.nombres.indexed) ...[
            if (i > 0) SizedBox(height: u * 0.2),
            letraPorLetra(
              n,
              TextStyle(
                fontFamily: FuentesTotem.gala,
                fontFeatures: _cifras,
                fontWeight: FontWeight.w600,
                fontSize: u * (c.nombres.length > 1 ? 1.8 : 2.2),
                height: 1.1,
                color: Colors.white,
              ),
              nombre,
            ),
          ],
          if (con != null) ...[
            SizedBox(height: u * 0.4),
            Opacity(
              opacity: nombre,
              child: Text(
                con,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: FuentesTotem.gala,
                  fontFeatures: _cifras,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  fontSize: u * 1.15,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
          if (c.mesa != null) ...[
            SizedBox(height: u * 0.8),
            SizedBox(
              width: u * 8,
              height: u * 8,
              child: CustomPaint(
                painter: _Medallon(progreso: medallon, color: d.color, u: u),
                child: Center(
                  child: Opacity(
                    opacity: medallon,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.rotuloMesa.toUpperCase(),
                          style: TextStyle(
                            fontFamily: FuentesTotem.gala,
                            fontFeatures: _cifras,
                            fontWeight: FontWeight.w600,
                            fontSize: u * 0.75,
                            letterSpacing: u * 0.25,
                            color: d.color,
                          ),
                        ),
                        Text(
                          c.mesa!,
                          style: TextStyle(
                            fontFamily: FuentesTotem.gala,
                            fontFeatures: _cifras,
                            fontWeight: FontWeight.w600,
                            fontSize: u * (c.mesa!.length > 3 ? 2 : 3),
                            height: 1.0,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          Opacity(
            opacity: d.tramo(0.75, 1),
            child: sillasYMusica(
              c,
              d,
              familia: FuentesTotem.gala,
              estiloMusica: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// El anillo de la foto, con marcas que giran.
class _Anillo extends CustomPainter {
  final double giro;
  final Color color;
  final double u;

  _Anillo({required this.giro, required this.color, required this.u});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - u * 0.15;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.06
      ..color = color.withValues(alpha: 0.85);
    canvas.drawCircle(c, r, p);
    const marcas = 36;
    for (var i = 0; i < marcas; i++) {
      final a = giro + i * 2 * math.pi / marcas;
      final largo = i.isEven ? u * 0.35 : u * 0.18;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - largo), c + dir * r, p);
    }
  }

  @override
  bool shouldRepaint(_Anillo old) =>
      old.giro != giro || old.color != color || old.u != u;
}

/// El medallón de la mesa: un círculo que se dibuja y otro fino adentro.
class _Medallon extends CustomPainter {
  final double progreso;
  final Color color;
  final double u;

  _Medallon({required this.progreso, required this.color, required this.u});

  @override
  void paint(Canvas canvas, Size size) {
    if (progreso <= 0) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - u * 0.2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progreso,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.1
        ..color = color,
    );
    canvas.drawCircle(
      c,
      r - u * 0.55,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.04
        ..color = color.withValues(alpha: 0.6 * progreso),
    );
  }

  @override
  bool shouldRepaint(_Medallon old) =>
      old.progreso != progreso || old.color != color || old.u != u;
}
