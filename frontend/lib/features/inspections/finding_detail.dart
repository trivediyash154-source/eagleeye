import 'dart:math' as math;

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
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';

/// Opens the finding detail side sheet (evidence, expected vs observed, review actions).
Future<void> showFindingDrawer(BuildContext context, String findingId, {VoidCallback? onReviewed}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close finding',
    barrierColor: const Color(0x99020409),
    transitionDuration: EE.med,
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: EE.bg1,
        elevation: 24,
        child: SizedBox(
          width: math.min(760, MediaQuery.sizeOf(ctx).width),
          height: double.infinity,
          child: FindingDetailView(findingId: findingId, onReviewed: onReviewed, onClose: () => Navigator.of(ctx).pop()),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      if (MediaQuery.maybeDisableAnimationsOf(ctx) ?? false) return child;
      return SlideTransition(position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: EE.curve)), child: FadeTransition(opacity: anim, child: child));
    },
  );
}

/// Full finding detail: crops, expected vs observed, char-level diff, rule, separate confidence
/// sources, detection/OCR records, history and persisted review actions.
class FindingDetailView extends ConsumerWidget {
  const FindingDetailView({super.key, required this.findingId, this.onReviewed, this.onClose, this.embedded = false});
  final String findingId;
  final VoidCallback? onReviewed;
  final VoidCallback? onClose;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(findingDetailProvider(findingId));
    return AsyncView<Finding>(
      f,
      onRetry: () => ref.invalidate(findingDetailProvider(findingId)),
      data: (fd) => _Body(f: fd, onClose: onClose, embedded: embedded, onReviewed: () {
        ref.invalidate(findingDetailProvider(findingId));
        ref.invalidate(findingsProvider(fd.versionId));
        onReviewed?.call();
      }),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.f, required this.onReviewed, this.onClose, required this.embedded});
  final Finding f;
  final VoidCallback onReviewed;
  final VoidCallback? onClose;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    final crops = f.evidence.where((e) => e.kind == 'finding_crop' || e.kind == 'finding_crop_annotated').toList();
    final missing = f.evidence.where((e) => e.error != null).toList();
    final comparison = f.details['comparison'] as Map?;
    final ocr = f.ocr;
    final det = f.detection;
    final c = f.confidences;
    final reg = (c['registration'] as Map?)?.cast<String, dynamic>() ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: EE.line))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow('Finding #${f.seq} · ${f.checkLabel}${f.zone != null ? ' · Zone ${f.zone}' : ''}'),
              const SizedBox(height: 6),
              Row(children: [
                Flexible(child: Text(f.subject, style: Theme.of(context).textTheme.headlineSmall, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 12),
                VerdictBadge(f.verdict),
                if (f.reviewCount > 0 && f.effectiveVerdict != f.verdict) ...[
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 14, color: EE.textDim)),
                  VerdictBadge(f.effectiveVerdict, reviewed: true),
                ],
              ]),
            ]),
          ),
          if (!embedded)
            TextButton.icon(
              onPressed: () {
                onClose?.call();
                context.go(workspaceLink(f.inspectionId, version: f.versionNo, finding: f.id));
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('Workspace'),
            ),
          if (onClose != null) IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          // --- evidence crops
          if (crops.isNotEmpty)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in crops.reversed) ...[
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.kind == 'finding_crop' ? 'ORIGINAL PIXELS' : 'ANNOTATED', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10, letterSpacing: 1.4, color: EE.textDim)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(EE.r2),
                      child: Container(
                        color: EE.bg0,
                        constraints: const BoxConstraints(maxHeight: 220),
                        width: double.infinity,
                        child: Image.network(api.url(e.url), fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                      ),
                    ),
                    if (e.bbox != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('crop px ${e.bbox!.map((v) => v.round()).join(', ')}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10, color: EE.textDim)),
                      ),
                  ]),
                ),
                const SizedBox(width: 12),
              ],
            ])
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: EE.line), borderRadius: BorderRadius.circular(EE.r2)),
              child: Text(
                missing.isNotEmpty ? 'No image evidence: ${missing.first.error}' : (f.checkType == 'drawing_alignment' ? 'Whole-image finding — see the registration overlay in the Drawing Intelligence view.' : 'No crop recorded for this finding.'),
                style: const TextStyle(color: EE.textMuted, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 18),
          // --- expected vs observed
          _ExpectedObserved(f: f, comparison: comparison?.cast<String, dynamic>()),
          const SizedBox(height: 16),
          Panel(
            eyebrow: 'Verification rule',
            title: f.rule,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.explanation, style: const TextStyle(fontSize: 13, height: 1.55)),
              if (f.reasons.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final r in f.reasons) ReasonChip(r)]),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          Panel(
            eyebrow: 'Confidence sources (kept separate)',
            child: Column(children: [
              KV('Detector confidence', fmtConf(c['detector']), mono: true),
              KV('OCR confidence', fmtConf(c['ocr']), mono: true),
              KV('Edit distance', c['edit_distance']?.toString(), mono: true),
              KV('Text similarity', fmtConf(c['text_similarity']), mono: true),
              if (c['color_fraction'] != null) KV('Colour fraction', fmtConf(c['color_fraction']), mono: true),
              KV('Registration', '${reg['status'] ?? '—'}${reg['method'] != null ? ' · ${reg['method']}' : ''}${reg['inliers'] != null ? ' · ${reg['inliers']} inliers' : ''}${reg['reprojection_error_median_px'] != null ? ' · ${reg['reprojection_error_median_px']} px' : ''}', mono: true),
              KV('Combined', 'not computed', mono: true, valueColor: EE.textMuted),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text((c['combined_note'] ?? '').toString(), style: const TextStyle(fontSize: 11.5, color: EE.textDim)),
              ),
            ]),
          ),
          if (det != null) ...[
            const SizedBox(height: 16),
            Panel(
              eyebrow: 'Detection',
              child: Column(children: [
                KV('Class', det.str('class_name')),
                KV('Confidence', fmtConf(det['confidence']), mono: true),
                KV('Box (image px)', (det.box('bbox') ?? []).map((v) => v.round()).join(', '), mono: true),
                KV('Source / model', '${det.str('source')} · ${det.str('model_name')}', mono: true),
              ]),
            ),
          ],
          if (ocr != null) ...[
            const SizedBox(height: 16),
            Panel(
              eyebrow: 'OCR observation',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                KV('Raw text', ocr.str('raw_text'), mono: true),
                KV('Normalised', ocr.str('normalized_text'), mono: true),
                KV('Confidence', fmtConf(ocr['confidence']), mono: true),
                KV('Region / variant', '${ocr.str('region')} · ${ocr.str('variant')} · ${ocr.str('engine')}', mono: true),
                const SizedBox(height: 6),
                const Text('Normalisation steps', style: TextStyle(fontSize: 12, color: EE.textDim)),
                const SizedBox(height: 4),
                if (ocr.objs('normalization_steps').isEmpty) const Text('none — raw text already normalised', style: TextStyle(fontSize: 12, color: EE.textMuted)),
                for (final s in ocr.objs('normalization_steps'))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      SizedBox(width: 170, child: Text(s.str('op'), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.ice))),
                      MonoValue("'${s.str('before')}'", color: EE.textMuted, size: 11.5),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_right_alt_rounded, size: 14, color: EE.textDim)),
                      MonoValue("'${s.str('after')}'", size: 11.5),
                    ]),
                  ),
                if (ocr.objs('alternatives').where((a) => a['text'] != null || a['normalized'] != null).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Other readings (not selected — selection is by OCR confidence only)', style: TextStyle(fontSize: 12, color: EE.textDim)),
                  for (final a in ocr.objs('alternatives').where((a) => a['text'] != null || a['normalized'] != null))
                    Text('${a['variant'] ?? a['region'] ?? ''}: ${a['normalized'] ?? a['text']} (${fmtConf(a['confidence'])})', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted)),
                ],
              ]),
            ),
          ],
          if (f.history.isNotEmpty) ...[
            const SizedBox(height: 16),
            Panel(
              eyebrow: 'Same item in other versions',
              child: Column(children: [
                for (final h in f.history)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(width: 50, child: Text('v${h['version_no']}', style: const TextStyle(fontFamily: EE.fontMono))),
                      VerdictBadge(h.str('verdict'), dense: true),
                      const SizedBox(width: 8),
                      if (h.str('effective_verdict') != h.str('verdict')) ...[const Text('→ '), VerdictBadge(h.str('effective_verdict'), dense: true, reviewed: true)],
                      const SizedBox(width: 10),
                      Expanded(child: MonoValue(h.strN('observed_value') ?? '—', color: EE.textMuted)),
                    ]),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          _ReviewSection(f: f, onReviewed: onReviewed),
          const SizedBox(height: 24),
        ]),
      ),
    ]);
  }
}

class _ExpectedObserved extends StatelessWidget {
  const _ExpectedObserved({required this.f, this.comparison});
  final Finding f;
  final Json? comparison;

  @override
  Widget build(BuildContext context) {
    final edits = comparison?.objs('edits') ?? const <Json>[];
    final subPos = {for (final e in edits.where((e) => e['op'] == 'substitute')) e.integer('position'): e.boolean('confusable')};
    Widget box(String label, Widget child, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: c.withValues(alpha: 0.35))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10, letterSpacing: 1.4, color: EE.textDim)),
              const SizedBox(height: 8),
              child,
            ]),
          ),
        );
    final expected = f.expected ?? '—';
    final observed = f.observed ?? '—';
    final exp = comparison?.str('expected') ?? expected;
    final obs = comparison?.str('observed') ?? observed;
    Widget chars(String s, bool isObserved) {
      if (comparison == null) return MonoValue(s, size: 22);
      return Wrap(children: [
        for (var i = 0; i < s.length; i++)
          Container(
            margin: const EdgeInsets.only(right: 1),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: !isObserved && subPos.containsKey(i)
                  ? (subPos[i]! ? EE.uncertain : EE.fail).withValues(alpha: 0.22)
                  : (isObserved && edits.any((e) => e['op'] == 'substitute' && e.integer('position') == i) ? (subPos[i] == true ? EE.uncertain : EE.fail).withValues(alpha: 0.22) : Colors.transparent),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(s[i], style: const TextStyle(fontFamily: EE.fontMono, fontSize: 22, fontWeight: FontWeight.w600, color: EE.text)),
          ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        box('EXPECTED (SPECIFICATION)', chars(exp, false), EE.ice),
        const SizedBox(width: 10),
        box('OBSERVED', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          chars(obs, true),
          if (f.observedRaw != null && f.observedRaw != f.observed)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text("raw OCR: '${f.observedRaw}'", style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted))),
        ]), EE.verdict(f.verdict)),
      ]),
      if (comparison != null) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          Text('Levenshtein d = ${comparison!['levenshtein_distance']}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.textMuted)),
          Text('similarity ${fmtConf(comparison!['normalized_similarity'])}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.textMuted)),
          for (final e in edits)
            Text(
              e['op'] == 'substitute'
                  ? "'${e['expected']}'→'${e['observed']}'${e.boolean('confusable') ? ' (OCR-confusable)' : ''}"
                  : (e['op'] == 'missing' ? "missing '${e['expected']}'" : "extra '${e['observed']}'"),
              style: TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: e.boolean('confusable') ? EE.uncertain : EE.fail),
            ),
        ]),
      ],
    ]);
  }
}

class _ReviewSection extends ConsumerStatefulWidget {
  const _ReviewSection({required this.f, required this.onReviewed});
  final Finding f;
  final VoidCallback onReviewed;
  @override
  ConsumerState<_ReviewSection> createState() => _ReviewSectionState();
}

class _ReviewSectionState extends ConsumerState<_ReviewSection> {
  bool _busy = false;

  List<(String, String, IconData, Color)> _actions() {
    final f = widget.f;
    final label = f.checkType == 'device_label' || f.checkType == 'ferrule_label';
    final a = <(String, String, IconData, Color)>[];
    if (f.verdict == 'FAIL') {
      a.add(('confirm', 'Confirm FAIL', Icons.verified_outlined, EE.fail));
      a.add(('false_positive', 'Mark false positive', Icons.thumb_down_alt_outlined, EE.pass));
    } else if (f.verdict == 'UNCERTAIN') {
      a.add(('resolve_pass', 'Resolve as PASS', Icons.check_circle_outline, EE.pass));
      a.add(('resolve_fail', 'Resolve as FAIL', Icons.cancel_outlined, EE.fail));
    } else {
      a.add(('confirm', 'Confirm PASS', Icons.verified_outlined, EE.pass));
      a.add(('resolve_fail', 'Override to FAIL', Icons.cancel_outlined, EE.fail));
    }
    if (label) a.add(('correct_observed', 'Correct observed label', Icons.edit_outlined, EE.ice));
    a.add(('waive', 'Waive with reason', Icons.do_not_disturb_on_outlined, EE.waived));
    a.add(('mark_reviewed', 'Mark reviewed', Icons.done_all_rounded, EE.textMuted));
    a.add(('note', 'Add note', Icons.sticky_note_2_outlined, EE.textMuted));
    return a;
  }

  Future<void> _do(String action, String title) async {
    final f = widget.f;
    final needsReason = action == 'false_positive' || action == 'waive' || ((action == 'resolve_pass' || action == 'resolve_fail') && f.verdict != 'UNCERTAIN');
    final needsValue = action == 'correct_observed';
    final notes = TextEditingController();
    final reason = TextEditingController();
    final value = TextEditingController(text: needsValue ? (f.observed ?? '') : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Finding #${f.seq} · ${f.subject} · machine verdict ${f.verdict}', style: const TextStyle(color: EE.textMuted, fontSize: 12.5)),
            const SizedBox(height: 14),
            if (needsValue) ...[
              TextField(controller: value, decoration: InputDecoration(labelText: 'Observed value as read by the inspector', helperText: 'Expected: ${f.expected}. Exact match → PASS, any difference → FAIL.')),
              const SizedBox(height: 12),
            ],
            if (needsReason) ...[
              TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (mandatory)'), maxLines: 2),
              const SizedBox(height: 12),
            ],
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Review notes (optional)'), maxLines: 3),
            const SizedBox(height: 12),
            const Text('Recorded as local-demo-reviewer (no authentication in this prototype). The machine finding is not modified.', style: TextStyle(fontSize: 11.5, color: EE.textDim)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save review')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).review(f.id, {
        'action': action,
        if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
        if (reason.text.trim().isNotEmpty) 'reason': reason.text.trim(),
        if (needsValue) 'corrected_value': value.text.trim(),
      });
      if (mounted) showSnack(context, 'Review saved');
      widget.onReviewed();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    return Panel(
      eyebrow: 'Human review',
      title: f.reviews.isEmpty ? 'Not yet reviewed' : 'Effective verdict: ${f.effectiveVerdict}',
      subtitle: 'Reviews are stored as separate records; the machine-generated result stays immutable.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (key, label, icon, color) in _actions())
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _do(key, label),
              icon: Icon(icon, size: 16, color: color),
              label: Text(label),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            ),
        ]),
        if (f.reviews.isNotEmpty) ...[
          const Hairline(),
          for (final r in f.reviews.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.person_outline_rounded, size: 16, color: EE.textDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(titleCase(r.action), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      if (r.resultingVerdict != null) VerdictBadge(r.resultingVerdict!, dense: true, reviewed: true),
                      Text('${r.reviewer} · ${fmtTime(r.createdAt)}', style: const TextStyle(fontSize: 11.5, color: EE.textDim)),
                    ]),
                    if (r.correctedValue != null) Text('Corrected value: ${r.correctedValue}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12)),
                    if (r.reason != null) Text('Reason: ${r.reason}', style: const TextStyle(fontSize: 12.5)),
                    if (r.notes != null) Text(r.notes!, style: const TextStyle(fontSize: 12.5, color: EE.textMuted)),
                  ]),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}
