import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/image_viewer.dart';

/// Swipe comparison: image A is revealed left of a draggable divider over image B.
/// Both images are fitted into the same box, so images sharing a coordinate frame
/// (original / processed / annotated photos, crop pairs) line up pixel-for-pixel.
class SwipeCompare extends StatefulWidget {
  const SwipeCompare({super.key, required this.urlA, required this.urlB, required this.labelA, required this.labelB, this.aspect});
  final String urlA;
  final String urlB;
  final String labelA;
  final String labelB;
  final double? aspect;

  @override
  State<SwipeCompare> createState() => _SwipeCompareState();
}

class _SwipeCompareState extends State<SwipeCompare> {
  double _split = 0.5;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(EE.r2),
      child: Container(
        color: EE.bg0,
        child: LayoutBuilder(builder: (context, c) {
          // area actually covered by the fitted image, so the divider spans the image only
          var w = c.maxWidth, h = c.maxHeight;
          if (widget.aspect != null && widget.aspect! > 0) {
            if (w / h > widget.aspect!) {
              w = h * widget.aspect!;
            } else {
              h = w / widget.aspect!;
            }
          }
          return Center(
            child: SizedBox(
              width: w,
              height: h,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => setState(() => _split = (_split + d.delta.dx / w).clamp(0.0, 1.0)),
                onTapDown: (d) => setState(() => _split = (d.localPosition.dx / w).clamp(0.0, 1.0)),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.network(widget.urlB, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true),
                    ClipRect(
                      clipper: _LeftClipper(_split),
                      child: Image.network(widget.urlA, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true),
                    ),
                    Positioned(
                      left: (w * _split) - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: EE.cyan, child: const SizedBox()),
                    ),
                    Positioned(
                      left: (w * _split) - 16,
                      top: h / 2 - 16,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: EE.surface,
                          border: Border.all(color: EE.cyan, width: 1.5),
                          boxShadow: [BoxShadow(color: EE.cyan.withValues(alpha: 0.4), blurRadius: 12)],
                        ),
                        child: const Icon(Icons.compare_arrows_rounded, size: 16, color: EE.cyan),
                      ),
                    ),
                    Positioned(left: 8, top: 8, child: _Label('A · ${widget.labelA}')),
                    Positioned(right: 8, top: 8, child: _Label('B · ${widget.labelB}')),
                  ]),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.split);
  final double split;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * split, size.height);
  @override
  bool shouldReclip(covariant _LeftClipper old) => old.split != split;
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: EE.bg0.withValues(alpha: 0.82), borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: EE.line)),
        child: Text(text, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.textMuted)),
      );
}

/// Two independently zoomable viewers next to each other (stacked on narrow screens).
class SideBySideCompare extends StatelessWidget {
  const SideBySideCompare({super.key, required this.urlA, required this.urlB, required this.labelA, required this.labelB, this.sizeA, this.sizeB});
  final String urlA, urlB, labelA, labelB;
  final Size? sizeA, sizeB;

  @override
  Widget build(BuildContext context) {
    final a = OverlayImageViewer(url: urlA, imageSize: sizeA, caption: 'A · $labelA');
    final b = OverlayImageViewer(url: urlB, imageSize: sizeB, caption: 'B · $labelB');
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 640) {
        return Column(children: [Expanded(child: a), const SizedBox(height: 8), Expanded(child: b)]);
      }
      return Row(children: [Expanded(child: a), const SizedBox(width: 8), Expanded(child: b)]);
    });
  }
}
