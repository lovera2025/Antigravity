import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/contenido_bienvenida.dart';
import 'escena_totem.dart';
import 'fuentes_totem.dart';
import 'totem_estilo.dart';

/// Póster: la foto del evento a pantalla completa, con zoom lento y oscurecida
/// abajo para letras grandes; sin foto, el fondo de luces de fiesta. En la
/// llegada el nombre sube desde una máscara y la mesa entra en una franja
/// inclinada del color del evento.
class EscenaPoster extends EscenaEstilo {
  const EscenaPoster();

  @override
  List<Widget> capasDeFondo(DatosEscena d) {
    final url = d.cfg.imagenUrl;
    return [
      if (url != null)
        Opacity(
          opacity: 1 - 0.45 * d.entrada,
          child: Transform.scale(
            // Zoom lento, de ida y vuelta.
            scale: 1.04 + 0.04 * math.sin(d.reloj * 0.1),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      // Oscurecido abajo, para las letras.
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.35, 1],
            colors: [Colors.transparent, Color(0xE6050308)],
          ),
        ),
      ),
    ];
  }

  /// Lo de abajo a la izquierda, que nunca se corta: si no entra, se achica.
  static Widget _abajo(DatosEscena d, Widget child) {
    final u = d.u;
    return Padding(
      padding: EdgeInsets.fromLTRB(u * 1.6, u * 2, u * 1.6, u * 3.2),
      child: LayoutBuilder(
        builder: (context, c) => Align(
          alignment: Alignment.bottomLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget espera(DatosEscena d) {
    final u = d.u;
    final titulo = partirTitulo(d.cfg.titulo);
    return _abajo(
      d,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.qrUrl != null) ...[
            Align(
              alignment: Alignment.centerRight,
              child: QrDelTotem(
                url: d.qrUrl!,
                texto: d.cfg.mensajeQr,
                u: u * 0.85,
                marco: d.color,
              ),
            ),
            SizedBox(height: u * 1.5),
          ],
          if (titulo.chico != null)
            Text(
              titulo.chico!,
              style: TextStyle(
                fontFamily: FuentesTotem.cartelera,
                fontSize: u * 1.4,
                letterSpacing: u * 0.25,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          Text(
            titulo.grande,
            style: TextStyle(
              fontFamily: FuentesTotem.cartelera,
              fontWeight: FontWeight.w700,
              fontSize: u * (titulo.chico == null ? 3.4 : 6.6),
              height: 0.95,
              color: Colors.white,
            ),
          ),
          if (d.cfg.subtitulo.isNotEmpty) ...[
            SizedBox(height: u * 0.5),
            Container(
              color: d.color,
              padding: EdgeInsets.symmetric(
                horizontal: u * 0.6,
                vertical: u * 0.2,
              ),
              child: Text(
                d.cfg.subtitulo.toUpperCase(),
                style: TextStyle(
                  fontFamily: FuentesTotem.cartelera,
                  fontSize: u * 0.85,
                  letterSpacing: u * 0.3,
                  color: const Color(0xFF111111),
                ),
              ),
            ),
          ],
          SizedBox(height: u * 0.7),
          Text(
            d.cfg.mensajeBienvenida,
            style: TextStyle(
              fontFamily: FuentesTotem.cartelera,
              fontSize: u * 1.5,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget llegada(DatosEscena d, ContenidoBienvenida c) {
    final u = d.u;
    final sube = d.tramo(0.1, 0.55, curva: Curves.easeOutCubic);
    final franja = d.tramo(0.45, 0.85, curva: Curves.easeOutCubic);
    final con = conQuienDe(c);
    return _abajo(
      d,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.saludo,
            style: TextStyle(
              fontFamily: FuentesTotem.cartelera,
              fontSize: u * 1.5,
              letterSpacing: u * 0.12,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          for (final n in c.nombres)
            ClipRect(
              child: FractionalTranslation(
                // El nombre sube desde abajo de una máscara.
                translation: Offset(0, 1 - sube),
                child: Text(
                  n,
                  style: TextStyle(
                    fontFamily: FuentesTotem.cartelera,
                    fontWeight: FontWeight.w700,
                    fontSize: u * (c.nombres.length > 1 ? 2.3 : 2.9),
                    height: 1.0,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (con != null) ...[
            SizedBox(height: u * 0.3),
            Opacity(
              opacity: sube,
              child: Text(
                con,
                style: TextStyle(
                  fontFamily: FuentesTotem.linea,
                  fontSize: u * 1.0,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
            ),
          ],
          if (c.mesa != null) ...[
            SizedBox(height: u * 0.9),
            // La franja inclinada entra desde la izquierda.
            ClipRect(
              child: FractionalTranslation(
                translation: Offset(-1.2 * (1 - franja), 0),
                child: Transform(
                  transform: Matrix4.skewY(-0.08),
                  child: Container(
                    color: d.color,
                    padding: EdgeInsets.fromLTRB(u * 0.7, u * 0.2, u * 1.2, u * 0.25),
                    child: Text(
                      '${c.rotuloMesa.toUpperCase()} ${c.mesa}',
                      style: TextStyle(
                        fontFamily: FuentesTotem.cartelera,
                        fontWeight: FontWeight.w700,
                        fontSize: u * 2.4,
                        height: 1.05,
                        color: const Color(0xFF111111),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          Opacity(
            opacity: d.tramo(0.7, 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [sillasYMusica(c, d, familia: FuentesTotem.linea)],
            ),
          ),
        ],
      ),
    );
  }
}
