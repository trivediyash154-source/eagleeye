import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/image_viewer.dart';
import '../../core/widgets/inspection_scope.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import '../detection/analysis_common.dart';
import '../inspections/finding_detail.dart';

final _ocrProvider = FutureProvider.family<List<Json>, String>((ref, versionId) => ref.watch(apiProvider).ocr(versionId));

const _regionLabels = {'full': 'Full image', 'detection_crop': 'Detection crop', 'targeted_crop': 'Targeted crop'};

class OcrPage extends StatelessWidget {
  const OcrPage({super.key, this.inspectionId, this.versionNo});
  final String? inspectionId;
  final int? versionNo;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PageHeader(
        eyebrow: 'Analyze · OCR',
        title: 'OCR & Label Verification',
        description: 'Every recognised text region with its raw reading, normalisation steps and confidence, linked to the device-label and ferrule '
            'findings it supports. Observations are immutable; corrections are recorded as review decisions on the finding.',
      ),
      Expanded(
        child: InspectionScope(
          inspectionId: inspectionId,
          versionNo: versionNo,
          onSelect: (i, v) => context.go(i.isEmpty ? '/console/ocr' : scopedLink('/console/ocr', i, version: v)),
          pickerTitle: 'Select an inspection to review its OCR observations',
          builder: (ctx, insp, ver) => _OcrWorkbench(key: ValueKey(ver.id), inspection: insp, version: ver),
        ),
      ),
    ]);
  }
}

class _OcrWorkbench extends ConsumerStatefulWidget {
  const _OcrWorkbench({super.key, required this.inspection, required this.version});
  final Inspection inspection;
  final Version version;
  @override
  ConsumerState<_OcrWorkbench> createState() => _OcrWorkbenchState();
}

class _OcrWorkbenchState extends ConsumerState<_OcrWorkbench> {
  final _search = TextEditingController();
  String _region = 'all';
  String _link = 'all';
  String _verdict = 'all';
  String? _selected;
  bool _labels = true;
  String _mode = 'interactive';

  Version get v => widget.version;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String linkedVerdict(Json o) => worstVerdict(o.objs('findings').map((f) => f.str('effective_verdict')));

  List<Json> _filter(List<Json> all) {
    final q = _search.text.trim().toUpperCase();
    return all.where((o) {
      if (_region != 'all' && o.str('region') != _region) return false;
      final links = o.objs('findings');
      if (_link == 'linked' && links.isEmpty) return false;
      if (_link == 'unlinked' && links.isNotEmpty) return false;
      if (_verdict != 'all' && !links.any((f) => f.str('effective_verdict') == _verdict)) return false;
      if (q.isNotEmpty) {
        final hay = '${o.str('raw_text')} ${o.str('normalized_text')} ${links.map((f) => f.str('expected_value')).join(' ')}'.toUpperCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    final ocr = ref.watch(_ocrProvider(v.id));
    final media = ref.watch(mediaProvider(v.id));
    if (ocr.hasError) return ErrorView(ocr.error!, onRetry: () => ref.invalidate(_ocrProvider(v.id)));
    if (media.hasError) return ErrorView(media.error!, onRetry: () => ref.invalidate(mediaProvider(v.id)));
    if (!ocr.hasValue || !media.hasValue) return const LoadingView(label: 'Loading OCR observations');
    final all = ocr.requireValue;
    if (all.isEmpty) {
      return EmptyState(
        title: 'No OCR observations for this version',
        message: v.status == 'completed'
            ? 'The OCR stage produced no text regions (or was skipped because no OCR engine was available). Check System Health → OCR engine.'
            : 'Version ${v.no} is "${v.status}". Observations appear after the OCR stage has run.',
        icon: Icons.text_fields_rounded,
      );
    }
    final rows = _filter(all);
    final selected = all.where((o) => o.str('id') == _selected).firstOrNull;
    final photo = mediaImage(api, media.requireValue, _mode == 'evidence' ? 'ocr_overlay' : 'original_photo') ?? mediaImage(api, media.requireValue, 'original_photo');
    final engines = all.map((o) => o.str('engine')).toSet().join(', ');

    final visual = Panel(
      eyebrow: 'Original frame · engine $engines',
      title: _mode == 'evidence' ? 'Server-rendered OCR evidence' : '${rows.length} of ${all.length} text regions',
      expand: true,
      padding: const EdgeInsets.all(EE.s3),
      actions: [
        SegToggle<String>(values: const {'interactive': 'Interactive', 'evidence': 'Evidence image'}, value: _mode, dense: true, onChanged: (m) => setState(() => _mode = m)),
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
              overlays: _mode == 'evidence'
                  ? const []
                  : [
                      for (final o in rows)
                        ImgOverlay(
                          id: o.str('id'),
                          box: o.box('bbox'),
                          color: linkedVerdict(o).isEmpty ? EE.ice : EE.verdict(linkedVerdict(o)),
                          label: '${o.str('normalized_text')} ${(o.dbl('confidence') ?? 0).toStringAsFixed(2)}',
                          dashed: o.str('region') == 'full',
                        ),
                    ],
              selectedId: _mode == 'evidence' ? null : _selected,
              onSelect: (id) => setState(() => _selected = id),
              showLabels: _labels,
              caption: 'Colour = verdict of the linked finding · ice = not linked · dashed = full-image pass',
            ),
    );
    final list = _ObservationList(
      rows: rows,
      total: all.length,
      selected: _selected,
      search: _search,
      region: _region,
      link: _link,
      verdict: _verdict,
      onSearch: () => setState(() {}),
      onRegion: (x) => setState(() => _region = x),
      onLink: (x) => setState(() => _link = x),
      onVerdict: (x) => setState(() => _verdict = x),
      onSelect: (id) => setState(() => _selected = id == _selected ? null : id),
    );
    final detail = selected == null
        ? const Panel(
            eyebrow: 'Observation',
            title: 'Select a text region',
            child: Text('Choose an observation in the list or tap a box on the photo to see the raw reading, normalisation and the findings it supports.',
                style: TextStyle(fontSize: 12.5, color: EE.textMuted, height: 1.5)),
          )
        : _ObservationDetail(obs: selected, inspectionId: widget.inspection.id, versionNo: v.no, onReviewed: () {
            ref.invalidate(_ocrProvider(v.id));
            refreshInspectionData(ref, inspectionId: widget.inspection.id, versionId: v.id);
          });
    const legend = _Legend();

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 1300) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 310, child: list),
          const SizedBox(width: EE.s4),
          Expanded(child: visual),
          const SizedBox(width: EE.s4),
          SizedBox(width: 390, child: ListView(padding: EdgeInsets.zero, children: [detail, const SizedBox(height: EE.s3), legend])),
        ]);
      }
      if (c.maxWidth >= 900) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: visual),
          const SizedBox(width: EE.s4),
          SizedBox(
            width: 380,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 5, child: list),
              const SizedBox(height: EE.s3),
              Expanded(flex: 6, child: ListView(padding: EdgeInsets.zero, children: [detail, const SizedBox(height: EE.s3), legend])),
            ]),
          ),
        ]);
      }
      return ListView(padding: const EdgeInsets.only(bottom: EE.s8), children: [
        SizedBox(height: 420, child: visual),
        const SizedBox(height: EE.s4),
        SizedBox(height: 460, child: list),
        const SizedBox(height: EE.s4),
        detail,
        const SizedBox(height: EE.s3),
        legend,
      ]);
    });
  }
}

class _ObservationList extends StatelessWidget {
  const _ObservationList({
    required this.rows,
    required this.total,
    required this.selected,
    required this.search,
    required this.region,
    required this.link,
    required this.verdict,
    required this.onSearch,
    required this.onRegion,
    required this.onLink,
    required this.onVerdict,
    required this.onSelect,
  });
  final List<Json> rows;
  final int total;
  final String? selected;
  final TextEditingController search;
  final String region, link, verdict;
  final VoidCallback onSearch;
  final ValueChanged<String> onRegion, onLink, onVerdict, onSelect;

  @override
  Widget build(BuildContext context) {
    return Panel(
      eyebrow: 'Text observations',
      title: '${rows.length} / $total',
      expand: true,
      padding: const EdgeInsets.fromLTRB(EE.s3, EE.s2, EE.s3, EE.s2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: search,
          onChanged: (_) => onSearch(),
          style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5),
          decoration: const InputDecoration(hintText: 'Search text or expected value', prefixIcon: Icon(Icons.search_rounded, size: 18)),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          SegToggle<String>(dense: true, values: const {'all': 'All', 'full': 'Full', 'detection_crop': 'Det. crop', 'targeted_crop': 'Targeted'}, value: region, onChanged: onRegion),
          SegToggle<String>(dense: true, values: const {'all': 'Any', 'linked': 'Linked', 'unlinked': 'Unlinked'}, value: link, onChanged: onLink),
          SegToggle<String>(dense: true, values: const {'all': 'All', 'PASS': 'Pass', 'FAIL': 'Fail', 'UNCERTAIN': 'Uncertain'}, value: verdict, onChanged: onVerdict),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No observations match the filters.', style: TextStyle(fontSize: 12, color: EE.textDim)))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _ObsRow(obs: rows[i], selected: rows[i].str('id') == selected, onTap: () => onSelect(rows[i].str('id'))),
                ),
        ),
      ]),
    );
  }
}

class _ObsRow extends StatelessWidget {
  const _ObsRow({required this.obs, required this.selected, required this.onTap});
  final Json obs;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final verdict = _OcrWorkbenchState.linkedVerdict(obs);
    final raw = obs.str('raw_text'), norm = obs.str('normalized_text');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(EE.r1),
      child: AnimatedContainer(
        duration: EE.fast,
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? EE.cyan.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(EE.r1),
          border: Border.all(color: selected ? EE.cyan.withValues(alpha: 0.4) : EE.line.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          Container(width: 3, height: 28, decoration: BoxDecoration(color: verdict.isEmpty ? EE.ice.withValues(alpha: 0.6) : EE.verdict(verdict), borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(norm, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                '${_regionLabels[obs.str('region')] ?? obs.str('region')}${raw != norm ? ' · raw "$raw"' : ''}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: EE.textDim),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          ConfidenceBar(value: obs.dbl('confidence') ?? 0, width: 36, color: verdict.isEmpty ? EE.ice : EE.verdict(verdict)),
          if (verdict.isNotEmpty) ...[const SizedBox(width: 6), VerdictBadge(verdict, dense: true)],
        ]),
      ),
    );
  }
}

class _ObservationDetail extends StatelessWidget {
  const _ObservationDetail({required this.obs, required this.inspectionId, required this.versionNo, required this.onReviewed});
  final Json obs;
  final String inspectionId;
  final int versionNo;
  final VoidCallback onReviewed;

  @override
  Widget build(BuildContext context) {
    final steps = obs.objs('normalization_steps');
    final alts = obs.objs('alternatives').where((a) => a.containsKey('text') || a.containsKey('normalized')).toList();
    final purpose = obs.objs('alternatives').where((a) => a.containsKey('purpose')).map((a) => a.str('purpose')).toList();
    final links = obs.objs('findings');
    final region = obs.str('region');
    return Panel(
      eyebrow: 'Observation · ${_regionLabels[region] ?? region}',
      title: obs.str('normalized_text'),
      actions: [Tag(obs.str('engine'), mono: true, color: EE.ice)],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SubHead('Recorded observation (immutable)'),
        _ValueLine(label: 'Raw OCR', value: obs.str('raw_text')),
        _ValueLine(label: 'Normalised', value: obs.str('normalized_text'), color: EE.cyan),
        Row(children: [
          const SizedBox(width: 92, child: Text('Confidence', style: TextStyle(fontSize: 12, color: EE.textDim))),
          ConfidenceBar(value: obs.dbl('confidence') ?? 0, width: 140),
        ]),
        const SizedBox(height: 4),
        KV('Variant', obs.str('variant'), mono: true, keyWidth: 92),
        KV('Box (px)', fmtBox(obs.box('bbox')), mono: true, keyWidth: 92),
        if (obs.strN('detection_id') != null) KV('Detection', obs.str('detection_id'), mono: true, keyWidth: 92),
        if (purpose.isNotEmpty) KV('Read for', purpose.join(', '), mono: true, keyWidth: 92),
        if (region == 'targeted_crop')
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Targeted read: the verification engine projected the expected position from the GA drawing and ran OCR on that region because no '
                'earlier observation fell inside it.', style: TextStyle(fontSize: 11, color: EE.textDim, height: 1.4)),
          ),
        const SubHead('Normalisation steps'),
        if (steps.isEmpty)
          const Text('No changes: the raw string was already in canonical form. Confusable characters are never rewritten.', style: TextStyle(fontSize: 12, color: EE.textDim))
        else
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.str('op').replaceAll('_', ' '), style: const TextStyle(fontSize: 11.5, color: EE.textMuted, fontWeight: FontWeight.w600)),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                  MonoValue('"${s.str('before')}"', color: EE.textMuted, size: 12),
                  const Icon(Icons.arrow_forward_rounded, size: 13, color: EE.textDim),
                  MonoValue('"${s.str('after')}"', size: 12),
                ]),
                if (s.strN('note') != null) Text(s.str('note'), style: const TextStyle(fontSize: 10.5, color: EE.textDim)),
              ]),
            ),
        if (alts.isNotEmpty) ...[
          const SubHead('Other readings (not selected)'),
          for (final a in alts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 110, child: Text('${a.str('variant')}${a.strN('region') != null ? ' (${a.str('region')})' : ''}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: EE.textDim))),
                Expanded(child: MonoValue(a.strN('normalized') ?? a.str('text'), size: 12)),
                if (a.dbl('confidence') != null) ConfidenceBar(value: a.dbl('confidence')!, width: 44, color: EE.textMuted),
              ]),
            ),
          const Text('The reading with the highest OCR confidence is kept; it is never chosen by similarity to the expected value.', style: TextStyle(fontSize: 10.5, color: EE.textDim, height: 1.4)),
        ],
        const SubHead('Findings supported by this observation'),
        if (links.isEmpty)
          const Text('Not linked to any finding. Text outside expected label/ferrule positions (e.g. ratings, voltages) is recorded for traceability only.',
              style: TextStyle(fontSize: 12, color: EE.textDim, height: 1.4))
        else
          for (final f in links) _LinkedFinding(link: f, observed: obs.str('normalized_text'), inspectionId: inspectionId, versionNo: versionNo, onReviewed: onReviewed),
        const SizedBox(height: 10),
        const NoticeBanner(
          title: 'Corrections never edit this observation',
          lines: ['To correct a misread, open the finding and record a review ("Correct observed label"). The machine observation and verdict stay as recorded; '
              'the review is stored separately with the reviewer identity and time.'],
          color: EE.ice,
          icon: Icons.history_edu_outlined,
        ),
      ]),
    );
  }
}

class _ValueLine extends StatelessWidget {
  const _ValueLine({required this.label, required this.value, this.color = EE.text});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 12, color: EE.textDim))),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: EE.line)),
              child: SelectableText(value.isEmpty ? '∅' : value, style: TextStyle(fontFamily: EE.fontMono, fontSize: 14, fontWeight: FontWeight.w600, color: color)),
            ),
          ),
        ]),
      );
}

class _LinkedFinding extends StatelessWidget {
  const _LinkedFinding({required this.link, required this.observed, required this.inspectionId, required this.versionNo, required this.onReviewed});
  final Json link;
  final String observed;
  final String inspectionId;
  final int versionNo;
  final VoidCallback onReviewed;

  @override
  Widget build(BuildContext context) {
    final eff = link.str('effective_verdict');
    final machine = link.str('verdict');
    final expected = link.strN('expected_value');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.verdict(eff).withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('#${link.integer('seq')}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.textMuted)),
          const SizedBox(width: 8),
          Expanded(child: Text(checkLabels[link.str('check_type')] ?? link.str('check_type'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          VerdictBadge(eff, dense: true, reviewed: link.integer('review_count') > 0),
        ]),
        if (eff != machine)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Machine verdict $machine · changed by human review', style: const TextStyle(fontSize: 11, color: EE.textDim))),
        const SizedBox(height: 8),
        if (expected != null) CharDiff(expected: expected, observed: observed) else const Text('No expected text for this finding.', style: TextStyle(fontSize: 12, color: EE.textDim)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          TextButton.icon(
            onPressed: () => showFindingDrawer(context, link.str('finding_id'), onReviewed: onReviewed),
            icon: const Icon(Icons.rate_review_outlined, size: 15),
            label: const Text('Review finding'),
          ),
          TextButton.icon(
            onPressed: () => context.go(workspaceLink(inspectionId, version: versionNo, finding: link.str('finding_id'))),
            icon: const Icon(Icons.view_quilt_outlined, size: 15),
            label: const Text('Open in workspace'),
          ),
        ]),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget row(String exp, String obs, String verdict, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              VerdictBadge(verdict, dense: true),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 11.5, color: EE.textMuted, height: 1.4))),
            ]),
            const SizedBox(height: 4),
            _MiniDiff(expected: exp, observed: obs),
          ]),
        );
    return Panel(
      eyebrow: 'Matching policy · confusion-aware',
      title: 'How readings become verdicts',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row('X12-1A', 'X12-1A', 'PASS', 'Exact match after normalisation, OCR confidence above the pass threshold, reliable position association.'),
        row('X12-6B', 'X12-68', 'UNCERTAIN', 'Differences are only visually confusable characters (8↔B, 0↔O, 1↔I, 5↔S…). Could be a misread or a misprint — a human decides.'),
        row('X12-4B', 'X12-8B', 'FAIL', 'A non-confusable substitution (4→8) read with reliable confidence at the expected position: a confirmed mismatch.'),
        const SizedBox(height: 4),
        const Text('Unreadable text, low confidence, partial reads and unreliable associations are UNCERTAIN — never FAIL. Thresholds are configurable per identifier type.',
            style: TextStyle(fontSize: 11, color: EE.textDim, height: 1.4)),
      ]),
    );
  }
}

class _MiniDiff extends StatelessWidget {
  const _MiniDiff({required this.expected, required this.observed});
  final String expected, observed;
  @override
  Widget build(BuildContext context) {
    final cells = alignChars(expected, observed);
    Widget c(String? ch, DiffCell d) {
      final col = d.op == DiffOp.match ? EE.textMuted : (d.confusable ? EE.uncertain : EE.fail);
      return Container(
        width: 15,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
        decoration: BoxDecoration(color: d.op == DiffOp.match ? Colors.transparent : col.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
        child: Text(ch ?? '∅', style: TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: col, fontWeight: FontWeight.w600)),
      );
    }

    return Row(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [for (final d in cells) c(d.expected, d)]),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('vs', style: TextStyle(fontSize: 10.5, color: EE.textDim))),
      Row(mainAxisSize: MainAxisSize.min, children: [for (final d in cells) c(d.observed, d)]),
    ]);
  }
}
