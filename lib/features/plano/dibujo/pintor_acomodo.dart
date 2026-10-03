import 'package:flutter/material.dart';

import '../estilos/estilo_plano.dart';
import '../modelo/armado_salon.dart';
import '../services/medir_salon.dart';
import 'pintor_plano.dart';

/// Lo que se dibuja encima del plano mientras se acomoda el salón: la mesa (o
/// el sector) que se tiene agarrado y la regla, con los metros a las mesas
/// más cercanas.
class PintorAcomodo extends CustomPainter {
  PintorAcomodo({
    required this.armado,
    required this.hoja,
    required this.tema,
    this.mesa,
    this.sector,
    this.vecinas = const [],
    this.pideM = 0,
  });

  final ArmadoSalon armado;
  final String hoja;
  final TemaPlano tema;

  /// La mesa elegida.
  final int? mesa;

  /// El sector elegido (su lugar en la lista del armado).
  final int? sector;

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

    final i = sector;
    if (i != null && i >= 0 && i < armado.sectores.length) {
      final s = armado.sectores[i];
      if (s.hoja == hoja) {
        final a = encuadre.aPantalla(Offset(s.caja.x, s.caja.y));
        final b = encuadre.aPantalla(Offset(s.caja.derecha, s.caja.abajo));
        canvas.drawRect(
          Rect.fromPoints(a, b).inflate(2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = tema.resaltado,
        );
      }
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

  @override
  bool shouldRepaint(PintorAcomodo old) =>
      !identical(old.armado, armado) ||
      old.hoja != hoja ||
      old.tema != tema ||
      old.mesa != mesa ||
      old.sector != sector ||
      old.pideM != pideM ||
      old.vecinas.length != vecinas.length ||
      !identical(old.vecinas, vecinas);
}
