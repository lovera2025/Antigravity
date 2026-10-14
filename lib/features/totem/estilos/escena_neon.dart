import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/contenido_bienvenida.dart';
import 'escena_totem.dart';
import 'fuentes_totem.dart';
import 'totem_estilo.dart';

/// Neón: título en letra de tubo con una letra que titila cada tanto y el
/// saludo como cartel en cursiva de neón. En la llegada el cartel se prende
/// titilando, el nombre se enciende letra por letra y el círculo de la mesa se
/// dibuja con un fogonazo.
class EscenaNeon extends EscenaEstilo {
  const EscenaNeon();

  /// Dónde está el horizonte del fondo, de arriba hacia abajo (el `hz` del
  /// shader). Lo que se lee va arriba: sobre la línea brillante no se lee.
  static const horizonte = 0.67;

  /// El margen de abajo que deja el contenido arriba del horizonte. Con el
  /// plano abajo, el horizonte queda detrás del plano: alcanza un margen chico.
  static double _sobreElHorizonte(DatosEscena d) =>
      d.conPlano && !d.planoAlCostado
          ? d.u
          : d.alto * (1 - horizonte) + d.u;

  /// Si la letra que titila está apagada en este instante: dos parpadeos
  /// cortos cada cuatro segundos.
  static bool apagada(double reloj) {
    final t = reloj % 4;
    return (t > 0.30 && t < 0.36) || (t > 0.44 && t < 0.48);
  }

  @override
  Widget espera(DatosEscena d) {
    final u = d.u;
    final titulo = partirTitulo(d.cfg.titulo);
    final apagar = apagada(d.reloj);
    final grande = titulo.grande.characters.toList();
    final tubo = TextStyle(
      fontFamily: FuentesTotem.tubo,
      fontSize: u * (titulo.chico == null ? 2.6 : 4.4),
      height: 1.05,
      color: Colors.white,
      shadows: brilloNeon(d.color, u),
    );
    final arriba = Centrado(
      margen: EdgeInsets.fromLTRB(u * 2, u * 2.2, u * 2, _sobreElHorizonte(d)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FotoEvento(
            imagen: d.foto,
            lado: u * 5.2,
            borde: d.color,
            grosor: u * 0.12,
          ),
          SizedBox(height: u * 1.2),
          if (titulo.chico != null)
            Text(
              titulo.chico!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: FuentesTotem.tubo,
                fontSize: u * 1.15,
                letterSpacing: u * 0.3,
                color: Colors.white.withValues(alpha: 0.85),
                shadows: brilloNeon(d.segundo, u, fuerza: 0.6),
              ),
            ),
          Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < grande.length; i++)
                  TextSpan(
                    text: grande[i],
                    // Una letra titila cada tanto, como un tubo flojo.
                    style: i == math.min(1, grande.length - 1) && apagar
                        ? tubo.copyWith(
                            color: Colors.white.withValues(alpha: 0.25),
                            shadows: const [],
                          )
                        : tubo,
                  ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          if (d.cfg.subtitulo.isNotEmpty) ...[
            SizedBox(height: u * 0.5),
            Text(
              d.cfg.subtitulo.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: FuentesTotem.linea,
                fontSize: u * 0.8,
                letterSpacing: u * 0.4,
                color: d.color,
              ),
            ),
          ],
          SizedBox(height: u * 0.9),
          Text(
            d.cfg.mensajeBienvenida,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: FuentesTotem.cartel,
              fontSize: u * 2.6,
              color: Colors.white,
              shadows: brilloNeon(d.segundo, u),
            ),
          ),
        ],
      ),
    );
    final qr = d.qrUrl;
    if (qr == null) return arriba;
    // El QR va abajo, sobre el piso de la grilla.
    return Stack(
      fit: StackFit.expand,
      children: [
        arriba,
        Positioned(
          left: 0,
          right: 0,
          top: d.alto * horizonte + u,
          bottom: u * 1.2,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: QrDelTotem(
                url: qr,
                texto: d.cfg.mensajeQr,
                u: u,
                marco: d.color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget llegada(DatosEscena d, ContenidoBienvenida c) {
    final u = d.u;
    // El cartel se prende titilando en el primer tramo de la entrada.
    final prende = d.tramo(0, 0.3);
    final titila = prende < 1 && (prende * 9).floor().isOdd;
    final nombre = d.tramo(0.3, 0.75, curva: Curves.linear);
    final circulo = d.tramo(0.55, 0.95);
    final con = conQuienDe(c);
    return Centrado(
      margen: EdgeInsets.fromLTRB(u * 1.6, u * 2.4, u * 1.6, _sobreElHorizonte(d)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: titila ? 0.2 : prende,
            child: Text(
              c.saludo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: FuentesTotem.cartel,
                fontSize: u * 3.2,
                color: Colors.white,
                shadows: brilloNeon(d.segundo, u),
              ),
            ),
          ),
          SizedBox(height: u * 0.5),
          for (final (i, n) in c.nombres.indexed) ...[
            if (i > 0) SizedBox(height: u * 0.3),
            letraPorLetra(
              n,
              TextStyle(
                fontFamily: FuentesTotem.tubo,
                fontSize: u * (c.nombres.length > 1 ? 1.7 : 2.1),
                height: 1.1,
                color: Colors.white,
                shadows: brilloNeon(d.color, u, fuerza: 0.9),
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
                  fontFamily: FuentesTotem.linea,
                  fontSize: u * 1.0,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
          if (c.mesa != null) ...[
            SizedBox(height: u * 0.8),
            SizedBox(
              width: u * 7.5,
              height: u * 7.5,
              child: CustomPaint(
                painter: _CirculoNeon(
                  progreso: circulo,
                  color: d.color,
                  u: u,
                ),
                child: Center(
                  child: Opacity(
                    opacity: circulo,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.rotuloMesa.toUpperCase(),
                          style: TextStyle(
                            fontFamily: FuentesTotem.linea,
                            fontSize: u * 0.7,
                            letterSpacing: u * 0.2,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        Text(
                          c.mesa!,
                          style: TextStyle(
                            fontFamily: FuentesTotem.tubo,
                            fontSize: u * (c.mesa!.length > 3 ? 1.9 : 2.8),
                            height: 1.05,
                            color: Colors.white,
                            shadows: brilloNeon(d.color, u, fuerza: 0.8),
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
            child: sillasYMusica(c, d, familia: FuentesTotem.linea),
          ),
        ],
      ),
    );
  }
}

/// El círculo de la mesa, que se dibuja de a poco con su brillo.
class _CirculoNeon extends CustomPainter {
  final double progreso;
  final Color color;
  final double u;

  _CirculoNeon({required this.progreso, required this.color, required this.u});

  @override
  void paint(Canvas canvas, Size size) {
    if (progreso <= 0) return;
    final r = size.shortestSide / 2 - u * 0.4;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final barrido = 2 * math.pi * progreso;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      barrido,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.35
        ..color = color.withValues(alpha: 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.3),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      barrido,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.12
        ..color = Color.lerp(color, Colors.white, 0.45)!,
    );
  }

  @override
  bool shouldRepaint(_CirculoNeon old) =>
      old.progreso != progreso || old.color != color || old.u != u;
}
