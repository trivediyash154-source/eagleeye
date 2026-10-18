import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/download.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/image_viewer.dart';
import '../../core/widgets/inspection_scope.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import 'finding_detail.dart';

final _detectionsProvider = FutureProvider.family<List<Json>, String>((ref, v) => ref.watch(apiProvider).detections(v));
final _ocrProvider = FutureProvider.family<List<Json>, String>((ref, v) => ref.watch(apiProvider).ocr(v));

class WorkspacePage extends StatelessWidget {
  const WorkspacePage({super.key, this.inspectionId, this.versionNo, this.findingId});
  final String? inspectionId;
  final int? versionNo;
  final String? findingId;

  @override
  Widget build(BuildContext context) {
    return InspectionScope(
      inspectionId: inspectionId,
      versionNo: versionNo,
      pickerTitle: 'Open an inspection in the workspace',
      pickerMessage: 'The workspace compares the GA drawing, the cabinet photograph and the findings side by side.',
      onSelect: (i, v) => context.go(i.isEmpty ? '/console/workspace' : workspaceLink(i, version: v)),
      builder: (context, insp, ver) => _Workspace(key: ValueKey(ver.id), inspection: insp, version: ver, initialFinding: findingId),
    );
  }
}

class _Workspace extends ConsumerStatefulWidget {
  const _Workspace({super.key, required this.inspection, required this.version, this.initialFinding});
  final Inspection inspection;
  final Version version;
  final String? initialFinding;
  @override
  ConsumerState<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends ConsumerState<_Workspace> {
  String? _selected;
  String _verdict = 'ALL';
  String _query = '';
  String? _check;
  String? _zone;
  bool _unreviewedOnly = false;
  bool _showFindings = true, _showDetections = false, _showOcr = false, _showZones = true;
  bool _annotated = false;
  double _opacity = 1.0;
  int _mobileTab = 0;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialFinding;
  }

  Version get v => widget.version;

  void _select(String id) => setState(() => _selected = id);

  Future<void> _export(String fmt) async {
    setState(() => _exporting = true);
    try {
      final api = ref.read(apiProvider);
      final r = await api.createReport(v.id, fmt);
      await openUrl(api.url(r.str('download_url')));
      if (mounted) showSnack(context, '${fmt.toUpperCase()} generated: ${r.str('filename')}');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (v.status != 'completed') return _NotReady(inspection: widget.inspection, version: v);
    final findingsAsync = ref.watch(findingsProvider(v.id));
    final mediaAsync = ref.watch(mediaProvider(v.id));
    return AsyncView<(List<Finding>, Map<String, int>)>(
      findingsAsync,
      onRetry: () => ref.invalidate(findingsProvider(v.id)),
      data: (fr) => AsyncView<Json>(
        mediaAsync,
        onRetry: () => ref.invalidate(mediaProvider(v.id)),
        data: (media) => _layout(context, fr.$1, fr.$2, media),
      ),
    );
  }

  List<Finding> _filter(List<Finding> all) => all.where((f) {
        if (_verdict != 'ALL' && f.effectiveVerdict != _verdict && f.verdict != _verdict) return false;
        if (_check != null && f.checkType != _check) return false;
        if (_zone != null && f.zone != _zone) return false;
        if (_unreviewedOnly && f.reviewCount > 0) return false;
        if (_query.isNotEmpty) {
          final hay = '${f.subject} ${f.expected ?? ''} ${f.observed ?? ''} ${f.checkLabel} ${f.zone ?? ''} ${f.rule}'.toLowerCase();
          if (!hay.contains(_query.toLowerCase())) return false;
        }
        return true;
      }).toList();

  Widget _layout(BuildContext context, List<Finding> all, Map<String, int> counts, Json media) {
    final w = MediaQuery.sizeOf(context).width;
    final filtered = _filter(all);
    final selected = all.where((f) => f.id == _selected).firstOrNull;
    final photo = _PhotoPanel(
      version: v,
      media: media,
      findings: filtered,
      selected: selected,
      onSelect: _select,
      showFindings: _showFindings,
      showDetections: _showDetections,
      showOcr: _showOcr,
      showZones: _showZones,
      annotated: _annotated,
      opacity: _opacity,
      onToggle: (k) => setState(() {
        switch (k) {
          case 'findings':
            _showFindings = !_showFindings;
          case 'det':
            _showDetections = !_showDetections;
          case 'ocr':
            _showOcr = !_showOcr;
          case 'zones':
            _showZones = !_showZones;
          case 'annotated':
            _annotated = !_annotated;
        }
      }),
      onOpacity: (x) => setState(() => _opacity = x),
      onOpenDetail: (id) => showFindingDrawer(context, id, onReviewed: () => refreshInspectionData(ref, inspectionId: widget.inspection.id, versionId: v.id)),
    );
    final list = _FindingsPanel(
      all: all,
      filtered: filtered,
      counts: counts,
      selectedId: _selected,
      verdict: _verdict,
      query: _query,
      check: _check,
      zone: _zone,
      unreviewedOnly: _unreviewedOnly,
      onVerdict: (x) => setState(() => _verdict = x),
      onQuery: (x) => setState(() => _query = x),
      onCheck: (x) => setState(() => _check = x),
      onZone: (x) => setState(() => _zone = x),
      onUnreviewed: (x) => setState(() => _unreviewedOnly = x),
      onSelect: _select,
      onOpen: (id) {
        _select(id);
        showFindingDrawer(context, id, onReviewed: () => refreshInspectionData(ref, inspectionId: widget.inspection.id, versionId: v.id));
      },
    );
    final spec = _SpecPanel(version: v, selected: selected, onZone: (z) => setState(() => _zone = _zone == z ? null : z), zone: _zone);
    final actions = Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(onPressed: _exporting ? null : () => _export('pdf'), icon: const Icon(Icons.picture_as_pdf_outlined, size: 16), label: const Text('Export PDF')),
      OutlinedButton.icon(onPressed: _exporting ? null : () => _export('xlsx'), icon: const Icon(Icons.table_view_outlined, size: 16), label: const Text('XLSX')),
      OutlinedButton.icon(onPressed: () => context.go('/console/evidence?i=${widget.inspection.id}'), icon: const Icon(Icons.photo_library_outlined, size: 16), label: const Text('Evidence')),
      FilledButton.icon(onPressed: () => context.go('/console/history?i=${widget.inspection.id}'), icon: const Icon(Icons.published_with_changes_rounded, size: 16), label: const Text('Reinspect / history')),
    ]);
    if (w >= 1500) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerRight, child: actions),
        const SizedBox(height: 12),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 330, child: spec),
            const SizedBox(width: 12),
            Expanded(child: photo),
            const SizedBox(width: 12),
            SizedBox(width: 400, child: list),
          ]),
        ),
        const SizedBox(height: 16),
      ]);
    }
    if (w >= 1000) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _Tabs(labels: const ['Photograph', 'GA drawing'], index: _mobileTab.clamp(0, 1), onTap: (i) => setState(() => _mobileTab = i)),
          const Spacer(),
          actions,
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _mobileTab == 1 ? spec : photo),
            const SizedBox(width: 12),
            SizedBox(width: 380, child: list),
          ]),
        ),
        const SizedBox(height: 16),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Tabs(labels: const ['Photo', 'Drawing', 'Findings'], index: _mobileTab, onTap: (i) => setState(() => _mobileTab = i)),
      const SizedBox(height: 10),
      Expanded(child: [photo, spec, list][_mobileTab.clamp(0, 2)]),
      const SizedBox(height: 10),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: actions),
      const SizedBox(height: 12),
    ]);
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.index, required this.onTap});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: EE.surface, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(EE.r1),
              child: AnimatedContainer(
                duration: EE.fast,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(color: i == index ? EE.cyan.withValues(alpha: 0.12) : Colors.transparent, borderRadius: BorderRadius.circular(EE.r1)),
                child: Text(labels[i], style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: i == index ? EE.cyan : EE.textMuted)),
              ),
            ),
        ]),
      );
}

class _NotReady extends StatelessWidget {
  const _NotReady({required this.inspection, required this.version});
  final Inspection inspection;
  final Version version;
  @override
  Widget build(BuildContext context) {
    final active = version.isActive;
    return EmptyState(
      icon: active ? Icons.sensors_rounded : (version.status == 'failed' ? Icons.error_outline_rounded : Icons.edit_note_rounded),
      title: active ? 'Version ${version.no} is still processing' : (version.status == 'failed' ? 'Version ${version.no} failed' : 'Version ${version.no} has not been run yet'),
      message: version.error ?? (active ? 'Results appear here when the backend job completes.' : 'Upload inputs and run the inspection to produce findings.'),
      action: Wrap(spacing: 8, children: [
        if (version.latestJobId != null) FilledButton(onPressed: () => context.go('/console/live?job=${version.latestJobId}'), child: const Text('Open live job')),
        if (!active) OutlinedButton(onPressed: () => context.go('/console/new'), child: const Text('New inspection')),
      ]),
    );
  }
}

// --- photo -------------------------------------------------------------------------------------

class _PhotoPanel extends ConsumerWidget {
  const _PhotoPanel({
    required this.version,
    required this.media,
    required this.findings,
    required this.selected,
    required this.onSelect,
    required this.showFindings,
    required this.showDetections,
    required this.showOcr,
    required this.showZones,
    required this.annotated,
    required this.opacity,
    required this.onToggle,
    required this.onOpacity,
    required this.onOpenDetail,
  });
  final Version version;
  final Json media;
  final List<Finding> findings;
  final Finding? selected;
  final ValueChanged<String> onSelect;
  final bool showFindings, showDetections, showOcr, showZones, annotated;
  final double opacity;
  final ValueChanged<String> onToggle;
  final ValueChanged<double> onOpacity;
  final ValueChanged<String> onOpenDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    final items = media.obj('items');
    final orig = items.objN('original_photo');
    final ann = items.objN('annotated_photo');
    final src = annotated && ann != null ? ann : orig;
    if (src == null) return const Panel(child: EmptyState(title: 'No photograph evidence', message: 'The preprocessing stage did not record an original-photo evidence item.'));
    final size = (orig?.intN('width') != null) ? Size(orig!.integer('width').toDouble(), orig.integer('height').toDouble()) : null;
    final overlays = <ImgOverlay>[];
    if (showZones) {
      final d = ref.watch(drawingProvider(version.id)).value;
      for (final z in d?.objs('zones') ?? const <Json>[]) {
        final q = (z['projected_quad'] as List?)?.map((p) => (p as List).map((e) => (e as num).toDouble()).toList()).toList();
        if (q != null) overlays.add(ImgOverlay(id: 'zone:${z.str('code')}', quad: q, color: EE.violet, label: z.str('code'), dashed: true, fillAlpha: 0.03));
      }
    }
    if (showDetections) {
      for (final d in ref.watch(_detectionsProvider(version.id)).value ?? const <Json>[]) {
        overlays.add(ImgOverlay(id: 'det:${d.str('id')}', box: d.box('bbox'), color: EE.detClass(d.str('class_name')), label: '${d.str('class_name').split('_').first} ${fmtConf(d['confidence'])}'));
      }
    }
    if (showOcr) {
      for (final o in ref.watch(_ocrProvider(version.id)).value ?? const <Json>[]) {
        overlays.add(ImgOverlay(id: 'ocr:${o.str('id')}', box: o.box('bbox'), color: EE.ice, label: o.str('normalized_text')));
      }
    }
    if (showFindings) {
      for (final f in findings) {
        if (f.checkType == 'drawing_alignment') continue;
        if (f.checkType == 'zone_correspondence' && f.id != selected?.id) continue;
        final b = f.bbox ?? f.expectedBbox;
        if (b == null) continue;
        overlays.add(ImgOverlay(id: f.id, box: b, color: EE.verdict(f.effectiveVerdict), label: '#${f.seq} ${f.subject}', dashed: f.bbox == null));
      }
    }
    if (selected != null && !overlays.any((o) => o.id == selected!.id)) {
      final b = selected!.bbox ?? selected!.expectedBbox;
      if (b != null) overlays.add(ImgOverlay(id: selected!.id, box: b, color: EE.verdict(selected!.effectiveVerdict), label: '#${selected!.seq} ${selected!.subject}', dashed: selected!.bbox == null));
    }
    Widget chip(String key, String label, bool on, Color c) => FilterChip(
          label: Text(label),
          selected: on,
          onSelected: (_) => onToggle(key),
          avatar: Icon(Icons.circle, size: 9, color: c),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
        );
    return Panel(
      expand: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      eyebrow: 'Cabinet photograph · original pixels',
      actions: [
        Tooltip(
          message: 'Show the server-rendered annotated image instead of the original',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Annotated', style: TextStyle(fontSize: 12, color: EE.textMuted)),
            Switch(value: annotated, onChanged: ann == null ? null : (_) => onToggle('annotated')),
          ]),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          chip('findings', 'Findings', showFindings, EE.pass),
          chip('det', 'Detections', showDetections, EE.detClass('circuit_breaker')),
          chip('ocr', 'OCR text', showOcr, EE.ice),
          chip('zones', 'Zones', showZones, EE.violet),
          const SizedBox(width: 8),
          const Text('Overlay', style: TextStyle(fontSize: 12, color: EE.textMuted)),
          SizedBox(width: 120, child: Slider(value: opacity, onChanged: onOpacity, min: 0.15, max: 1)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: OverlayImageViewer(
            url: api.url(src.str('url')),
            imageSize: size,
            overlays: overlays,
            selectedId: selected?.id,
            onSelect: (id) {
              if (!id.contains(':')) onSelect(id);
            },
            overlayOpacity: opacity,
            caption: '${orig?.integer('width')}×${orig?.integer('height')} px · scroll/pinch to zoom · drag to pan · click a box',
          ),
        ),
        if (selected != null) ...[const SizedBox(height: 10), _SelectedStrip(f: selected!, onOpen: () => onOpenDetail(selected!.id))],
      ]),
    );
  }
}

class _SelectedStrip extends StatelessWidget {
  const _SelectedStrip({required this.f, required this.onOpen});
  final Finding f;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: EE.verdict(f.effectiveVerdict).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.verdict(f.effectiveVerdict).withValues(alpha: 0.4))),
      child: Row(children: [
        Text('#${f.seq}', style: const TextStyle(fontFamily: EE.fontMono, color: EE.textDim)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${f.checkLabel} · ${f.subject}${f.zone != null ? ' · ${f.zone}' : ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'expected ', style: TextStyle(color: EE.textDim)),
                TextSpan(text: f.expected ?? '—', style: const TextStyle(fontFamily: EE.fontMono, color: EE.ice)),
                const TextSpan(text: '   observed ', style: TextStyle(color: EE.textDim)),
                TextSpan(text: f.observed ?? '—', style: TextStyle(fontFamily: EE.fontMono, color: EE.verdict(f.verdict))),
              ]),
              style: const TextStyle(fontSize: 12.5),
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        VerdictBadge(f.effectiveVerdict, reviewed: f.reviewCount > 0),
        const SizedBox(width: 10),
        FilledButton.tonalIcon(onPressed: onOpen, icon: const Icon(Icons.manage_search_rounded, size: 16), label: const Text('Evidence & review')),
      ]),
    );
  }
}

// --- findings ---------------------------------------------------------------------------------

class _FindingsPanel extends StatefulWidget {
  const _FindingsPanel({
    required this.all,
    required this.filtered,
    required this.counts,
    required this.selectedId,
    required this.verdict,
    required this.query,
    required this.check,
    required this.zone,
    required this.unreviewedOnly,
    required this.onVerdict,
    required this.onQuery,
    required this.onCheck,
    required this.onZone,
    required this.onUnreviewed,
    required this.onSelect,
    required this.onOpen,
  });
  final List<Finding> all, filtered;
  final Map<String, int> counts;
  final String? selectedId;
  final String verdict, query;
  final String? check, zone;
  final bool unreviewedOnly;
  final ValueChanged<String> onVerdict, onQuery, onSelect, onOpen;
  final ValueChanged<String?> onCheck, onZone;
  final ValueChanged<bool> onUnreviewed;

  @override
  State<_FindingsPanel> createState() => _FindingsPanelState();
}

class _FindingsPanelState extends State<_FindingsPanel> {
  late final _q = TextEditingController(text: widget.query);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checks = {for (final f in widget.all) f.checkType}.toList()..sort();
    final zones = {for (final f in widget.all) f.zone}.whereType<String>().toList()..sort();
    Widget vchip(String v, int n) {
      final on = widget.verdict == v;
      final c = v == 'ALL' ? EE.cyan : EE.verdict(v);
      return InkWell(
        onTap: () => widget.onVerdict(v),
        borderRadius: BorderRadius.circular(EE.r1),
        child: AnimatedContainer(
          duration: EE.fast,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(color: on ? c.withValues(alpha: 0.14) : Colors.transparent, borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: on ? c : EE.line)),
          child: Text('${v == 'ALL' ? 'All' : v} $n', style: TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, fontWeight: FontWeight.w600, color: on ? c : EE.textMuted)),
        ),
      );
    }

    return Panel(
      expand: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      eyebrow: 'Findings',
      title: '${widget.filtered.length} of ${widget.all.length}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _q,
          onChanged: widget.onQuery,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded, size: 18), hintText: 'Search subject, value, rule…'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          vchip('ALL', widget.all.length),
          vchip('FAIL', widget.counts['FAIL'] ?? 0),
          vchip('UNCERTAIN', widget.counts['UNCERTAIN'] ?? 0),
          vchip('PASS', widget.counts['PASS'] ?? 0),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: widget.check,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Check'),
              items: [const DropdownMenuItem(value: null, child: Text('All checks')), for (final c in checks) DropdownMenuItem(value: c, child: Text(checkLabels[c] ?? c, overflow: TextOverflow.ellipsis))],
              onChanged: widget.onCheck,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: DropdownButtonFormField<String?>(
              initialValue: widget.zone,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Zone'),
              items: [const DropdownMenuItem(value: null, child: Text('All')), for (final z in zones) DropdownMenuItem(value: z, child: Text(z))],
              onChanged: widget.onZone,
            ),
          ),
        ]),
        Row(children: [
          Checkbox(value: widget.unreviewedOnly, onChanged: (x) => widget.onUnreviewed(x ?? false)),
          const Text('Unreviewed only', style: TextStyle(fontSize: 12.5, color: EE.textMuted)),
        ]),
        const Divider(),
        Expanded(
          child: widget.filtered.isEmpty
              ? const EmptyState(title: 'No findings match', icon: Icons.filter_alt_off_outlined)
              : ListView.builder(
                  itemCount: widget.filtered.length,
                  itemBuilder: (_, i) {
                    final f = widget.filtered[i];
                    return _FindingRow(f: f, selected: f.id == widget.selectedId, onTap: () => widget.onSelect(f.id), onOpen: () => widget.onOpen(f.id));
                  },
                ),
        ),
      ]),
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.f, required this.selected, required this.onTap, required this.onOpen});
  final Finding f;
  final bool selected;
  final VoidCallback onTap, onOpen;

  @override
  Widget build(BuildContext context) {
    final c = EE.verdict(f.effectiveVerdict);
    final conf = f.confidences;
    final confText = [
      if (conf['detector'] != null) 'det ${fmtConf(conf['detector'])}',
      if (conf['ocr'] != null) 'ocr ${fmtConf(conf['ocr'])}',
      if (conf['edit_distance'] != null) 'd=${conf['edit_distance']}',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      onDoubleTap: onOpen,
      child: AnimatedContainer(
        duration: EE.fast,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(EE.r1),
          border: Border(left: BorderSide(color: selected ? c : Colors.transparent, width: 3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 30, child: Text('${f.seq}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textDim))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${f.subject}  ·  ${f.checkLabel}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                if (f.zone != null) Text(f.zone!, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Flexible(child: MonoValue(f.expected ?? '—', color: EE.ice, size: 11.5)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Icon(Icons.east_rounded, size: 11, color: EE.textDim)),
                Flexible(child: MonoValue(f.observed ?? '—', color: f.verdict == 'PASS' ? EE.textMuted : EE.verdict(f.verdict), size: 11.5)),
              ]),
              if (confText.isNotEmpty || f.reasons.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text([confText, if (f.reasons.isNotEmpty) reasonLabels[f.reasons.first] ?? f.reasons.first].where((s) => s.isNotEmpty).join('  ·  '),
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: EE.textDim)),
              ],
            ]),
          ),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            VerdictBadge(f.effectiveVerdict, dense: true, reviewed: f.reviewCount > 0),
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'Evidence & review', onPressed: onOpen, icon: const Icon(Icons.open_in_full_rounded, size: 15)),
          ]),
        ]),
      ),
    );
  }
}

// --- specification ------------------------------------------------------------------------------

class _SpecPanel extends ConsumerWidget {
  const _SpecPanel({required this.version, required this.selected, required this.onZone, required this.zone});
  final Version version;
  final Finding? selected;
  final ValueChanged<String> onZone;
  final String? zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    final d = ref.watch(drawingProvider(version.id));
    final reg = version.registration;
    return Panel(
      expand: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      eyebrow: 'Engineering specification',
      child: AsyncView<Json>(
        d,
        onRetry: () => ref.invalidate(drawingProvider(version.id)),
        data: (dj) {
          if (dj['parsed'] != true) {
            return EmptyState(title: 'No parsed GA drawing', message: dj.strN('message'), icon: Icons.architecture_rounded);
          }
          final dw = dj.obj('drawing');
          final scale = dw.dbl('render_scale') ?? 1.0;
          final size = Size((dw.dbl('width') ?? 0) * scale, (dw.dbl('height') ?? 0) * scale);
          List<double> s(List<double> b) => b.map((x) => x * scale).toList();
          final overlays = <ImgOverlay>[
            for (final z in dj.objs('zones'))
              ImgOverlay(id: 'zone:${z.str('code')}', box: s(z.box('bbox')!), color: zone == z.str('code') ? EE.cyan : EE.violet, label: z.str('code'), dashed: true, fillAlpha: zone == z.str('code') ? 0.08 : 0),
            if (selected?.drawingBbox != null) ImgOverlay(id: 'sel', box: s(selected!.drawingBbox!), color: EE.verdict(selected!.effectiveVerdict), label: selected!.subject),
          ];
          final comps = dj.objs('components');
          final idents = dj.objs('identifiers');
          final notFound = comps.where((c) => c.str('drawing_match') == 'not_found').length + idents.where((i) => i.str('drawing_match') == 'not_found').length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 230,
              child: OverlayImageViewer(url: api.url(dw.str('render_url')), imageSize: size, overlays: overlays, selectedId: selected?.drawingBbox != null ? 'sel' : null, toolbar: false, background: EE.bg1),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(children: [
                _RegistrationCard(reg: reg),
                const SizedBox(height: 10),
                const Text('ZONES', style: TextStyle(fontFamily: EE.fontMono, fontSize: 10, letterSpacing: 1.4, color: EE.textDim)),
                const SizedBox(height: 4),
                for (final z in dj.objs('zones'))
                  InkWell(
                    onTap: () => onZone(z.str('code')),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Icon(zone == z.str('code') ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, size: 14, color: zone == z.str('code') ? EE.cyan : EE.textDim),
                        const SizedBox(width: 8),
                        SizedBox(width: 34, child: Text(z.str('code'), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.violet))),
                        Expanded(child: Text(z.strN('name') ?? '', style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                        Text(z.str('source').replaceAll('_', ' '), style: const TextStyle(fontSize: 10.5, color: EE.textDim)),
                      ]),
                    ),
                  ),
                const Hairline(vertical: 8),
                KV('Page', '${(dw.integer('page_index')) + 1} / ${dw.integer('page_count')} · ${dw.str('kind')}', keyWidth: 110),
                KV('Expected', '${comps.length} components · ${idents.length} wire records', keyWidth: 110),
                KV('Located', notFound == 0 ? 'all identifiers located in drawing' : '$notFound not located', keyWidth: 110, valueColor: notFound == 0 ? EE.pass : EE.uncertain),
                for (final w in dw.objs('warnings').take(4))
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text('⚠ ${w.str('message')}', style: const TextStyle(fontSize: 11.5, color: EE.uncertain))),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => context.go(scopedLink('/console/drawing', version.inspectionId, version: version.no)),
                  icon: const Icon(Icons.architecture_rounded, size: 16),
                  label: const Text('Open Drawing Intelligence'),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _RegistrationCard extends StatelessWidget {
  const _RegistrationCard({required this.reg});
  final Json reg;
  @override
  Widget build(BuildContext context) {
    final status = reg.str('status', 'not run');
    final m = reg.obj('metrics');
    final usable = reg.boolean('usable');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: EE.state(status).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.state(status).withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Photo ↔ drawing registration', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const Spacer(),
          StatePill(status),
        ]),
        const SizedBox(height: 4),
        Text(
          usable
              ? '${reg.strN('method') ?? ''} · ${m['inliers'] ?? '—'} inliers · median error ${m['reprojection_error_median_px'] ?? '—'} px'
              : 'Not usable — position-based checks are UNCERTAIN. ${(reg.strs('reasons')).take(2).join('; ')}',
          style: const TextStyle(fontSize: 11.5, color: EE.textMuted),
        ),
      ]),
    );
  }
}
