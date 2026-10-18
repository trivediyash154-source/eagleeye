import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Faint drafting grid used behind console content: minor 24px, major 120px.
class GridBackground extends StatelessWidget {
  const GridBackground({super.key, this.opacity = 1});
  final double opacity;
  @override
  Widget build(BuildContext context) => IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _GridPainter(opacity))));
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.o);
  final double o;
  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()..color = EE.line.withValues(alpha: 0.18 * o);
    final major = Paint()..color = EE.line.withValues(alpha: 0.45 * o);
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), (x % 120 == 0) ? major : minor);
    }
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), (y % 120 == 0) ? major : minor);
    }
    final glow = RadialGradient(colors: [EE.cyan.withValues(alpha: 0.05 * o), Colors.transparent], radius: 0.8, center: const Alignment(0.8, -1.1));
    canvas.drawRect(Offset.zero & size, Paint()..shader = glow.createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.o != o;
}
