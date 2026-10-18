import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// An overlay drawn in IMAGE pixel coordinates (original frame).
class ImgOverlay {
  const ImgOverlay({required this.id, this.box, this.quad, required this.color, this.label, this.dashed = false, this.fillAlpha = 0.0, this.group = 'default'});
  final String id;
  final List<double>? box; // x0,y0,x1,y1
  final List<List<double>>? quad; // polygon points
  final Color color;
  final String? label;
  final bool dashed;
  final double fillAlpha;
  final String group;

  Rect? get rect {
    if (box != null && box!.length == 4) return Rect.fromLTRB(box![0], box![1], box![2], box![3]);
    if (quad != null && quad!.isNotEmpty) {
      final xs = quad!.map((p) => p[0]);
      final ys = quad!.map((p) => p[1]);
      return Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max));
    }
    return null;
  }
}

class ImgMarker {
  const ImgMarker(this.point, this.label, {this.color = EE.cyan});
  final Offset point;
  final String label;
  final Color color;
}

/// Zoomable, pannable image with precise overlays. Stroke widths and labels are kept at a
/// constant on-screen size regardless of zoom.
class OverlayImageViewer extends StatefulWidget {
  const OverlayImageViewer({
    super.key,
    required this.url,
    this.imageSize,
    this.overlays = const [],
    this.selectedId,
    this.onSelect,
    this.onImageTap,
    this.markers = const [],
    this.overlayOpacity = 1.0,
    this.showLabels = true,
    this.toolbar = true,
    this.background = EE.bg0,
    this.caption,
  });

  final String url;
  final Size? imageSize;
  final List<ImgOverlay> overlays;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final ValueChanged<Offset>? onImageTap;
  final List<ImgMarker> markers;
  final double overlayOpacity;
  final bool showLabels;
  final bool toolbar;
  final Color background;
  final String? caption;

  @override
  State<OverlayImageViewer> createState() => _OverlayImageViewerState();
}

class _OverlayImageViewerState extends State<OverlayImageViewer> with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: EE.slow);
  Animation<Matrix4>? _matrixAnim;
  Size? _imgSize;
  Size? _viewport;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Object? _error;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _imgSize = widget.imageSize;
    _anim.addListener(() {
      if (_matrixAnim != null) _tc.value = _matrixAnim!.value;
    });
    _resolve();
  }

  @override
  void didUpdateWidget(covariant OverlayImageViewer old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _imgSize = widget.imageSize;
      _fitted = false;
      _error = null;
      _resolve();
    }
    if (old.selectedId != widget.selectedId && widget.selectedId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => focusOn(widget.selectedId!));
    }
  }

  void _resolve() {
    if (_listener != null) _stream?.removeListener(_listener!);
    final provider = NetworkImage(widget.url);
    _stream = provider.resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _imgSize ??= Size(info.image.width.toDouble(), info.image.height.toDouble()));
    }, onError: (e, _) {
      if (mounted) setState(() => _error = e);
    });
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _anim.dispose();
    _tc.dispose();
    super.dispose();
  }

  Matrix4 _fitMatrix() {
    final v = _viewport!, i = _imgSize!;
    final s = math.min(v.width / i.width, v.height / i.height);
    final dx = (v.width - i.width * s) / 2, dy = (v.height - i.height * s) / 2;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  void _animateTo(Matrix4 m) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _tc.value = m;
      return;
    }
    _matrixAnim = Matrix4Tween(begin: _tc.value, end: m).animate(CurvedAnimation(parent: _anim, curve: EE.curve));
    _anim.forward(from: 0);
  }

  void fit() {
    if (_viewport == null || _imgSize == null) return;
    _animateTo(_fitMatrix());
  }

  void zoom(double factor) {
    if (_viewport == null) return;
    final c = Offset(_viewport!.width / 2, _viewport!.height / 2);
    final m = _tc.value.clone()
      ..translateByDouble(0, 0, 0, 1);
    final s = m.getMaxScaleOnAxis();
    final target = (s * factor).clamp(0.02, 12.0) / s;
    final scene = _tc.toScene(c);
    m
      ..translateByDouble(scene.dx, scene.dy, 0, 1)
      ..scaleByDouble(target, target, 1, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
    _animateTo(m);
  }

  void focusOn(String id) {
    final o = widget.overlays.where((o) => o.id == id).firstOrNull;
    final r = o?.rect;
    if (r == null || _viewport == null || _imgSize == null) return;
    final v = _viewport!;
    final pad = math.max(r.width, r.height) * 1.6 + 40;
    final s = math.min(math.min(v.width / (r.width + pad), v.height / (r.height + pad)), 6.0);
    final m = Matrix4.identity()
      ..translateByDouble(v.width / 2 - r.center.dx * s, v.height / 2 - r.center.dy * s, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
    _animateTo(m);
  }

  void _onTapUp(TapUpDetails d) {
    final p = d.localPosition; // image coordinates (child is image-sized)
    if (widget.onImageTap != null) {
      widget.onImageTap!(p);
      return;
    }
    if (widget.onSelect == null) return;
    ImgOverlay? best;
    double bestArea = double.infinity;
    for (final o in widget.overlays) {
      final r = o.rect;
      if (r == null) continue;
      final hit = r.inflate(6 / _tc.value.getMaxScaleOnAxis());
      if (hit.contains(p) && r.width * r.height < bestArea) {
        best = o;
        bestArea = r.width * r.height;
      }
    }
    if (best != null) widget.onSelect!(best.id);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(EE.r2),
      child: Container(
        color: widget.background,
        child: LayoutBuilder(builder: (context, c) {
          _viewport = Size(c.maxWidth, c.maxHeight);
          if (_error != null) {
            return Center(child: Text('Image could not be loaded: $_error', style: const TextStyle(color: EE.fail, fontSize: 12)));
          }
          if (_imgSize == null) return const Center(child: SizedBox(width: 90, child: LinearProgressIndicator(minHeight: 2)));
          if (!_fitted) {
            _fitted = true;
            _tc.value = _fitMatrix();
          }
          final img = _imgSize!;
          return Stack(children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _tc,
                constrained: false,
                minScale: 0.02,
                maxScale: 12,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: GestureDetector(
                  onTapUp: _onTapUp,
                  child: SizedBox(
                    width: img.width,
                    height: img.height,
                    child: Stack(children: [
                      Positioned.fill(child: Image.network(widget.url, fit: BoxFit.fill, filterQuality: FilterQuality.medium, gaplessPlayback: true)),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: widget.overlayOpacity.clamp(0.0, 1.0),
                            child: CustomPaint(
                              painter: _OverlayPainter(widget.overlays, widget.selectedId, _tc, widget.showLabels, widget.markers),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            if (widget.toolbar)
              Positioned(
                right: 10,
                top: 10,
                child: _Toolbar(onFit: fit, onIn: () => zoom(1.5), onOut: () => zoom(1 / 1.5), onFocus: widget.selectedId == null ? null : () => focusOn(widget.selectedId!)),
              ),
            if (widget.caption != null)
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: EE.bg0.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: EE.line)),
                  child: Text(widget.caption!, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.textMuted)),
                ),
              ),
          ]);
        }),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.onFit, required this.onIn, required this.onOut, this.onFocus});
  final VoidCallback onFit, onIn, onOut;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    Widget b(IconData i, String tip, VoidCallback? f) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: f,
            child: SizedBox(width: 32, height: 32, child: Icon(i, size: 16, color: f == null ? EE.textDim : EE.text)),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: EE.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.lineHi)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        b(Icons.add_rounded, 'Zoom in', onIn),
        b(Icons.remove_rounded, 'Zoom out', onOut),
        b(Icons.fit_screen_rounded, 'Fit to screen / reset view', onFit),
        b(Icons.center_focus_strong_rounded, 'Focus selected finding', onFocus),
      ]),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.overlays, this.selected, this.tc, this.labels, this.markers) : super(repaint: tc);
  final List<ImgOverlay> overlays;
  final String? selected;
  final TransformationController tc;
  final bool labels;
  final List<ImgMarker> markers;

  @override
  void paint(Canvas canvas, Size size) {
    final s = tc.value.getMaxScaleOnAxis();
    final px = 1 / (s == 0 ? 1 : s);
    final ordered = [...overlays.where((o) => o.id != selected), ...overlays.where((o) => o.id == selected)];
    for (final o in ordered) {
      final sel = o.id == selected;
      final stroke = Paint()
        ..color = o.color.withValues(alpha: selected == null || sel ? 1 : 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (sel ? 3.0 : 1.6) * px;
      Path path;
      if (o.quad != null && o.quad!.length >= 3) {
        path = Path()..addPolygon(o.quad!.map((p) => Offset(p[0], p[1])).toList(), true);
      } else if (o.rect != null) {
        path = Path()..addRect(o.rect!);
      } else {
        continue;
      }
      if (o.fillAlpha > 0 || sel) {
        canvas.drawPath(path, Paint()..color = o.color.withValues(alpha: sel ? 0.14 : o.fillAlpha));
      }
      if (sel) {
        canvas.drawPath(path, Paint()
          ..color = o.color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9 * px
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * px));
      }
      if (o.dashed) {
        _dashed(canvas, path, stroke, 7 * px, 5 * px);
      } else {
        canvas.drawPath(path, stroke);
      }
      if (labels && o.label != null && (sel || s > 0.18)) {
        final r = o.rect!;
        final tp = TextPainter(
          text: TextSpan(text: o.label, style: TextStyle(fontFamily: EE.fontMono, fontSize: 11 * px, color: const Color(0xFF041018), fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout();
        final bg = Rect.fromLTWH(r.left, r.top - tp.height - 4 * px, tp.width + 8 * px, tp.height + 4 * px);
        canvas.drawRect(bg, Paint()..color = o.color.withValues(alpha: selected == null || sel ? 0.95 : 0.6));
        tp.paint(canvas, Offset(bg.left + 4 * px, bg.top + 2 * px));
      }
    }
    for (final m in markers) {
      final p = Paint()
        ..color = m.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * px;
      canvas.drawCircle(m.point, 9 * px, p);
      canvas.drawLine(m.point - Offset(14 * px, 0), m.point + Offset(14 * px, 0), p);
      canvas.drawLine(m.point - Offset(0, 14 * px), m.point + Offset(0, 14 * px), p);
      final tp = TextPainter(text: TextSpan(text: m.label, style: TextStyle(fontFamily: EE.fontMono, fontSize: 12 * px, color: m.color, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, m.point + Offset(12 * px, -tp.height - 6 * px));
    }
  }

  void _dashed(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => old.overlays != overlays || old.selected != selected || old.labels != labels || old.markers != markers;
}
