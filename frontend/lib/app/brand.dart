import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// The EAGLE EYE mark: a downward chevron "beak" over a scanning aperture.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _MarkPainter());
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final grad = const LinearGradient(colors: [EE.ice, EE.cyan, EE.violet], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(Offset.zero & s);
    final p = Path()
      ..moveTo(w * 0.06, h * 0.18)
      ..lineTo(w * 0.94, h * 0.18)
      ..lineTo(w * 0.5, h * 0.92)
      ..close();
    canvas.drawPath(p, Paint()..shader = grad);
    final cut = Path()
      ..moveTo(w * 0.30, h * 0.30)
      ..lineTo(w * 0.70, h * 0.30)
      ..lineTo(w * 0.5, h * 0.64)
      ..close();
    canvas.drawPath(cut, Paint()..color = EE.bg1);
    canvas.drawCircle(Offset(w * 0.5, h * 0.40), w * 0.065, Paint()..color = EE.cyan);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.subtitle = 'Cabinet inspection console'});
  final String subtitle;
  @override
  Widget build(BuildContext context) => Row(children: [
        const BrandMark(size: 28),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('EAGLE EYE', style: TextStyle(fontFamily: EE.fontDisplay, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 2.4, color: EE.text)),
          Text(subtitle, style: const TextStyle(fontSize: 10.5, color: EE.textDim, letterSpacing: 0.2)),
        ]),
      ]);
}
