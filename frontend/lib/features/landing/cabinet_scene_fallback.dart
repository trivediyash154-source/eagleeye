import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Static technical composition shown when WebGL is unavailable: an isometric line drawing of
/// the cabinet with inspection markers and a scan line. Deliberately calm — no animation.
class CabinetSceneFallback extends StatelessWidget {
  const CabinetSceneFallback({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _FallbackPainter(), child: const SizedBox.expand());
}

class _FallbackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / 5.2, size.height / 4.4);
    final o = Offset(size.width * 0.52, size.height * 0.5);
    Offset p(double x, double y, double z) => o + Offset((x - z * 0.55) * s, (-y + z * 0.32) * s);
    final line = Paint()
      ..color = EE.ice.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final strong = Paint()
      ..color = EE.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    void quad(List<Offset> pts, Paint paint, [Color? fill]) {
      final path = Path()..addPolygon(pts, true);
      if (fill != null) canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(path, paint);
    }

    // enclosure
    quad([p(-2.2, 1.7, 0), p(2.2, 1.7, 0), p(2.2, -1.7, 0), p(-2.2, -1.7, 0)], line, EE.surface.withValues(alpha: 0.6));
    quad([p(-2.2, 1.7, 0), p(-2.2, 1.7, 0.9), p(-2.2, -1.7, 0.9), p(-2.2, -1.7, 0)], line, EE.surfaceHi.withValues(alpha: 0.4));
    quad([p(-2.2, 1.7, 0), p(2.2, 1.7, 0), p(2.2, 1.7, 0.9), p(-2.2, 1.7, 0.9)], line, EE.surfaceHi.withValues(alpha: 0.3));
    // rails and devices
    for (final y in [0.95, -0.05, -0.98]) {
      quad([p(-1.9, y + 0.08, 0.05), p(1.6, y + 0.08, 0.05), p(1.6, y - 0.08, 0.05), p(-1.9, y - 0.08, 0.05)], line);
    }
    final verdicts = [EE.pass, EE.pass, EE.pass, EE.pass, EE.fail, EE.pass];
    var x = -1.75;
    for (var i = 0; i < 6; i++) {
      final w = i == 0 ? 0.44 : 0.17;
      if (i != 4) quad([p(x, 1.26, 0.35), p(x + w, 1.26, 0.35), p(x + w, 0.64, 0.35), p(x, 0.64, 0.35)], line, EE.titanium.withValues(alpha: 0.7));
      quad([p(x - 0.03, 1.29, 0.4), p(x + w + 0.03, 1.29, 0.4), p(x + w + 0.03, 0.61, 0.4), p(x - 0.03, 0.61, 0.4)], Paint()
        ..color = verdicts[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4);
      x += w + 0.16;
    }
    for (var i = 0; i < 3; i++) {
      final cx = -0.42 + i * 0.44;
      quad([p(cx - 0.15, 0.21, 0.35), p(cx + 0.15, 0.21, 0.35), p(cx + 0.15, -0.31, 0.35), p(cx - 0.15, -0.31, 0.35)], line, EE.titanium.withValues(alpha: 0.6));
    }
    for (var i = 0; i < 12; i++) {
      final cx = -1.7 + i * 0.13;
      quad([p(cx - 0.05, -0.8, 0.3), p(cx + 0.05, -0.8, 0.3), p(cx + 0.05, -1.2, 0.3), p(cx - 0.05, -1.2, 0.3)], line);
    }
    quad([p(-1.37, -0.62, 0.35), p(-1.24, -0.62, 0.35), p(-1.24, -0.7, 0.35), p(-1.37, -0.7, 0.35)], Paint()
      ..color = EE.fail
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
    // scan line
    final sy = 0.2;
    canvas.drawLine(p(-2.3, sy, 0.5), p(2.3, sy, 0.5), strong);
    canvas.drawLine(p(-2.3, sy, 0.5), p(2.3, sy, 0.5), Paint()
      ..color = EE.cyan.withValues(alpha: 0.25)
      ..strokeWidth = 10
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    final tp = TextPainter(
      text: const TextSpan(text: 'STATIC PREVIEW · WebGL unavailable', style: TextStyle(fontFamily: EE.fontMono, fontSize: 10, letterSpacing: 1.4, color: EE.textDim)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width - 16, size.height - 24));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
