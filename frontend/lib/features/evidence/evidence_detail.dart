import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/download.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/image_viewer.dart';
import '../../core/widgets/panel.dart';
import '../review/dataset_toggle.dart';
import 'evidence_compare.dart';
import 'evidence_kinds.dart';

Future<void> showEvidenceDetail(BuildContext context, Evidence e) => showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => EvidenceDetailDialog(evidence: e),
    );

enum _Mode { inspect, swipe, sideBySide }

class EvidenceDetailDialog extends ConsumerStatefulWidget {
  const EvidenceDetailDialog({super.key, required this.evidence});
  final Evidence evidence;

  @override
  ConsumerState<EvidenceDetailDialog> createState() => _EvidenceDetailDialogState();
}

class _EvidenceDetailDialogState extends ConsumerState<EvidenceDetailDialog> {
  _Mode _mode = _Mode.inspect;
  List<Evidence> _candidates = const [];
  Evidence? _other;
  bool _loadingCandidates = true;
  String? _candidateError;

  Evidence get e => widget.evidence;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  /// Comparison candidates: other evidence of the same finding / version, and the same
  /// evidence kind in other versions of the inspection.
  Future<void> _loadCandidates() async {
    final api = ref.read(apiProvider);
    try {
      final sameVersion = await api.evidence(versionId: e.versionId, pageSize: 200);
      final sameKind = await api.evidence(inspectionId: e.inspectionId, kind: e.kind, pageSize: 100);
      final seen = <String>{e.id};
      final all = <Evidence>[];
      for (final x in [...sameVersion.items, ...sameKind.items]) {
        if (x.url == null || !seen.add(x.id)) continue;
        // a crop is only comparable with crops of the same finding
        if (e.findingId != null && x.findingId != null && x.findingId != e.findingId && x.kind != e.kind) continue;
        if (e.findingId == null && x.findingId != null) continue;
        all.add(x);
      }
      final pref = preferredPartner(e.kind);
      all.sort((a, b) {
        int score(Evidence x) {
          if (x.findingId != null && x.findingId == e.findingId && x.kind == pref) return 0;
          if (x.versionId == e.versionId && x.kind == pref) return 1;
          if (x.kind == e.kind) return 2;
          if (x.versionId == e.versionId) return 3;
          return 4;
        }

        return score(a).compareTo(score(b));
      });
      if (!mounted) return;
      setState(() {
        _candidates = all;
        _other = all.isEmpty ? null : all.first;
        _loadingCandidates = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _candidateError = err.toString();
        _loadingCandidates = false;
      });
    }
  }

  String _label(Evidence x) => '${evidenceKindLabel(x.kind)} · ${x.inspectionCode ?? ''} v${x.versionNo ?? '?'}';

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 1100;
    final viewer = _viewer(api);
    final meta = _Metadata(evidence: e, onOpenFinding: e.findingId == null ? null : () {
      Navigator.of(context).pop();
      context.go(workspaceLink(e.inspectionId, version: e.versionNo, finding: e.findingId));
    });
    return Dialog(
      insetPadding: EdgeInsets.all(size.width < 700 ? 8 : 28),
      backgroundColor: EE.bg1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1500),
        child: Padding(
          padding: const EdgeInsets.all(EE.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Eyebrow(evidenceKindLabel(e.kind)),
                  const SizedBox(height: 4),
                  Text(e.title, style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (e.isDemo) const Padding(padding: EdgeInsets.only(right: 8), child: DemoTag(compact: true)),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedPicker<_Mode>(
                value: _mode,
                options: const [
                  (_Mode.inspect, 'Inspect', Icons.zoom_in_rounded),
                  (_Mode.swipe, 'Swipe compare', Icons.compare_rounded),
                  (_Mode.sideBySide, 'Side by side', Icons.view_column_outlined),
                ],
                onChanged: (m) => setState(() => _mode = m),
              ),
              if (_mode != _Mode.inspect) _candidatePicker(),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: viewer),
                      const SizedBox(width: 14),
                      SizedBox(width: 360, child: SingleChildScrollView(child: meta)),
                    ])
                  : ListView(children: [SizedBox(height: size.height * 0.55, child: viewer), const SizedBox(height: 12), meta]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _candidatePicker() {
    if (_loadingCandidates) return const SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 2));
    if (_candidateError != null) return Text('Comparison candidates unavailable: $_candidateError', style: const TextStyle(color: EE.fail, fontSize: 12));
    if (_candidates.isEmpty) return const Text('No other evidence image to compare with', style: TextStyle(color: EE.textMuted, fontSize: 12));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Text('Compare with  ', style: TextStyle(fontSize: 12, color: EE.textMuted)),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: DropdownButton<String>(
          value: _other?.id,
          isExpanded: true,
          isDense: true,
          dropdownColor: EE.surfaceHi,
          underline: const SizedBox(),
          style: const TextStyle(fontSize: 12.5, color: EE.text),
          items: [for (final c in _candidates) DropdownMenuItem(value: c.id, child: Text(_label(c), overflow: TextOverflow.ellipsis))],
          onChanged: (id) => setState(() => _other = _candidates.firstWhere((c) => c.id == id)),
        ),
      ),
    ]);
  }

  Widget _viewer(ApiClient api) {
    final url = api.url(e.url);
    final sizeA = e.width != null && e.height != null ? Size(e.width!.toDouble(), e.height!.toDouble()) : null;
    if (_mode == _Mode.inspect || _other == null) {
      return OverlayImageViewer(url: url, imageSize: sizeA, caption: sizeA == null ? null : '${e.width}×${e.height} px · scroll/pinch to zoom');
    }
    final o = _other!;
    final sizeB = o.width != null && o.height != null ? Size(o.width!.toDouble(), o.height!.toDouble()) : null;
    if (_mode == _Mode.sideBySide) {
      return SideBySideCompare(urlA: url, urlB: api.url(o.url), labelA: _label(e), labelB: _label(o), sizeA: sizeA, sizeB: sizeB);
    }
    final aspectA = sizeA == null ? null : sizeA.width / sizeA.height;
    final aspectB = sizeB == null ? null : sizeB.width / sizeB.height;
    final mismatch = aspectA != null && aspectB != null && (aspectA / aspectB - 1).abs() > 0.02;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (mismatch)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 15, color: EE.uncertain),
            const SizedBox(width: 6),
            Expanded(
              child: Text('These images use different frames (aspect ${aspectA.toStringAsFixed(2)} vs ${aspectB.toStringAsFixed(2)}); pixels do not line up. Side-by-side mode is recommended.',
                  style: const TextStyle(fontSize: 12, color: EE.uncertain)),
            ),
          ]),
        ),
      Expanded(child: SwipeCompare(urlA: url, urlB: api.url(o.url), labelA: _label(e), labelB: _label(o), aspect: aspectA)),
      const SizedBox(height: 6),
      const Text('Drag the divider (or click) to reveal image A over image B.', style: TextStyle(fontSize: 11.5, color: EE.textDim)),
    ]);
  }
}

class _Metadata extends ConsumerWidget {
  const _Metadata({required this.evidence, this.onOpenFinding});
  final Evidence evidence;
  final VoidCallback? onOpenFinding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = evidence;
    final api = ref.watch(apiProvider);
    final f = e.finding;
    final b = e.bbox;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        eyebrow: 'Provenance',
        title: 'Evidence record',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KV('Evidence ID', e.id, mono: true, keyWidth: 120),
          KV('Kind', evidenceKindLabel(e.kind), keyWidth: 120),
          KV('Inspection', '${e.inspectionCode ?? e.inspectionId}  ·  version ${e.versionNo ?? '?'}', keyWidth: 120),
          KV('Created', fmtTime(e.createdAt), keyWidth: 120),
          KV('Operation', e.operation, mono: true, keyWidth: 120),
          KV('Algorithm', e.algorithm, keyWidth: 120),
          KV('Image size', e.width == null ? null : '${e.width} × ${e.height} px', mono: true, keyWidth: 120),
          KV('Region (orig. px)', b == null ? null : 'x ${b[0].round()}–${b[2].round()}, y ${b[1].round()}–${b[3].round()}  (${(b[2] - b[0]).round()}×${(b[3] - b[1]).round()})', mono: true, keyWidth: 120),
          KV('Source asset', e.j.strN('source_asset_id'), mono: true, keyWidth: 120),
          KV('SHA-256', e.sha256, mono: true, keyWidth: 120),
          if (b != null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Region coordinates are in the original photo frame (after EXIF orientation), the same frame used by detections, OCR boxes and findings.',
                  style: TextStyle(fontSize: 11.5, color: EE.textDim)),
            ),
        ]),
      ),
      if (f != null) ...[
        const SizedBox(height: 12),
        Panel(
          eyebrow: 'Related finding',
          title: '#${f.integer('seq')} ${checkLabels[f.str('check_type')] ?? titleCase(f.str('check_type'))}',
          actions: [VerdictBadge(f.str('verdict'), dense: true)],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KV('Subject', f.str('subject'), keyWidth: 120),
            const SizedBox(height: 8),
            if (onOpenFinding != null)
              OutlinedButton.icon(onPressed: onOpenFinding, icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open finding in workspace')),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      if (e.url != null)
        FilledButton.icon(
          onPressed: () => openUrl(api.url('${e.url}?download=1')),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download original evidence file'),
        ),
    ]);
  }
}
