import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../services/contenido_bienvenida.dart';
import 'escena_totem.dart';
import 'fuentes_totem.dart';
import 'totem_estilo.dart';

/// Cristal: sobre el gradiente líquido, una tarjeta de vidrio esmerilado con la
/// foto, el título y el saludo. En la llegada la tarjeta se da vuelta y muestra
/// el nombre y la mesa.
class EscenaCristal extends EscenaEstilo {
  const EscenaCristal();

  static Widget _vidrio(double u, {required Widget child}) => ClipRRect(
        borderRadius: BorderRadius.circular(u * 1.2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: u * 0.6, sigmaY: u * 0.6),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: u * 1.4, vertical: u * 1.6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(u * 1.2),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.30),
                width: u * 0.05,
              ),
            ),
            child: child,
          ),
        ),
      );

  @override
  Widget espera(DatosEscena d) {
    final u = d.u;
    final titulo = partirTitulo(d.cfg.titulo);
    return Centrado(
      margen: EdgeInsets.symmetric(horizontal: u * 2.2, vertical: u * 2.4),
      child: _vidrio(
        u,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FotoEvento(
              imagen: d.foto,
              lado: u * 4.6,
              borde: d.color,
              grosor: u * 0.1,
            ),
            SizedBox(height: u * 0.9),
            if (titulo.chico != null)
              Text(
                titulo.chico!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: FuentesTotem.cartelera,
                  fontSize: u * 1.1,
                  letterSpacing: u * 0.28,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            Text(
              titulo.grande,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: FuentesTotem.cartelera,
                fontWeight: FontWeight.w700,
                fontSize: u * (titulo.chico == null ? 2.4 : 4),
                height: 1.05,
                color: Colors.white,
              ),
            ),
            if (d.cfg.subtitulo.isNotEmpty) ...[
              SizedBox(height: u * 0.4),
              Text(
                d.cfg.subtitulo.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: FuentesTotem.linea,
                  fontSize: u * 0.75,
                  letterSpacing: u * 0.35,
                  color: d.color,
                ),
              ),
            ],
            SizedBox(height: u * 0.9),
            Text(
              d.cfg.mensajeBienvenida,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: FuentesTotem.linea,
                fontSize: u * 1.2,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
            if (d.qrUrl != null) ...[
              SizedBox(height: u * 1.1),
              QrDelTotem(
                url: d.qrUrl!,
                texto: d.cfg.mensajeQr,
                u: u,
                marco: Colors.white.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget llegada(DatosEscena d, ContenidoBienvenida c) {
    final u = d.u;
    // La tarjeta se da vuelta: arranca de canto y queda de frente.
    final giro = d.tramo(0, 0.55, curva: Curves.easeOutBack);
    final con = conQuienDe(c);
    return Centrado(
      margen: EdgeInsets.symmetric(horizontal: u * 1.8, vertical: u * 2.6),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY((1 - giro.clamp(0.0, 1.0)) * math.pi / 2),
        child: _vidrio(
          u,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.saludo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: FuentesTotem.cartelera,
                  fontSize: u * 1.6,
                  letterSpacing: u * 0.05,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
              SizedBox(height: u * 0.4),
              for (final (i, n) in c.nombres.indexed) ...[
                if (i > 0) SizedBox(height: u * 0.2),
                Text(
                  n,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FuentesTotem.cartelera,
                    fontWeight: FontWeight.w700,
                    fontSize: u * (c.nombres.length > 1 ? 1.8 : 2.2),
                    height: 1.1,
                    color: Colors.white,
                  ),
                ),
              ],
              if (con != null) ...[
                SizedBox(height: u * 0.4),
                Text(
                  con,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FuentesTotem.linea,
                    fontSize: u * 0.95,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
              if (c.mesa != null) ...[
                SizedBox(height: u * 0.9),
                Text(
                  c.rotuloMesa.toUpperCase(),
                  style: TextStyle(
                    fontFamily: FuentesTotem.linea,
                    fontSize: u * 0.75,
                    letterSpacing: u * 0.3,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  c.mesa!,
                  style: TextStyle(
                    fontFamily: FuentesTotem.cartelera,
                    fontWeight: FontWeight.w700,
                    fontSize: u * (c.mesa!.length > 3 ? 3 : 4.2),
                    height: 1.0,
                    color: d.color,
                  ),
                ),
              ],
              sillasYMusica(c, d, familia: FuentesTotem.linea),
            ],
          ),
        ),
      ),
    );
  }
}
