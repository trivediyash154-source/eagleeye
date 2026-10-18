import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';

// ---------------------------------------------------------------------------
// Data providers (dashboard + analytics)
// ---------------------------------------------------------------------------

typedef AnalyticsQuery = ({String dataset, String? from, String? to});

final analyticsProvider = FutureProvider.family<Json, AnalyticsQuery>(
  (ref, q) => ref.watch(apiProvider).analytics(dataset: q.dataset, dateFrom: q.from, dateTo: q.to),
);

final activityFeedProvider = FutureProvider.family<List<Json>, String>(
  (ref, dataset) => ref.watch(apiProvider).activity(limit: 14, dataset: dataset),
);

// ---------------------------------------------------------------------------
// Date ranges
// ---------------------------------------------------------------------------

enum RangeKey { d7, d30, d90, all, custom }

class DateRangeSpec {
  const DateRangeSpec(this.key, {this.customFrom, this.customTo});
  final RangeKey key;
  final DateTime? customFrom;
  final DateTime? customTo;

  static const labels = {RangeKey.d7: '7d', RangeKey.d30: '30d', RangeKey.d90: '90d', RangeKey.all: 'All'};

  DateTime get today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime? get from => switch (key) {
        RangeKey.d7 => today.subtract(const Duration(days: 6)),
        RangeKey.d30 => today.subtract(const Duration(days: 29)),
        RangeKey.d90 => today.subtract(const Duration(days: 89)),
        RangeKey.all => null,
        RangeKey.custom => customFrom,
      };

  DateTime? get to => key == RangeKey.custom ? customTo : null;

  String? get fromIso => from == null ? null : DateFormat('yyyy-MM-dd').format(from!);
  String? get toIso => to == null ? null : DateFormat('yyyy-MM-dd').format(to!);

  String get describe => switch (key) {
        RangeKey.d7 => 'last 7 days',
        RangeKey.d30 => 'last 30 days',
        RangeKey.d90 => 'last 90 days',
        RangeKey.all => 'all time',
        RangeKey.custom => '${fmtDate(customFrom)} – ${fmtDate(customTo)}',
      };

  /// Chart window: explicit range, or first recorded day → today for "all".
  (DateTime, DateTime) window(List<Json> volume) {
    final end = to ?? today;
    if (from != null) return (from!, end);
    if (volume.isEmpty) return (end.subtract(const Duration(days: 13)), end);
    final first = DateTime.tryParse(volume.first.str('date')) ?? end;
    final start = end.difference(first).inDays < 6 ? end.subtract(const Duration(days: 6)) : first;
    return (start, end);
  }
}

class RangeSelector extends StatelessWidget {
  const RangeSelector({super.key, required this.value, required this.onChanged, this.allowCustom = false});
  final DateRangeSpec value;
  final ValueChanged<DateRangeSpec> onChanged;
  final bool allowCustom;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Segmented<RangeKey>(
        options: {...DateRangeSpec.labels, if (allowCustom && value.key == RangeKey.custom) RangeKey.custom: 'Custom'},
        value: value.key,
        onChanged: (k) {
          if (k != RangeKey.custom) onChanged(DateRangeSpec(k));
        },
      ),
      if (allowCustom) ...[
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Custom date range',
          icon: const Icon(Icons.date_range_rounded, size: 18),
          onPressed: () async {
            final now = DateTime.now();
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year, now.month, now.day),
              initialDateRange: value.key == RangeKey.custom && value.customFrom != null && value.customTo != null
                  ? DateTimeRange(start: value.customFrom!, end: value.customTo!)
                  : null,
            );
            if (r != null) onChanged(DateRangeSpec(RangeKey.custom, customFrom: r.start, customTo: r.end));
          },
        ),
      ],
    ]);
  }
}

class DatasetToggle extends ConsumerWidget {
  const DatasetToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = ref.watch(datasetProvider);
    return Segmented<String>(
      options: const {'all': 'All data', 'real': 'Real only', 'demo': 'Demo only'},
      tooltips: const {
        'all': 'Real and demonstration inspections',
        'real': 'Exclude demonstration (synthetic fixture) inspections',
        'demo': 'Only demonstration inspections built from synthetic fixtures',
      },
      value: ds,
      onChanged: (v) => ref.read(datasetProvider.notifier).set(v),
    );
  }
}

/// Starts the bundled sample inspection (live pipeline on synthetic fixtures) and opens Live view.
Future<void> runSampleInspection(BuildContext context, WidgetRef ref) async {
  final api = ref.read(apiProvider);
  try {
    final res = await api.sampleInspection();
    final job = res.objN('job');
    ref.invalidate(recentInspectionsProvider);
    if (!context.mounted) return;
    showSnack(context, 'Sample inspection created from synthetic fixtures — running the live pipeline.');
    if (job != null) {
      context.go('/console/live?job=${job.str('id')}');
    } else {
      final insp = res.obj('inspection');
      context.go(workspaceLink(insp.str('id')));
    }
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, 'Could not start sample inspection: ${e.message}', error: true);
  }
}

// ---------------------------------------------------------------------------
// System readiness
// ---------------------------------------------------------------------------

const stateMeaning = {
  'ok': 'Operational',
  'degraded': 'Degraded',
  'loading': 'Loading',
  'not_loaded': 'Not loaded',
  'unavailable': 'Unavailable',
  'disabled': 'Disabled',
  'error': 'Error',
};

const _componentIcons = {
  'api': Icons.api_rounded,
  'database': Icons.storage_rounded,
  'storage': Icons.folder_open_rounded,
  'detector': Icons.center_focus_weak_rounded,
  'ocr': Icons.text_fields_rounded,
  'pdf_parser': Icons.picture_as_pdf_outlined,
  'registration': Icons.architecture_rounded,
  'report_generator': Icons.description_outlined,
};

class ReadinessGrid extends ConsumerStatefulWidget {
  const ReadinessGrid({super.key, this.compact = false});
  final bool compact;

  @override
  ConsumerState<ReadinessGrid> createState() => _ReadinessGridState();
}

class _ReadinessGridState extends ConsumerState<ReadinessGrid> {
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ref.read(apiProvider).loadModels();
      if (mounted) {
        showSnack(context, 'Detector ${r['detector_loaded'] == true ? 'loaded' : 'not loaded'} · OCR ${r['ocr_loaded'] == true ? 'loaded' : 'not loaded'}',
            error: r['detector_loaded'] != true || r['ocr_loaded'] != true);
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      await ref.read(systemStatusProvider.notifier).refresh();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(systemStatusProvider);
    final s = status.value;
    final needsLoad = s != null && s.components.any((c) => (c.key == 'detector' || c.key == 'ocr') && c.state == 'not_loaded');
    return Panel(
      eyebrow: 'H · System readiness',
      title: 'Subsystem status',
      subtitle: 'Real health checks — an unloaded model, an unavailable service and a degraded model are reported differently.',
      actions: [
        if (needsLoad)
          OutlinedButton.icon(
            onPressed: _loading ? null : _load,
            icon: _loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.bolt_rounded, size: 16),
            label: Text(_loading ? 'Loading models…' : 'Load models now'),
          ),
        if (!widget.compact) ...[
          const SizedBox(width: 6),
          TextButton(onPressed: () => context.go('/console/health'), child: const Text('System health')),
        ],
      ],
      child: status.hasError && s == null
          ? ErrorView(status.error!, compact: true, onRetry: () => ref.read(systemStatusProvider.notifier).refresh())
          : s == null
              ? const LoadingView(label: 'Checking subsystems')
              : LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth > 1100 ? 4 : (c.maxWidth > 700 ? 3 : (c.maxWidth > 440 ? 2 : 1));
                  final w = (c.maxWidth - (cols - 1) * 10) / cols;
                  return Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final comp in s.components) SizedBox(width: w, child: _ComponentTile(comp)),
                  ]);
                }),
    );
  }
}

class _ComponentTile extends StatelessWidget {
  const _ComponentTile(this.c);
  final SystemComponent c;

  @override
  Widget build(BuildContext context) {
    final col = EE.state(c.state);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EE.bg1,
        borderRadius: BorderRadius.circular(EE.r2),
        border: Border(left: BorderSide(color: col, width: 2), top: const BorderSide(color: EE.line), right: const BorderSide(color: EE.line), bottom: const BorderSide(color: EE.line)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_componentIcons[c.key] ?? Icons.settings_outlined, size: 18, color: col),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(c.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              Text((stateMeaning[c.state] ?? c.state).toUpperCase(), style: TextStyle(fontFamily: EE.fontMono, fontSize: 9.5, letterSpacing: 1, color: col, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            Tooltip(
              message: c.message,
              child: Text(c.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: EE.textMuted, height: 1.35)),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity feed
// ---------------------------------------------------------------------------

class ActivityFeed extends ConsumerWidget {
  const ActivityFeed({super.key, this.maxItems = 10});
  final int maxItems;

  static (IconData, Color, String) describe(String type) => switch (type) {
        'run_completed' => (Icons.check_circle_outline_rounded, EE.pass, 'Run completed'),
        'run_failed' => (Icons.error_outline_rounded, EE.fail, 'Run failed'),
        'run_started' => (Icons.play_circle_outline_rounded, EE.cyan, 'Run started'),
        'run_cancelled' => (Icons.cancel_outlined, EE.textDim, 'Run cancelled'),
        'inspection_created' => (Icons.add_box_outlined, EE.ice, 'Inspection created'),
        'review_recorded' => (Icons.fact_check_outlined, EE.violet, 'Review recorded'),
        'reinspection_created' => (Icons.replay_rounded, EE.ultraviolet, 'Reinspection created'),
        'report_generated' => (Icons.picture_as_pdf_outlined, EE.textMuted, 'Report generated'),
        _ => (Icons.circle_outlined, EE.textMuted, titleCase(type)),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = ref.watch(datasetProvider);
    final feed = ref.watch(activityFeedProvider(ds));
    return Panel(
      eyebrow: 'E · Activity',
      title: 'Inspection activity feed',
      actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded, size: 17), onPressed: () => ref.invalidate(activityFeedProvider(ds)))],
      child: AsyncView<List<Json>>(
        feed,
        onRetry: () => ref.invalidate(activityFeedProvider(ds)),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(title: 'No activity yet', message: 'Runs, reviews and reports appear here as they happen.', icon: Icons.timeline_rounded);
          }
          final shown = items.take(maxItems).toList();
          return Column(children: [
            for (var i = 0; i < shown.length; i++) _ActivityRow(a: shown[i], last: i == shown.length - 1),
          ]);
        },
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.a, required this.last});
  final Json a;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = ActivityFeed.describe(a.str('event_type'));
    final summary = a.objN('summary');
    final ver = a.intN('version_no');
    final total = summary?.intN('total');
    final dur = a.intN('duration_ms');
    return InkWell(
      onTap: () => context.go(workspaceLink(a.str('inspection_id'), version: ver)),
      borderRadius: BorderRadius.circular(EE.r1),
      child: Stack(children: [
        if (!last) Positioned(left: 12.5, top: 30, bottom: 0, child: Container(width: 1, color: EE.line)),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 26,
            child: Padding(padding: const EdgeInsets.only(top: 9), child: Icon(icon, size: 16, color: color)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(a.str('inspection_code'), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.cyan, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label + (ver != null ? ' · v$ver' : ''), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500))),
                  Text(ago(a.time('created_at')), style: const TextStyle(fontSize: 11, color: EE.textDim)),
                ]),
                const SizedBox(height: 3),
                Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Cabinet ${a.str('cabinet_id')}', style: const TextStyle(fontSize: 11, color: EE.textMuted)),
                  if (a.strN('status') != null) StatePill(a.str('status')),
                  if (total != null) Text('$total findings', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textMuted)),
                  if (summary != null && total != null)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final k in const ['pass', 'fail', 'uncertain'])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text('${summary.integer(k)}', style: TextStyle(fontFamily: EE.fontMono, fontSize: 11, fontWeight: FontWeight.w600, color: EE.verdict(k.toUpperCase()))),
                        ),
                    ]),
                  if (dur != null) Text(fmtMs(dur), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim)),
                  if (a.boolean('is_demo')) const DemoTag(compact: true),
                ]),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Quality intelligence (computed from records)
// ---------------------------------------------------------------------------

const comparisonLabels = {
  'resolved': 'Resolved',
  'persistent': 'Persistent',
  'unconfirmed': 'Unconfirmed (open)',
  'new_discrepancy': 'New discrepancy',
  'still_uncertain': 'Still uncertain',
  'clarified_pass': 'Clarified → PASS',
  'clarified_fail': 'Clarified → FAIL',
  'regressed_to_uncertain': 'Regressed → UNCERTAIN',
  'unchanged_pass': 'Unchanged PASS',
  'waived': 'Waived',
  'new_check': 'New check',
  'not_rechecked': 'Not re-checked',
};

Color comparisonColor(String k) => switch (k) {
      'resolved' || 'clarified_pass' || 'unchanged_pass' => EE.pass,
      'persistent' || 'new_discrepancy' || 'clarified_fail' => EE.fail,
      'unconfirmed' || 'still_uncertain' || 'regressed_to_uncertain' => EE.uncertain,
      _ => EE.textMuted,
    };

String subjectLabel(String s) {
  final i = s.indexOf(':');
  if (i < 0) return s;
  final check = s.substring(0, i);
  return '${checkLabels[check] ?? check} · ${s.substring(i + 1)}';
}

class SubPanel extends StatelessWidget {
  const SubPanel({super.key, required this.title, required this.child, this.caption});
  final String title;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title.toUpperCase(), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10, letterSpacing: 1.3, color: EE.textMuted)),
          if (caption != null) ...[const SizedBox(height: 3), Text(caption!, style: const TextStyle(fontSize: 11, color: EE.textDim))],
          const SizedBox(height: 10),
          child,
        ]),
      );
}

class QualityIntelligence extends StatelessWidget {
  const QualityIntelligence({super.key, required this.data});
  final Json data;

  @override
  Widget build(BuildContext context) {
    final sample = data.obj('basis').obj('sample');
    final findings = sample.integer('findings');
    if (findings == 0) {
      return const EmptyState(
        title: 'Insufficient data',
        message: 'Quality intelligence is calculated from the findings of completed inspections. Run an inspection to populate it.',
        icon: Icons.insights_rounded,
      );
    }
    final cats = data.objs('finding_categories').where((c) => c.integer('FAIL') + c.integer('UNCERTAIN') > 0).toList()
      ..sort((a, b) => (b.integer('FAIL') + b.integer('UNCERTAIN')).compareTo(a.integer('FAIL') + a.integer('UNCERTAIN')));
    final repeated = data.objs('repeated_mismatches');
    final zones = data.objs('zones_requiring_review');
    final subs = data.objs('substitution_patterns');
    final ocr = data.obj('ocr_unreadable');
    final reinsp = data.obj('reinspection_outcomes');
    final kpis = data.obj('kpis');

    final tiles = <Widget>[
      SubPanel(
        title: 'Discrepancy categories',
        caption: 'FAIL + UNCERTAIN per check (after review)',
        child: cats.isEmpty
            ? const _None('No FAIL or UNCERTAIN findings')
            : StackedVerdictBars(
                labelWidth: 120,
                rows: [
                  for (final c in cats.take(6))
                    StackRow(checkLabels[c.str('check_type')] ?? c.str('check_type'), {'FAIL': c.integer('FAIL'), 'UNCERTAIN': c.integer('UNCERTAIN')}),
                ],
              ),
      ),
      SubPanel(
        title: 'Repeated label mismatches',
        caption: 'Subjects not verified as PASS',
        child: repeated.isEmpty
            ? const _None('No label or ferrule mismatches')
            : Column(children: [
                for (final r in repeated.take(6))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(child: Text(subjectLabel(r.str('subject')), overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5))),
                      Text('×${r.integer('count')}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.uncertain, fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ]),
      ),
      SubPanel(
        title: 'Zones needing manual review',
        caption: 'UNCERTAIN findings by zone',
        child: zones.isEmpty
            ? const _None('No zone has open UNCERTAIN findings')
            : HBarList(labelWidth: 50, items: [for (final z in zones.take(6)) BarItem(z.str('zone'), z.integer('count'), color: EE.uncertain, mono: true)]),
      ),
      SubPanel(
        title: 'OCR & evidence',
        child: Wrap(alignment: WrapAlignment.spaceAround, spacing: 12, runSpacing: 12, children: [
          RatioGauge(
            value: ocr.dbl('rate'),
            label: 'Unreadable labels',
            sub: '${ocr.integer('unreadable')} of ${ocr.integer('label_findings')} label findings',
            color: EE.uncertain,
            size: 116,
          ),
          RatioGauge(
            value: kpis.dbl('evidence_completeness'),
            label: 'Evidence completeness',
            sub: 'findings with image crops',
            color: EE.pass,
            size: 116,
          ),
        ]),
      ),
      SubPanel(
        title: 'Reinspection outcomes',
        caption: 'Across all version comparisons',
        child: reinsp.isEmpty
            ? const _None('No reinspections compared yet')
            : HBarList(
                labelWidth: 132,
                items: [
                  for (final e in reinsp.entries.where((e) => e.key != 'unchanged_pass'))
                    BarItem(comparisonLabels[e.key] ?? e.key, (e.value as num).toInt(), color: comparisonColor(e.key)),
                ],
              ),
      ),
      SubPanel(
        title: 'Character substitutions',
        caption: 'expected → observed, from recorded edit operations',
        child: subs.isEmpty
            ? const _None('No substitutions recorded')
            : Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in subs.take(10)) Tag('${s.str('pattern')}  ×${s.integer('count')}', color: EE.ice, mono: true),
              ]),
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 1050 ? 3 : (c.maxWidth > 640 ? 2 : 1);
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }
}

class _None extends StatelessWidget {
  const _None(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: const TextStyle(fontSize: 12, color: EE.textDim)),
      );
}

/// Basis/sample-size strip shown above statistics.
class BasisStrip extends StatelessWidget {
  const BasisStrip({super.key, required this.data, required this.range});
  final Json data;
  final DateRangeSpec range;

  @override
  Widget build(BuildContext context) {
    final b = data.obj('basis');
    final s = b.obj('sample');
    final ds = b.str('dataset', 'all');
    Widget item(String k, String v) => Row(mainAxisSize: MainAxisSize.min, children: [
          Text(k, style: const TextStyle(fontSize: 11, color: EE.textDim)),
          const SizedBox(width: 6),
          Text(v, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.text, fontWeight: FontWeight.w600)),
        ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: EE.surface, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line)),
      child: Wrap(spacing: 18, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Icon(Icons.dataset_outlined, size: 15, color: EE.cyan),
        item('Dataset', ds == 'all' ? 'all' : (ds == 'real' ? 'real only' : 'demo only')),
        item('Range', range.describe),
        item('Inspections', '${s.integer('inspections')}'),
        item('Runs', '${s.integer('runs')}'),
        item('Completed', '${s.integer('completed_runs')}'),
        item('Findings', '${s.integer('findings')}'),
        if (b.integer('demo_inspections') > 0 && ds != 'real')
          Tooltip(
            message: 'Demonstration inspections use synthetic fixtures. Switch to "Real only" to exclude them.',
            child: Tag('${b.integer('demo_inspections')} demo inspection${b.integer('demo_inspections') == 1 ? '' : 's'} included', color: EE.violet, icon: Icons.science_outlined, filled: true),
          ),
        Text('Verdicts: ${b.str('verdict_statistics')} · Activity: ${b.str('activity_statistics')}', style: const TextStyle(fontSize: 11, color: EE.textDim)),
      ]),
    );
  }
}
