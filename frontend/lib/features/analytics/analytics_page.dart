import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/kpi.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import '../dashboard/dashboard_widgets.dart';

/// Analytics & Insights: outcome analytics computed from persisted records, with sample size
/// and basis always visible. Model accuracy is deliberately not reported (no ground truth).
class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  DateRangeSpec _range = const DateRangeSpec(RangeKey.all);
  Json? _last;

  @override
  Widget build(BuildContext context) {
    final ds = ref.watch(datasetProvider);
    final q = (dataset: ds, from: _range.fromIso, to: _range.toIso);
    final live = ref.watch(analyticsProvider(q));
    if (live.hasValue) _last = live.requireValue;
    final stale = !live.hasValue && !live.hasError && _last != null;
    final value = stale ? AsyncValue<Json>.data(_last!) : live;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          eyebrow: 'Assure · Analytics & insights',
          title: 'Inspection outcome analytics',
          description: 'Every chart below is computed from persisted inspection records. Sample sizes and the statistical basis are shown with the data; '
              'demonstration inspections can be excluded with the dataset filter.',
          actions: [
            const DatasetToggle(),
            RangeSelector(value: _range, allowCustom: true, onChanged: (r) => setState(() => _range = r)),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded, size: 18), onPressed: () => ref.invalidate(analyticsProvider(q))),
          ],
        ),
        SizedBox(height: 3, child: stale ? const LinearProgressIndicator(minHeight: 1.5) : null),
        AsyncView<Json>(
          value,
          onRetry: () => ref.invalidate(analyticsProvider(q)),
          loadingLabel: 'Computing analytics',
          data: (a) => _Body(data: a, range: _range),
        ),
      ]),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data, required this.range});
  final Json data;
  final DateRangeSpec range;

  Map<String, int> _ints(Json m) => m.map((k, v) => MapEntry(k, (v as num).toInt()));

  @override
  Widget build(BuildContext context) {
    final k = data.obj('kpis');
    final sample = data.obj('basis').obj('sample');
    final noFindings = sample.integer('findings') == 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BasisStrip(data: data, range: range),
      const SizedBox(height: EE.s3),
      _AccuracyNotice(note: data.obj('accuracy').str('note')),
      const SizedBox(height: EE.s4),
      ResponsiveRow(breakpoint: 1100, flex: const [3, 2], children: [
        _VolumeByDate(data: data, range: range),
        Panel(
          eyebrow: 'Verdict distribution',
          title: 'Machine vs after human review',
          subtitle: 'Latest completed version per inspection · ${sample.integer('findings')} findings',
          child: noFindings
              ? const EmptyState(title: 'No findings in scope', icon: Icons.donut_large_rounded)
              : Wrap(alignment: WrapAlignment.spaceEvenly, spacing: 20, runSpacing: 18, children: [
                  _DonutWithCaption(caption: 'MACHINE', counts: _ints(data.obj('machine_verdicts'))),
                  _DonutWithCaption(caption: 'AFTER REVIEW', counts: _ints(data.obj('effective_verdicts'))),
                ]),
        ),
      ]),
      const SizedBox(height: EE.s4),
      ResponsiveRow(breakpoint: 1100, flex: const [3, 2], children: [
        _Categories(data: data),
        Panel(
          eyebrow: 'Human oversight',
          title: 'Review workload',
          subtitle: 'Open items that require an inspector decision.',
          actions: [TextButton(onPressed: () => context.go('/console/review'), child: const Text('Open queue'))],
          child: KpiGrid(minTileWidth: 150, children: [
            Kpi(label: 'Review queue', value: '${k.integer('review_queue_size')}', sub: 'UNCERTAIN + unreviewed FAIL', accent: EE.uncertain, onTap: () => context.go('/console/review')),
            Kpi(label: 'Uncertain items', value: '${k.integer('uncertain_items')}', sub: 'after review', accent: EE.uncertain),
            Kpi(label: 'Inspections to review', value: '${k.integer('inspections_requiring_review')}', sub: 'latest versions', accent: EE.ice),
            Kpi(label: 'Waived items', value: '${k.integer('waived_items')}', sub: 'with recorded reason', accent: EE.waived),
          ]),
        ),
      ]),
      const SizedBox(height: EE.s4),
      ResponsiveRow(breakpoint: 1100, children: [
        _Reinspection(data: data),
        _MismatchPatterns(data: data),
      ]),
      const SizedBox(height: EE.s4),
      ResponsiveRow(breakpoint: 1100, flex: const [2, 3], children: [
        _Gauges(data: data),
        _Registration(data: data),
      ]),
      const SizedBox(height: EE.s4),
      ResponsiveRow(breakpoint: 1100, children: [
        _Detections(data: data),
        _Durations(data: data),
      ]),
      const SizedBox(height: EE.s4),
      _Limitations(data: data),
    ]);
  }
}

class _AccuracyNotice extends StatelessWidget {
  const _AccuracyNotice({required this.note});
  final String note;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(EE.r2),
          border: Border.all(color: EE.violet.withValues(alpha: 0.4)),
          color: EE.violet.withValues(alpha: 0.06),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.rule_rounded, size: 18, color: EE.ultraviolet),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Model accuracy: not measured', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 3),
              Text(
                '$note Verdict counts describe what the system concluded on the inspected cabinets — they are not accuracy rates. '
                'Detector training metrics (synthetic validation only) are shown with their caveat in Model Diagnostics.',
                style: const TextStyle(fontSize: 12, color: EE.textMuted, height: 1.45),
              ),
            ]),
          ),
          TextButton(onPressed: () => context.go('/console/models'), child: const Text('Model diagnostics')),
        ]),
      );
}

class _DonutWithCaption extends StatelessWidget {
  const _DonutWithCaption({required this.caption, required this.counts});
  final String caption;
  final Map<String, int> counts;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        VerdictDonut(counts: counts, size: 150, centerLabel: caption),
        const SizedBox(height: 10),
        VerdictLegend(counts: counts, includeWaived: caption != 'MACHINE'),
      ]);
}

class _VolumeByDate extends StatelessWidget {
  const _VolumeByDate({required this.data, required this.range});
  final Json data;
  final DateRangeSpec range;

  @override
  Widget build(BuildContext context) {
    final vol = data.objs('volume_by_day');
    final (from, to) = range.window(vol);
    final points = fillDays(vol, from, to);
    final runs = points.fold<int>(0, (a, p) => a + p.runs);
    final active = points.where((p) => p.runs > 0).length;
    return Panel(
      eyebrow: 'Inspection volume by date',
      title: '$runs run${runs == 1 ? '' : 's'} on $active day${active == 1 ? '' : 's'}',
      subtitle: '${fmtDate(from)} – ${fmtDate(to)} · every run counted, including reinspections',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 16, runSpacing: 6, children: const [
          LegendDot(color: EE.cyan, label: 'Completed', square: true),
          LegendDot(color: EE.fail, label: 'Failed', square: true),
          LegendDot(color: EE.textDim, label: 'Other', square: true),
        ]),
        const SizedBox(height: 12),
        Stack(children: [
          VolumeChart(points: points, height: 230),
          if (runs == 0)
            const Positioned.fill(
              child: IgnorePointer(child: Center(child: Text('No runs in this range', style: TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textDim)))),
            ),
        ]),
      ]),
    );
  }
}

class _Categories extends StatelessWidget {
  const _Categories({required this.data});
  final Json data;

  @override
  Widget build(BuildContext context) {
    final cats = data.objs('finding_categories');
    return Panel(
      eyebrow: 'Finding categories',
      title: 'Verdicts by check type',
      subtitle: 'After human review · bar length is proportional to the number of findings',
      child: cats.isEmpty
          ? const EmptyState(title: 'No findings in scope', icon: Icons.stacked_bar_chart_rounded)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 14, runSpacing: 6, children: [for (final v in verdictOrder) LegendDot(color: EE.verdict(v), label: v, square: true)]),
              const SizedBox(height: 10),
              StackedVerdictBars(
                labelWidth: 160,
                rows: [
                  for (final c in cats)
                    StackRow(checkLabels[c.str('check_type')] ?? c.str('check_type'), {
                      for (final v in verdictOrder)
                        if (c.integer(v) > 0) v: c.integer(v),
                    }),
                ],
              ),
            ]),
    );
  }
}

class _Reinspection extends StatelessWidget {
  const _Reinspection({required this.data});
  final Json data;

  @override
  Widget build(BuildContext context) {
    final r = data.obj('reinspection_outcomes');
    final rate = data.obj('kpis').dbl('reinspection_rate');
    final entries = r.entries.toList()..sort((a, b) => (b.value as num).compareTo(a.value as num));
    return Panel(
      eyebrow: 'Reinspection outcomes',
      title: 'What changed between versions',
      subtitle: 'Reinspection rate ${pct(rate)} · a discrepancy is resolved only when the new run verifies it as PASS',
      child: entries.isEmpty
          ? const EmptyState(
              title: 'No reinspections compared yet',
              message: 'Create a reinspection from Inspection History after correcting a cabinet to see resolved, persistent and new discrepancies.',
              icon: Icons.compare_arrows_rounded,
            )
          : HBarList(labelWidth: 170, items: [
              for (final e in entries) BarItem(comparisonLabels[e.key] ?? e.key, (e.value as num).toInt(), color: comparisonColor(e.key)),
            ]),
    );
  }
}

class _MismatchPatterns extends StatelessWidget {
  const _MismatchPatterns({required this.data});
  final Json data;

  @override
  Widget build(BuildContext context) {
    final subs = data.objs('substitution_patterns');
    final rep = data.objs('repeated_mismatches');
    return Panel(
      eyebrow: 'Common mismatch patterns',
      title: 'Label and ferrule differences',
      subtitle: 'Character substitutions (expected → observed) recorded by the matching engine, and subjects not verified as PASS',
      child: subs.isEmpty && rep.isEmpty
          ? const EmptyState(title: 'No label or ferrule mismatches in scope', icon: Icons.text_fields_rounded)
          : ResponsiveRow(breakpoint: 520, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SUBSTITUTIONS', style: TextStyle(fontFamily: EE.fontMono, fontSize: 10, letterSpacing: 1.3, color: EE.textMuted)),
                const SizedBox(height: 8),
                if (subs.isEmpty)
                  const Text('None recorded', style: TextStyle(fontSize: 12, color: EE.textDim))
                else
                  HBarList(labelWidth: 56, items: [for (final s in subs) BarItem(s.str('pattern'), s.integer('count'), color: EE.ice, mono: true)]),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SUBJECTS NOT VERIFIED', style: TextStyle(fontFamily: EE.fontMono, fontSize: 10, letterSpacing: 1.3, color: EE.textMuted)),
                const SizedBox(height: 8),
                if (rep.isEmpty)
                  const Text('None', style: TextStyle(fontSize: 12, color: EE.textDim))
                else
                  for (final r in rep)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(child: Text(subjectLabel(r.str('subject')), overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5))),
                        Text('×${r.integer('count')}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.uncertain, fontWeight: FontWeight.w600)),
                      ]),
                    ),
              ]),
            ]),
    );
  }
}

class _Gauges extends StatelessWidget {
  const _Gauges({required this.data});
  final Json data;

  @override
  Widget build(BuildContext context) {
    final ocr = data.obj('ocr_unreadable');
    final k = data.obj('kpis');
    return Panel(
      eyebrow: 'OCR & evidence',
      title: 'Readability and traceability',
      child: Wrap(alignment: WrapAlignment.spaceAround, spacing: 16, runSpacing: 16, children: [
        RatioGauge(
          value: ocr.dbl('rate'),
          label: 'OCR unreadable',
          sub: '${ocr.integer('unreadable')} of ${ocr.integer('label_findings')} label/ferrule findings\nhad no readable text',
          color: EE.uncertain,
        ),
        RatioGauge(
          value: k.dbl('evidence_completeness'),
          label: 'Evidence completeness',
          sub: 'findings with an image crop\n(alignment findings excluded)',
          color: EE.pass,
        ),
      ]),
    );
  }
}

class _Registration extends StatelessWidget {
  const _Registration({required this.data});
  final Json data;

  static Color _c(String k) => switch (k) {
        'aligned' || 'manual' => EE.pass,
        'insufficient' => EE.uncertain,
        'failed' => EE.fail,
        _ => EE.textDim,
      };

  static const _labels = {
    'aligned': 'Aligned (automatic)',
    'manual': 'Aligned (manual anchors)',
    'insufficient': 'Rejected by quality checks',
    'failed': 'Failed',
    'unavailable': 'Unavailable (no drawing)',
    'not_run': 'Not run',
  };

  @override
  Widget build(BuildContext context) {
    final r = data.obj('registration_outcomes');
    final total = r.values.fold<int>(0, (a, b) => a + (b as num).toInt());
    final ok = (r['aligned'] as num? ?? 0).toInt() + (r['manual'] as num? ?? 0).toInt();
    return Panel(
      eyebrow: 'Registration outcomes',
      title: total == 0 ? 'No completed runs in scope' : '$ok of $total completed runs registered',
      subtitle: 'Photo-to-drawing registration status per completed run. Without registration, position-based checks are UNCERTAIN.',
      child: total == 0
          ? const EmptyState(title: 'No registration attempts yet', icon: Icons.architecture_rounded)
          : HBarList(labelWidth: 190, items: [
              for (final e in r.entries) BarItem(_labels[e.key] ?? e.key, (e.value as num).toInt(), color: _c(e.key)),
            ]),
    );
  }
}

class _Detections extends StatelessWidget {
  const _Detections({required this.data});
  final Json data;

  @override
  Widget build(BuildContext context) {
    final d = data.obj('detections_by_class');
    final total = d.values.fold<int>(0, (a, b) => a + (b as num).toInt());
    return Panel(
      eyebrow: 'Detections by class',
      title: '$total detections above threshold',
      subtitle: 'Latest completed versions · only classes the loaded detector supports can appear',
      actions: [TextButton(onPressed: () => context.go('/console/detection'), child: const Text('Component detection'))],
      child: d.isEmpty
          ? const EmptyState(title: 'No detections in scope', message: 'A generic COCO model or an empty scope produces no cabinet-class detections.', icon: Icons.center_focus_weak_rounded)
          : HBarList(labelWidth: 130, items: [
              for (final e in d.entries) BarItem(e.key.replaceAll('_', ' '), (e.value as num).toInt(), color: EE.detClass(e.key)),
            ]),
    );
  }
}

class _Durations extends StatelessWidget {
  const _Durations({required this.data});
  final Json data;

  @override
  Widget build(BuildContext context) {
    final bins = data.objs('duration_histogram');
    final k = data.obj('kpis');
    final n = bins.fold<int>(0, (a, b) => a + b.integer('count'));
    String label(Json b) {
      final from = b.integer('from_s');
      final to = b.intN('to_s');
      return to == null ? '$from s+' : '$from–$to s';
    }

    return Panel(
      eyebrow: 'Processing-duration distribution',
      title: k.intN('avg_processing_ms') == null ? 'No completed runs' : 'Mean ${fmtMs(k.intN('avg_processing_ms'))} · median ${fmtMs(k.intN('median_processing_ms'))}',
      subtitle: 'Measured wall-clock time of $n completed run${n == 1 ? '' : 's'} on this deployment (hardware dependent)',
      child: n == 0
          ? const EmptyState(title: 'No completed runs in scope', icon: Icons.timer_outlined)
          : Histogram(bins: [for (final b in bins) HistBin(label(b), b.integer('count'))], color: EE.violet, height: 210),
    );
  }
}

class _Limitations extends StatelessWidget {
  const _Limitations({required this.data});
  final Json data;

  @override
  Widget build(BuildContext context) {
    final b = data.obj('basis');
    final s = b.obj('sample');
    final items = <String>[
      'Sample size: ${s.integer('inspections')} inspection(s), ${s.integer('completed_runs')} completed run(s), ${s.integer('findings')} finding(s). Small samples do not support trend conclusions.',
      if (b.integer('demo_inspections') > 0 && b.str('dataset') != 'real')
        '${b.integer('demo_inspections')} demonstration inspection(s) built from SYNTHETIC fixtures are included. Use "Real only" to exclude them.',
      'Verdict statistics use the latest completed version of each inspection so reinspected cabinets are not double counted; volume and duration use every run.',
      '"After review" figures reflect human decisions recorded in the review workflow; machine verdicts are never overwritten.',
      'Confidence values are engine-reported scores, not calibrated probabilities; no combined confidence is computed.',
      'Processing durations depend on hardware (CPU vs GPU) and image resolution.',
    ];
    return Panel(
      eyebrow: 'Interpretation',
      title: 'Limitations of these figures',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final t in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 4, color: EE.textDim)),
              const SizedBox(width: 10),
              Expanded(child: Text(t, style: const TextStyle(fontSize: 12.5, color: EE.textMuted, height: 1.45))),
            ]),
          ),
      ]),
    );
  }
}
