import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/image_viewer.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import '../detection/analysis_common.dart';

class _Pair {
  _Pair(this.drawing, this.photo);
  final Offset drawing; // drawing render px
  final Offset photo; // original photo px
}

/// Manual anchor alignment: the inspector clicks a point on the drawing, then the same
/// physical point on the photo. ≥ 4 pairs are sent to the backend, which estimates and
/// validates the homography and re-runs the inspection.
class AlignmentTool extends ConsumerStatefulWidget {
  const AlignmentTool({
    super.key,
    required this.version,
    required this.drawingUrl,
    required this.drawingSize,
    required this.renderScale,
    required this.photo,
    required this.registration,
    required this.onCancel,
  });
  final Version version;
  final String drawingUrl;
  final Size drawingSize;
  final double renderScale;
  final PhotoRef? photo;
  final Json registration;
  final VoidCallback onCancel;

  @override
  ConsumerState<AlignmentTool> createState() => _AlignmentToolState();
}

class _AlignmentToolState extends ConsumerState<AlignmentTool> {
  final List<_Pair> _pairs = [];
  Offset? _pending;
  bool _busy = false;

  List<Json> get _seedable => widget.registration.objs('correspondences').where((c) => c['drawing'] is List && c['photo'] is List && c['inlier'] != false).toList();

  void _onDrawingTap(Offset p) => setState(() => _pending = p);

  void _onPhotoTap(Offset p) {
    if (_pending == null) {
      showSnack(context, 'First click the point on the drawing, then the same point on the photo.', error: true);
      return;
    }
    setState(() {
      _pairs.add(_Pair(_pending!, p));
      _pending = null;
    });
  }

  void _seed() {
    final src = _seedable;
    if (src.isEmpty) return;
    // farthest-point sampling for a well-spread set of up to 8 anchors
    final pts = src.map((c) => (Offset((c['drawing'][0] as num).toDouble(), (c['drawing'][1] as num).toDouble()), Offset((c['photo'][0] as num).toDouble(), (c['photo'][1] as num).toDouble()))).toList();
    final chosen = <int>[0];
    while (chosen.length < math.min(8, pts.length)) {
      var best = -1;
      var bestD = -1.0;
      for (var i = 0; i < pts.length; i++) {
        if (chosen.contains(i)) continue;
        final d = chosen.map((j) => (pts[i].$1 - pts[j].$1).distance).reduce(math.min);
        if (d > bestD) {
          bestD = d;
          best = i;
        }
      }
      if (best < 0) break;
      chosen.add(best);
    }
    setState(() {
      _pairs
        ..clear()
        ..addAll(chosen.map((i) => _Pair(pts[i].$1 * widget.renderScale, pts[i].$2)));
      _pending = null;
    });
  }

  Future<void> _apply() async {
    final completed = !widget.version.editable;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apply manual alignment?'),
        content: SizedBox(
          width: 480,
          child: Text(
            completed
                ? 'Version ${widget.version.no} is ${widget.version.status} and will not be modified. A new version '
                    '"Re-run with manual alignment" is created with the same photo, drawing and expected list, and the full pipeline runs again '
                    'using your ${_pairs.length} anchor pairs. The backend validates the transform and rejects implausible alignments.'
                : 'The ${_pairs.length} anchor pairs are stored on version ${widget.version.no} and the pipeline starts. '
                    'The backend validates the transform and rejects implausible alignments.',
            style: const TextStyle(height: 1.5),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply & re-run')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final anchors = [
        for (var i = 0; i < _pairs.length; i++)
          {
            'drawing': [_pairs[i].drawing.dx / widget.renderScale, _pairs[i].drawing.dy / widget.renderScale],
            'photo': [_pairs[i].photo.dx, _pairs[i].photo.dy],
            'label': 'A${i + 1}',
          },
      ];
      final res = await ref.read(apiProvider).manualAlignment(widget.version.id, anchors);
      refreshInspectionData(ref, inspectionId: widget.version.inspectionId, versionId: widget.version.id);
      final job = res.objN('job');
      if (!mounted) return;
      if (job != null) {
        context.go('/console/live?job=${job.str('id')}');
      } else {
        showSnack(context, 'Alignment saved on version ${res.obj('version').integer('version_no')}.');
        widget.onCancel();
      }
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    final drawingMarkers = [
      for (var i = 0; i < _pairs.length; i++) ImgMarker(_pairs[i].drawing, 'A${i + 1}'),
      if (_pending != null) ImgMarker(_pending!, 'A${_pairs.length + 1}?', color: EE.uncertain),
    ];
    final photoMarkers = [for (var i = 0; i < _pairs.length; i++) ImgMarker(_pairs[i].photo, 'A${i + 1}')];
    final step = _pending == null ? 'Step 1 — click a distinctive point on the DRAWING (a device corner, label plate, terminal).' : 'Step 2 — click the SAME physical point on the PHOTO.';
    final visual = Panel(
      eyebrow: 'Manual alignment · ${_pairs.length} pair${_pairs.length == 1 ? '' : 's'}',
      title: step,
      accent: _pending == null ? EE.cyan : EE.uncertain,
      expand: true,
      padding: const EdgeInsets.all(EE.s3),
      child: LayoutBuilder(builder: (context, c) {
        final horizontal = c.maxWidth >= 700;
        final a = OverlayImageViewer(
          key: const ValueKey('align-drawing'),
          url: widget.drawingUrl,
          imageSize: widget.drawingSize,
          onImageTap: _onDrawingTap,
          markers: drawingMarkers,
          background: const Color(0xFFF7F8FA),
          caption: 'GA drawing — click to place',
        );
        final b = photo == null
            ? const EmptyState(title: 'No photo evidence for this version', icon: Icons.image_not_supported_outlined)
            : OverlayImageViewer(key: const ValueKey('align-photo'), url: photo.url, imageSize: photo.size, onImageTap: _onPhotoTap, markers: photoMarkers, caption: 'Photo — click the matching point');
        final children = [Expanded(child: a), SizedBox(width: horizontal ? 8 : 0, height: horizontal ? 0 : 8), Expanded(child: b)];
        return horizontal ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      }),
    );
    final side = Panel(
      eyebrow: 'Anchor pairs',
      title: _pairs.length >= 4 ? 'Ready to apply' : 'Need ${4 - _pairs.length} more',
      accent: _pairs.length >= 4 ? EE.pass : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
          'Use points spread across the cabinet (corners of the backplate or of distant devices). Four pairs define the planar homography; more pairs '
          'let RANSAC reject a mis-click. Zoom with the viewer controls for precision.',
          style: TextStyle(fontSize: 11.5, color: EE.textMuted, height: 1.45),
        ),
        const SizedBox(height: 10),
        if (_seedable.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _seed,
            icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
            label: Text('Start from ${_seedable.length} automatic correspondences'),
          ),
        const SizedBox(height: 8),
        for (var i = 0; i < _pairs.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(width: 34, child: Text('A${i + 1}', style: const TextStyle(fontFamily: EE.fontMono, fontWeight: FontWeight.w600, color: EE.cyan))),
              Expanded(
                child: Text(
                  'dwg (${(_pairs[i].drawing.dx / widget.renderScale).toStringAsFixed(1)}, ${(_pairs[i].drawing.dy / widget.renderScale).toStringAsFixed(1)}) pt\n'
                  'photo (${_pairs[i].photo.dx.toStringAsFixed(0)}, ${_pairs[i].photo.dy.toStringAsFixed(0)}) px',
                  style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textMuted),
                ),
              ),
              IconButton(tooltip: 'Remove pair', onPressed: () => setState(() => _pairs.removeAt(i)), icon: const Icon(Icons.close_rounded, size: 15)),
            ]),
          ),
        if (_pending != null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Waiting for the matching photo point…', style: TextStyle(fontSize: 11.5, color: EE.uncertain))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _busy ? null : widget.onCancel, child: const Text('Close tool')),
          OutlinedButton(onPressed: _busy || (_pairs.isEmpty && _pending == null) ? null : () => setState(() {
                _pairs.clear();
                _pending = null;
              }), child: const Text('Clear')),
          FilledButton.icon(
            onPressed: _busy || _pairs.length < 4 ? null : _apply,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(_busy ? 'Submitting…' : 'Apply alignment & re-run'),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          widget.version.editable
              ? 'This ${widget.version.status} version will run with your anchors.'
              : 'Version ${widget.version.no} stays unchanged; a new version is created and processed.',
          style: const TextStyle(fontSize: 11, color: EE.textDim),
        ),
      ]),
    );
    return AnalysisLayout(visual: visual, side: side, sideWidth: 360, narrowVisualHeight: 620);
  }
}
