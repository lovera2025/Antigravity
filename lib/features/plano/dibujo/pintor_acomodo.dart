import 'package:flutter/material.dart';

import '../estilos/estilo_plano.dart';
import '../modelo/armado_salon.dart';
import '../services/editar_armado.dart';
import '../services/manijas.dart';
import '../services/medir_salon.dart';
import 'pintor_plano.dart';

/// Lo que se dibuja encima del plano mientras se acomoda el salón: la mesa (o
/// el sector) que se tiene agarrado y la regla, con los metros a las mesas
/// más cercanas; y las manijas de lo elegido (6.1.0).
class PintorAcomodo extends CustomPainter {
  PintorAcomodo({
    required this.armado,
    required this.hoja,
    required this.tema,
    this.mesa,
    this.sector,
    this.vecinas = const [],
    this.pideM = 0,
    this.manijas,
    this.centroPlayon,
    this.playon,
    this.medidaSector,
    this.zoom,
  }) : super(repaint: zoom);

  final ArmadoSalon armado;
  final String hoja;
  final TemaPlano tema;

  /// La mesa elegida.
  final int? mesa;

  /// El sector elegido (su lugar en la lista del armado).
  final int? sector;

  /// Las manijas de lo elegido (el sector o el playón), en coordenadas del
  /// plano.
  final Map<Manija, Offset>? manijas;

  /// La manija del medio del playón elegido, para moverlo entero.
  final Offset? centroPlayon;

  /// El borde del playón elegido, que va resaltado.
  final ContornoPlano? playon;

  /// "12 × 6 m": lo que mide el sector elegido, escrito debajo de él.
  final String? medidaSector;

  /// El zoom del plano: las manijas y los rótulos miden lo mismo en la
  /// pantalla aunque se acerque la vista.
  final TransformationController? zoom;

  /// Las mesas más cercanas a la elegida, con su distancia.
  final List<({int numero, double metros})> vecinas;

  /// De centro a centro, lo que pide una mesa: más cerca que esto, la regla
  /// va en rojo.
  final double pideM;

  @override
  void paint(Canvas canvas, Size size) {
    final h = armado.hoja(hoja);
    if (h == null) return;
    final encuadre = EncuadrePlano.de(h.caja, size);

    // Un píxel de la pantalla, en este lienzo (que el zoom agranda).
    final px = 1 / (zoom?.value.getMaxScaleOnAxis() ?? 1.0);

    final c = playon;
    if (c != null && c.puntos.length >= 3) {
      final borde = Path()
        ..addPolygon([
          for (final p in c.puntos) encuadre.aPantalla(Offset(p.x, p.y)),
        ], true);
      canvas.drawPath(
        borde,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * px
          ..color = tema.resaltado,
      );
    }

    final i = sector;
    if (i != null && i >= 0 && i < armado.sectores.length) {
      final s = armado.sectores[i];
      if (s.hoja == hoja) {
        final a = encuadre.aPantalla(Offset(s.caja.x, s.caja.y));
        final b = encuadre.aPantalla(Offset(s.caja.derecha, s.caja.abajo));
        final caja = Rect.fromPoints(a, b);
        canvas.drawRect(
          caja.inflate(2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = tema.resaltado,
        );
        final medida = medidaSector;
        if (medida != null) {
          _rotulo(
            canvas,
            medida,
            Offset(caja.center.dx, caja.bottom + (ManijasPlano.ladoPx + 12) * px),
            px,
          );
        }
      }
    }

    for (final p in (manijas ?? const <Manija, Offset>{}).values) {
      final cuadro = Rect.fromCenter(
        center: encuadre.aPantalla(p),
        width: ManijasPlano.ladoPx * px,
        height: ManijasPlano.ladoPx * px,
      );
      canvas.drawRect(cuadro, Paint()..color = tema.fondo);
      canvas.drawRect(
        cuadro,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * px
          ..color = tema.resaltado,
      );
    }

    // La del medio del playón: un círculo con una cruz de flechas, la seña
    // de "mover".
    final mover = centroPlayon;
    if (mover != null) {
      final o = encuadre.aPantalla(mover);
      final r = ManijasPlano.ladoPx * px;
      canvas.drawCircle(o, r, Paint()..color = tema.fondo);
      final trazo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * px
        ..strokeCap = StrokeCap.round
        ..color = tema.resaltado;
      canvas.drawCircle(o, r, trazo);
      final l = r * 0.6;
      canvas.drawLine(o - Offset(l, 0), o + Offset(l, 0), trazo);
      canvas.drawLine(o - Offset(0, l), o + Offset(0, l), trazo);
    }

    final m = mesa == null ? null : armado.mesa(mesa!);
    if (m == null || m.hoja != hoja) return;
    final centro = encuadre.aPantalla(Offset(m.x, m.y));
    for (final (i, v) in vecinas.indexed) {
      final o = armado.mesa(v.numero);
      if (o == null) continue;
      final otro = encuadre.aPantalla(Offset(o.x, o.y));
      final justa = v.metros < pideM - MedirSalon.toleranciaM;
      final color = justa ? tema.conflicto : tema.resaltado;
      canvas.drawLine(
        centro,
        otro,
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: MedirSalon.metros(v.metros, decimales: 2),
          style: TextStyle(
            fontFamily: tema.fuente,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Cada medida va a otra altura de su línea: si las tres vecinas están
      // para el mismo lado, los carteles no quedan uno encima del otro.
      final medio = Offset.lerp(
        centro,
        otro,
        vecinas.length == 1 ? 0.5 : 0.72 - 0.22 * i,
      )!;
      final caja = Rect.fromCenter(
        center: medio,
        width: tp.width + 10,
        height: tp.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(caja, const Radius.circular(5)),
        Paint()..color = tema.fondo,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(caja, const Radius.circular(5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color,
      );
      tp.paint(canvas, medio - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.drawCircle(
      centro,
      armado.radio * encuadre.escala + 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = tema.resaltado,
    );
  }

  /// Un rótulo chico con fondo, centrado en [centro], del mismo tamaño en la
  /// pantalla con cualquier zoom.
  void _rotulo(Canvas canvas, String texto, Offset centro, double px) {
    final tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(
          fontFamily: tema.fuente,
          fontSize: 12 * px,
          fontWeight: FontWeight.w700,
          color: tema.resaltado,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final caja = Rect.fromCenter(
      center: centro,
      width: tp.width + 10 * px,
      height: tp.height + 4 * px,
    );
    final redondeo = RRect.fromRectAndRadius(caja, Radius.circular(5 * px));
    canvas.drawRRect(redondeo, Paint()..color = tema.fondo);
    canvas.drawRRect(
      redondeo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px
        ..color = tema.resaltado,
    );
    tp.paint(canvas, centro - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(PintorAcomodo old) =>
      !identical(old.armado, armado) ||
      old.hoja != hoja ||
      old.tema != tema ||
      old.mesa != mesa ||
      old.sector != sector ||
      old.pideM != pideM ||
      old.vecinas.length != vecinas.length ||
      !identical(old.vecinas, vecinas) ||
      old.manijas != manijas ||
      old.centroPlayon != centroPlayon ||
      !identical(old.playon, playon) ||
      old.medidaSector != medidaSector ||
      old.zoom != zoom;
}
