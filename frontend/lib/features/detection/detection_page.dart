import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/image_viewer.dart';
import '../../core/widgets/inspection_scope.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import '../inspections/finding_detail.dart';
import 'analysis_common.dart';

final _detectionsProvider = FutureProvider.family<List<Json>, (String, bool)>((ref, k) => ref.watch(apiProvider).detections(k.$1, includeLow: k.$2));
final _detectorStatusProvider = FutureProvider<Json>((ref) async => (await ref.watch(apiProvider).diagnostics()).obj('detector'));
final _expectedProvider = FutureProvider.family<Json, String>((ref, versionId) => ref.watch(apiProvider).expected(versionId));

String classLabel(String c) => titleCase(c);

class DetectionPage extends StatelessWidget {
  const DetectionPage({super.key, this.inspectionId, this.versionNo});
  final String? inspectionId;
  final int? versionNo;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PageHeader(
        eyebrow: 'Analyze · YOLOv8',
        title: 'Component Detection',
        description: 'Every stored detection of the selected run, in original-photo coordinates. Boxes carry the model\'s own confidence; '
            'low-confidence detections are kept for review and never counted as confirmed components.',
      ),
      Expanded(
        child: InspectionScope(
          inspectionId: inspectionId,
          versionNo: versionNo,
          onSelect: (i, v) => context.go(i.isEmpty ? '/console/detection' : scopedLink('/console/detection', i, version: v)),
          pickerTitle: 'Select an inspection to inspect its detections',
          builder: (ctx, insp, ver) => _DetectionWorkbench(key: ValueKey(ver.id), inspection: insp, version: ver),
        ),
      ),
    ]);
  }
}

class _DetectionWorkbench extends ConsumerStatefulWidget {
  const _DetectionWorkbench({super.key, required this.inspection, required this.version});
  final Inspection inspection;
  final Version version;
  @override
  ConsumerState<_DetectionWorkbench> createState() => _DetectionWorkbenchState();
}

class _DetectionWorkbenchState extends ConsumerState<_DetectionWorkbench> {
  bool _includeLow = false;
  double? _threshold;
  final Set<String> _hidden = {};
  String? _selected;
  bool _labels = true;
  double _opacity = 1.0;
  String _mode = 'interactive';
  String _sort = 'confidence';

  Version get v => widget.version;

  double _runThreshold(Json? status) {
    final cfg = v.config.obj('detector');
    return (cfg.dbl('conf') ?? status?.dbl('conf_threshold') ?? 0.35);
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    final dets = ref.watch(_detectionsProvider((v.id, _includeLow)));
    final media = ref.watch(mediaProvider(v.id));
    final status = ref.watch(_detectorStatusProvider);
    final findings = ref.watch(findingsProvider(v.id));
    if (dets.hasError) return ErrorView(dets.error!, onRetry: () => ref.invalidate(_detectionsProvider((v.id, _includeLow))));
    if (media.hasError) return ErrorView(media.error!, onRetry: () => ref.invalidate(mediaProvider(v.id)));
    if (!dets.hasValue || !media.hasValue) return const LoadingView(label: 'Loading detections');
    final all = dets.requireValue;
    if (all.isEmpty && v.status != 'completed') {
      return EmptyState(
        title: 'No detections for this version',
        message: 'Version ${v.no} is "${v.status}". Detections appear once the pipeline has run the YOLOv8 stage.',
        icon: Icons.center_focus_weak_rounded,
        action: v.latestJobId == null ? null : OutlinedButton(onPressed: () => context.go('/console/live?job=${v.latestJobId}'), child: const Text('Open live job')),
      );
    }
    final st = status.value;
    final runThr = _runThreshold(st);
    final thr = _threshold ?? runThr;
    final visible = all.where((d) => (d.dbl('confidence') ?? 0) >= thr && !_hidden.contains(d.str('class_name'))).toList();
    final counts = <String, int>{};
    for (final d in all.where((d) => (d.dbl('confidence') ?? 0) >= thr)) {
      counts[d.str('class_name')] = (counts[d.str('class_name')] ?? 0) + 1;
    }
    final photo = mediaImage(api, media.requireValue, _mode == 'evidence' ? 'detections_overlay' : 'original_photo') ?? mediaImage(api, media.requireValue, 'original_photo');
    final linked = <String, List<Finding>>{};
    for (final f in findings.value?.$1 ?? const <Finding>[]) {
      final id = f.j.strN('detection_id');
      if (id != null) linked.putIfAbsent(id, () => []).add(f);
    }
    final selected = all.where((d) => d.str('id') == _selected).firstOrNull;

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final visual = Panel(
        eyebrow: 'Original frame · ${photo?.size == null ? '' : '${photo!.size!.width.toInt()}×${photo.size!.height.toInt()} px'}',
        title: _mode == 'evidence' ? 'Server-rendered detection evidence' : '${visible.length} detections shown',
        expand: true,
        padding: const EdgeInsets.fromLTRB(EE.s3, EE.s3, EE.s3, EE.s3),
        actions: [
          SegToggle<String>(values: const {'interactive': 'Interactive', 'evidence': 'Evidence image'}, value: _mode, dense: true, onChanged: (m) => setState(() => _mode = m)),
          const SizedBox(width: 6),
          IconButton(
            tooltip: _labels ? 'Hide labels' : 'Show labels',
            onPressed: () => setState(() => _labels = !_labels),
            icon: Icon(_labels ? Icons.label_outline_rounded : Icons.label_off_outlined, size: 18),
          ),
        ],
        child: photo == null
            ? const EmptyState(title: 'No photo evidence for this version', icon: Icons.image_not_supported_outlined)
            : OverlayImageViewer(
                url: photo.url,
                imageSize: photo.size,
                overlays: _mode == 'evidence' ? const [] : [for (final d in visible) _overlay(d)],
                selectedId: _mode == 'evidence' ? null : _selected,
                onSelect: (id) => setState(() => _selected = id),
                overlayOpacity: _opacity,
                showLabels: _labels,
                caption: _mode == 'evidence' ? 'Annotated by the backend at run time (conf ≥ run threshold)' : 'Tap a box to inspect · dashed = below model threshold',
              ),
      );
      final sideChildren = <Widget>[
        _ModelCard(version: v, status: st, statusError: status.error, sampleModel: all.isEmpty ? null : all.first.str('model_name'), runThreshold: runThr),
        const SizedBox(height: EE.s3),
        _filters(counts, runThr, thr),
        const SizedBox(height: EE.s3),
        if (selected != null) ...[_SelectedDetection(det: selected, threshold: runThr, findings: linked[selected.str('id')] ?? const [], inspectionId: widget.inspection.id, versionNo: v.no, onClear: () => setState(() => _selected = null)), const SizedBox(height: EE.s3)],
        _ExpectedVsDetected(versionId: v.id, allDetections: all, runThreshold: runThr),
        const SizedBox(height: EE.s3),
        _table(visible, runThr, wide),
      ];
      final side = wide
          ? ListView(padding: EdgeInsets.zero, children: sideChildren)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sideChildren);
      return AnalysisLayout(visual: visual, side: side, narrowVisualHeight: 460);
    });
  }

  ImgOverlay _overlay(Json d) {
    final cls = d.str('class_name');
    final conf = d.dbl('confidence') ?? 0;
    return ImgOverlay(
      id: d.str('id'),
      box: d.box('bbox'),
      color: EE.detClass(cls),
      label: '${_short(cls)} ${conf.toStringAsFixed(2)}',
      dashed: !d.boolean('above_threshold', true),
      group: cls,
    );
  }

  String _short(String c) => switch (c) {
        'circuit_breaker' => 'CB',
        'contactor' => 'K',
        'power_supply' => 'PSU',
        'terminal_block' => 'TB',
        'wire_marker' => 'FER',
        'device_label' => 'LBL',
        'earth_bar' => 'PE',
        _ => c,
      };

  Widget _filters(Map<String, int> counts, double runThr, double thr) {
    final classes = counts.keys.toList()..sort();
    return Panel(
      eyebrow: 'Filters',
      title: 'Classes & confidence',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (classes.isEmpty)
          const Text('No detections at this confidence.', style: TextStyle(fontSize: 12, color: EE.textDim))
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final cl in classes)
              InkWell(
                borderRadius: BorderRadius.circular(EE.r1),
                onTap: () => setState(() => _hidden.contains(cl) ? _hidden.remove(cl) : _hidden.add(cl)),
                child: AnimatedContainer(
                  duration: EE.fast,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: _hidden.contains(cl) ? Colors.transparent : EE.detClass(cl).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(EE.r1),
                    border: Border.all(color: _hidden.contains(cl) ? EE.line : EE.detClass(cl).withValues(alpha: 0.6)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: _hidden.contains(cl) ? EE.textDim : EE.detClass(cl), borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 6),
                    Text(classLabel(cl), style: TextStyle(fontSize: 12, color: _hidden.contains(cl) ? EE.textDim : EE.text)),
                    const SizedBox(width: 6),
                    Text('${counts[cl]}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted)),
                  ]),
                ),
              ),
          ]),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Display threshold', style: TextStyle(fontSize: 12.5)),
          const Spacer(),
          MonoValue(thr.toStringAsFixed(2), color: EE.cyan),
        ]),
        Slider(
          value: thr.clamp(_includeLow ? 0.05 : runThr, 1.0),
          min: _includeLow ? 0.05 : runThr,
          max: 1.0,
          onChanged: (x) => setState(() => _threshold = x),
        ),
        Text(
          'Run threshold ${runThr.toStringAsFixed(2)} (model confidence; detections below it are stored only when ≥ 0.05 and never confirm presence). '
          'This slider filters the display only.',
          style: const TextStyle(fontSize: 11, color: EE.textDim, height: 1.4),
        ),
        const SizedBox(height: 6),
        ToggleRow(
          label: 'Include low-confidence detections',
          hint: 'Show stored detections below the run threshold (dashed)',
          value: _includeLow,
          onChanged: (x) => setState(() {
            _includeLow = x;
            _threshold = null;
            if (x) _threshold = 0.05;
          }),
        ),
        Row(children: [
          const Text('Overlay opacity', style: TextStyle(fontSize: 12.5)),
          Expanded(child: Slider(value: _opacity, min: 0.1, max: 1.0, onChanged: (x) => setState(() => _opacity = x))),
        ]),
      ]),
    );
  }

  Widget _table(List<Json> visible, double runThr, bool wide) {
    final rows = [...visible];
    if (_sort == 'confidence') {
      rows.sort((a, b) => (b.dbl('confidence') ?? 0).compareTo(a.dbl('confidence') ?? 0));
    } else {
      rows.sort((a, b) {
        final c = a.str('class_name').compareTo(b.str('class_name'));
        return c != 0 ? c : (b.dbl('confidence') ?? 0).compareTo(a.dbl('confidence') ?? 0);
      });
    }
    return Panel(
      eyebrow: 'Detections',
      title: '${rows.length} rows',
      actions: [SegToggle<String>(values: const {'confidence': 'By conf.', 'class': 'By class'}, value: _sort, dense: true, onChanged: (s) => setState(() => _sort = s))],
      padding: const EdgeInsets.fromLTRB(EE.s2, EE.s2, EE.s2, EE.s3),
      child: rows.isEmpty
          ? const Padding(padding: EdgeInsets.all(12), child: Text('No detections match the filters.', style: TextStyle(fontSize: 12, color: EE.textDim)))
          : Column(children: [
              for (final d in rows.take(400)) _row(d, runThr),
              if (rows.length > 400) Padding(padding: const EdgeInsets.all(8), child: Text('Showing first 400 of ${rows.length}', style: const TextStyle(fontSize: 11, color: EE.textDim))),
            ]),
    );
  }

  Widget _row(Json d, double runThr) {
    final id = d.str('id');
    final sel = id == _selected;
    final cls = d.str('class_name');
    final conf = d.dbl('confidence') ?? 0;
    return InkWell(
      onTap: () => setState(() => _selected = sel ? null : id),
      borderRadius: BorderRadius.circular(EE.r1),
      child: AnimatedContainer(
        duration: EE.fast,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? EE.cyan.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(EE.r1),
          border: Border.all(color: sel ? EE.cyan.withValues(alpha: 0.4) : Colors.transparent),
        ),
        child: Row(children: [
          Container(width: 3, height: 18, decoration: BoxDecoration(color: EE.detClass(cls), borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(child: Text(classLabel(cls), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
          ConfidenceBar(value: conf, threshold: runThr, color: d.boolean('above_threshold', true) ? EE.detClass(cls) : EE.textDim, width: 64),
          const SizedBox(width: 8),
          SizedBox(width: 30, child: Text(d.str('source'), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.textDim))),
        ]),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.version, required this.status, required this.statusError, required this.sampleModel, required this.runThreshold});
  final Version version;
  final Json? status;
  final Object? statusError;
  final String? sampleModel;
  final double runThreshold;

  @override
  Widget build(BuildContext context) {
    final kind = version.summary.detectorKind ?? status?.strN('kind') ?? 'unknown';
    final limitations = status?.strs('limitations') ?? const <String>[];
    final metrics = status?.objN('training_metrics');
    final synthetic = (metrics?.str('dataset').toLowerCase().contains('synthetic') ?? false) || limitations.any((l) => l.toLowerCase().contains('synthetic'));
    final currentModel = status?.strN('model_name');
    final sameModel = currentModel == null || currentModel == sampleModel;
    Widget? banner;
    if (kind == 'generic_coco') {
      banner = NoticeBanner(
        title: 'Generic COCO-pretrained weights — no electrical-cabinet classes',
        lines: limitations.isNotEmpty
            ? limitations
            : const ['Component presence and type checks of this run are UNCERTAIN because the detector cannot recognise breakers, contactors, terminals or ferrules.'],
        color: EE.uncertain,
        icon: Icons.warning_amber_rounded,
      );
    } else if (synthetic && sameModel) {
      banner = NoticeBanner(
        title: 'Detector trained on synthetic renders only',
        lines: [
          ...limitations,
          if (metrics != null)
            'Validation on held-out synthetic renders: mAP50 ${fmtConf(metrics['mAP50'])}, mAP50-95 ${fmtConf(metrics['mAP50_95'])}. ${metrics.str('caveat')}',
        ],
        color: EE.violet,
        icon: Icons.science_outlined,
      );
    } else if (kind == 'none' || kind == 'unknown') {
      banner = const NoticeBanner(
        title: 'Detector did not run for this version',
        lines: ['No detector was available when this version was processed, so presence and type checks are UNCERTAIN.'],
        color: EE.fail,
        icon: Icons.block_rounded,
      );
    }
    return Panel(
      eyebrow: 'Model',
      title: sampleModel ?? currentModel ?? 'Detector',
      actions: [Tag(kind.replaceAll('_', ' '), color: kind == 'custom' ? EE.cyan : EE.uncertain, mono: true)],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (banner != null) ...[banner, const SizedBox(height: 10)],
        KV('Run threshold', runThreshold.toStringAsFixed(2), mono: true, keyWidth: 130),
        if (status != null) ...[
          KV('IoU threshold', fmtConf(status!['iou_threshold']), mono: true, keyWidth: 130),
          KV('Input size', '${status!.integer('imgsz')} px · tiles ${status!.obj('tiling').boolean('enabled') ? '${status!.obj('tiling').integer('tile_size')} px, ${pct(status!.obj('tiling').dbl('overlap'))} overlap' : 'off'}',
              mono: true, keyWidth: 130),
          KV('Server detector now', '${status!.str('state')}${currentModel != null ? ' · $currentModel' : ''}${status!.strN('device') != null ? ' · ${status!.str('device')}' : ''}', keyWidth: 130),
          if (status!.strs('supported_cabinet_classes').isNotEmpty)
            KV('Cabinet classes', status!.strs('supported_cabinet_classes').map(titleCase).join(', '), keyWidth: 130),
        ] else if (statusError != null)
          Text('Current detector status unavailable: $statusError', style: const TextStyle(fontSize: 11.5, color: EE.textDim)),
        if (!sameModel)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('The server now has different weights loaded than the ones that produced this run; figures above describe the current server.',
                style: TextStyle(fontSize: 11, color: EE.textDim)),
          ),
      ]),
    );
  }
}

class _SelectedDetection extends StatelessWidget {
  const _SelectedDetection({required this.det, required this.threshold, required this.findings, required this.inspectionId, required this.versionNo, required this.onClear});
  final Json det;
  final double threshold;
  final List<Finding> findings;
  final String inspectionId;
  final int versionNo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final b = det.box('bbox');
    final cls = det.str('class_name');
    final above = det.boolean('above_threshold', true);
    return Panel(
      eyebrow: 'Selected detection',
      title: classLabel(cls),
      accent: EE.detClass(cls),
      actions: [IconButton(tooltip: 'Clear selection', onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 16))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const SizedBox(width: 130, child: Text('Confidence', style: TextStyle(fontSize: 12, color: EE.textDim))),
          ConfidenceBar(value: det.dbl('confidence') ?? 0, threshold: threshold, color: EE.detClass(cls), width: 120),
        ]),
        KV('Status', above ? 'At or above run threshold' : 'Below run threshold — not used as positive evidence', valueColor: above ? EE.pass : EE.uncertain, keyWidth: 130),
        KV('Box (px)', fmtBox(b), mono: true, keyWidth: 130),
        if (b != null) KV('Size', '${(b[2] - b[0]).toStringAsFixed(0)} × ${(b[3] - b[1]).toStringAsFixed(0)} px', mono: true, keyWidth: 130),
        KV('Pass', det.str('source') == 'tile' ? 'Tile (high-resolution crop, mapped back)' : 'Full image', keyWidth: 130),
        KV('Model', det.str('model_name'), mono: true, keyWidth: 130),
        KV('Detection ID', det.str('id'), mono: true, keyWidth: 130),
        const SubHead('Findings using this detection'),
        if (findings.isEmpty)
          const Text('No finding references this detection directly.', style: TextStyle(fontSize: 12, color: EE.textDim))
        else
          for (final f in findings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Text('#${f.seq}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.textMuted)),
                const SizedBox(width: 8),
                Expanded(child: Text('${f.checkLabel} · ${f.subject}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                VerdictBadge(f.effectiveVerdict, dense: true, reviewed: f.reviewCount > 0),
                IconButton(
                  tooltip: 'Open finding',
                  onPressed: () => showFindingDrawer(context, f.id),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                ),
                IconButton(
                  tooltip: 'Open in workspace',
                  onPressed: () => context.go(workspaceLink(inspectionId, version: versionNo, finding: f.id)),
                  icon: const Icon(Icons.view_quilt_outlined, size: 15),
                ),
              ]),
            ),
      ]),
    );
  }
}

class _ExpectedVsDetected extends ConsumerWidget {
  const _ExpectedVsDetected({required this.versionId, required this.allDetections, required this.runThreshold});
  final String versionId;
  final List<Json> allDetections;
  final double runThreshold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exp = ref.watch(_expectedProvider(versionId));
    return Panel(
      eyebrow: 'Specification',
      title: 'Expected vs detected (counts)',
      child: exp.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (e, _) => ErrorView(e, compact: true, onRetry: () => ref.invalidate(_expectedProvider(versionId))),
        data: (j) {
          final expected = <String, int>{};
          var unmapped = 0;
          for (final c in j.objs('components')) {
            final cl = c.strN('canonical_class');
            if (cl == null) {
              unmapped += c.integer('quantity', 1);
              continue;
            }
            expected[cl] = (expected[cl] ?? 0) + c.integer('quantity', 1);
          }
          final detected = <String, int>{};
          for (final d in allDetections.where((d) => d.boolean('above_threshold', true) && (d.dbl('confidence') ?? 0) >= runThreshold)) {
            detected[d.str('class_name')] = (detected[d.str('class_name')] ?? 0) + 1;
          }
          final classes = {...expected.keys, ...detected.keys}.toList()..sort();
          if (classes.isEmpty) return const Text('No expected components recorded for this version.', style: TextStyle(fontSize: 12, color: EE.textDim));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: const [
              Expanded(child: Text('Class', style: TextStyle(fontSize: 11, color: EE.textDim))),
              SizedBox(width: 64, child: Text('Expected', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: EE.textDim))),
              SizedBox(width: 64, child: Text('Detected', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: EE.textDim))),
            ]),
            const SizedBox(height: 4),
            for (final cl in classes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: EE.detClass(cl), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(classLabel(cl), style: const TextStyle(fontSize: 12.5))),
                  SizedBox(width: 64, child: Text(expected[cl]?.toString() ?? '—', textAlign: TextAlign.right, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12))),
                  SizedBox(
                    width: 64,
                    child: Text(
                      detected[cl]?.toString() ?? '0',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: EE.fontMono,
                        fontSize: 12,
                        color: expected.containsKey(cl) && (detected[cl] ?? 0) < expected[cl]! ? EE.uncertain : EE.text,
                      ),
                    ),
                  ),
                ]),
              ),
            if (unmapped > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('$unmapped expected item(s) have no detector class mapping.', style: const TextStyle(fontSize: 11, color: EE.uncertain))),
            const SizedBox(height: 6),
            const Text(
              'Counts only. Label plates and ferrules are detected as separate classes; whether a specific component is present is decided per item by the '
              'verification rules using the registered drawing position — see the Workspace findings.',
              style: TextStyle(fontSize: 11, color: EE.textDim, height: 1.4),
            ),
          ]);
        },
      ),
    );
  }
}
