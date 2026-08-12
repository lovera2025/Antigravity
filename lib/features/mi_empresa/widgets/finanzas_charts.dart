import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/utils/ar_time.dart';
import '../../common/utils/currency_extensions.dart';

import '../providers/finanzas_provider.dart';
 // For state dependencies if any

class DashedOverlayPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  DashedOverlayPainter({required this.color, this.strokeWidth = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    const dash = 3.0;
    const gap = 3.0;
    final y = size.height / 2;
    double x = 0;
    while (x < size.width) {
      final x2 = min(x + dash, size.width);
      canvas.drawLine(Offset(x, y), Offset(x2, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant DashedOverlayPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// Torta simple de egresos por categoría (donut).
class EgresosPiePainter extends CustomPainter {
  final List<double> amounts;
  final List<Color> colors;
  final Color holeColor;

  EgresosPiePainter({
    required this.amounts,
    required this.colors,
    required this.holeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = amounts.fold(0.0, (a, b) => a + b);
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 * 0.92;
    const holeFrac = 0.52;
    var start = -pi / 2;
    for (var i = 0; i < amounts.length; i++) {
      final sweep = 2 * pi * (amounts[i] / total);
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        paint,
      );
      start += sweep;
    }
    canvas.drawCircle(
      center,
      radius * holeFrac,
      Paint()
        ..color = holeColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant EgresosPiePainter oldDelegate) =>
      oldDelegate.amounts != amounts ||
      oldDelegate.colors != colors ||
      oldDelegate.holeColor != holeColor;
}

/// Gauge circular 0-100 con apertura inferior (270° de sweep).
///
/// Pinta un track gris y sobre él un arco de color (rojo <40, ámbar 40-70,
/// verde ≥70) proporcional al valor. Agrega dos ticks sutiles en 40 y 70
/// como referencia visual de umbrales.
class HealthScoreArcPainter extends CustomPainter {
  /// Valor renderizado (0-100). Puede ser animado desde 0 al valor real.
  final double score;
  /// Valor "objetivo" real (0-100) — define el color del arco aunque [score]
  /// esté a mitad de animación.
  final double targetScore;
  final Color trackColor;
  final Color tickColor;

  HealthScoreArcPainter({
    required this.score,
    required this.targetScore,
    required this.trackColor,
    required this.tickColor,
  });

  Color get _valueColor {
    if (targetScore < 40) return const Color(0xFFE74C3C);
    if (targetScore < 70) return const Color(0xFFF39C12);
    return const Color(0xFF00B894);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 * 0.86;
    final strokeW = radius * 0.16;

    const startAngle = 3 * pi / 4;
    const totalSweep = 3 * pi / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      totalSweep,
      false,
      track,
    );

    final pct = (score / 100).clamp(0.0, 1.0);
    final valueSweep = totalSweep * pct;
    if (valueSweep > 0.001) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final baseColor = _valueColor;
      final value = Paint()
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + totalSweep,
          colors: [
            baseColor.withValues(alpha: 0.55),
            baseColor,
          ],
          transform: const GradientRotation(3 * pi / 4),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      final shadow = Paint()
        ..color = baseColor.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      
      canvas.drawArc(rect, startAngle, valueSweep, false, shadow);
      canvas.drawArc(rect, startAngle, valueSweep, false, value);
    }

    final tick = Paint()
      ..color = tickColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final t in [40, 70]) {
      final a = startAngle + totalSweep * (t / 100);
      final inner = center + Offset(cos(a), sin(a)) * (radius - strokeW * 0.65);
      final outer = center + Offset(cos(a), sin(a)) * (radius + strokeW * 0.65);
      canvas.drawLine(inner, outer, tick);
    }
  }

  @override
  bool shouldRepaint(covariant HealthScoreArcPainter old) =>
      old.score != score ||
      old.targetScore != targetScore ||
      old.trackColor != trackColor ||
      old.tickColor != tickColor;
}

// ── Timeline del día (HOY) ───────────────────────────────────────────────────

class TimelineLayDot {
  final Offset center;
  final double displayR;
  final double hitR;
  final Color color;
  final String tooltip;
  final bool esIngreso;

  const TimelineLayDot({
    required this.center,
    required this.displayR,
    required this.hitR,
    required this.color,
    required this.tooltip,
    required this.esIngreso,
  });
}

class TimelineDiaLayout {
  final List<TimelineLayDot> dots;
  final double padH;
  final double drawW;
  final double gridTop;
  final double gridBottom;
  final double? nowX;
  final String nowLabel;

  const TimelineDiaLayout({
    required this.dots,
    required this.padH,
    required this.drawW,
    required this.gridTop,
    required this.gridBottom,
    required this.nowX,
    required this.nowLabel,
  });
}

TimelineDiaLayout layoutTimelineDia(FinanzasState state, Size size) {
  const green = Color(0xFF00B894);
  const red = Color(0xFFE74C3C);
  final w = size.width;
  const padH = 8.0;
  final drawW = (w - 2 * padH).clamp(4.0, double.infinity);
  const gridTop = 14.0;
  const gridBottom = 54.0;
  const yIng = 26.0;
  const yEg = 40.0;

  final hoyRef = ArTime.nowAr();
  final raw = <({bool ing, DateTime when, double monto, String concept})>[];
  for (final i in state.ingresos) {
    if (!ArTime.mismoDia(i.fecha, hoyRef)) continue;
    final concept = i.concepto.trim().isNotEmpty
        ? i.concepto
        : (i.nombreEvento.trim().isNotEmpty ? i.nombreEvento : 'Ingreso');
    raw.add((ing: true, when: i.fecha, monto: i.monto, concept: concept));
  }
  for (final e in state.egresos) {
    if (e.fecha == null || !ArTime.mismoDia(e.fecha!, hoyRef)) continue;
    final concept =
        e.proveedorVisible ?? (e.categoria ?? 'Egreso');
    raw.add((ing: false, when: e.fecha!, monto: e.monto, concept: concept));
  }

  var maxM = 1.0;
  for (final r in raw) {
    if (r.monto > maxM) maxM = r.monto;
  }

  final dots = <TimelineLayDot>[];
  for (final r in raw) {
    final ar = ArTime.toAr(r.when);
    final frac = (ar.hour + ar.minute / 60.0 + ar.second / 3600.0) / 24.0;
    final x = padH + frac.clamp(0.0, 1.0) * drawW;
    final displayR = 6.0 + (r.monto / maxM) * 2.0;
    final hitR = max(14.0, displayR + 2.0);
    final y = r.ing ? yIng : yEg;
    final tip =
        '${ArTime.formatHora(r.when)} · ${r.concept} · ${r.monto.toCurrency()}';
    dots.add(
      TimelineLayDot(
        center: Offset(x, y),
        displayR: displayR,
        hitR: hitR,
        color: r.ing ? green : red,
        tooltip: tip,
        esIngreso: r.ing,
      ),
    );
  }

  final nowAr = ArTime.nowAr();
  final nowFrac = (nowAr.hour + nowAr.minute / 60.0 + nowAr.second / 3600.0) / 24.0;
  final nx = padH + nowFrac.clamp(0.0, 1.0) * drawW;
  final nowLabel =
      '${nowAr.hour.toString().padLeft(2, '0')}:${nowAr.minute.toString().padLeft(2, '0')}';

  return TimelineDiaLayout(
    dots: dots,
    padH: padH,
    drawW: drawW,
    gridTop: gridTop,
    gridBottom: gridBottom,
    nowX: nx.isFinite ? nx : null,
    nowLabel: nowLabel,
  );
}

class TimelineDiaPainter extends CustomPainter {
  final TimelineDiaLayout layout;
  final bool isDark;
  final Color gold;

  TimelineDiaPainter({
    required this.layout,
    required this.isDark,
    required this.gold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final gridMinor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.07);
    final labelColor = isDark ? Colors.white38 : Colors.black45;

    for (var k = 0; k <= 8; k++) {
      final u = k * 3 / 24.0;
      final x = layout.padH + u * layout.drawW;
      final p = Paint()
        ..color = gridMinor
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, layout.gridTop), Offset(x, layout.gridBottom), p);
    }

    final hourLabels = ['00', '03', '06', '09', '12', '15', '18', '21', '24'];
    for (var k = 0; k < hourLabels.length; k++) {
      final u = k * 3 / 24.0;
      final x = layout.padH + u * layout.drawW;
      final tp = TextPainter(
        text: TextSpan(
          text: hourLabels[k],
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - tp.height - 4));
    }

    final nx = layout.nowX;
    if (nx != null) {
      final flag = Paint()
        ..color = gold.withValues(alpha: 0.85)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(nx, layout.gridTop), Offset(nx, layout.gridBottom), flag);

      final tNow = TextPainter(
        text: TextSpan(
          text: layout.nowLabel,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: gold,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var lx = nx - tNow.width / 2;
      lx = lx.clamp(2.0, w - tNow.width - 2);
      tNow.paint(canvas, Offset(lx, 2));
    }

    for (final d in layout.dots) {
      final shadow = Paint()
        ..color = d.color.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(d.center, d.displayR + 1.5, shadow);

      final fill = Paint()..color = d.color;
      canvas.drawCircle(d.center, d.displayR, fill);
      final ring = Paint()
        ..color = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(d.center, d.displayR, ring);
    }
  }

  @override
  bool shouldRepaint(covariant TimelineDiaPainter oldDelegate) =>
      oldDelegate.layout.dots.length != layout.dots.length ||
      oldDelegate.layout.nowX != layout.nowX ||
      oldDelegate.layout.nowLabel != layout.nowLabel ||
      oldDelegate.isDark != isDark ||
      oldDelegate.gold != gold;
}
