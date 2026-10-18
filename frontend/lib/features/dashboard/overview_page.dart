import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/kpi.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import 'dashboard_widgets.dart';
import 'recent_inspections_table.dart';

/// Overview dashboard: command overview, KPIs, activity timeline, verdict distribution,
/// activity feed, recent inspections, quality intelligence and system readiness.
/// Every figure is derived from persisted records via the API.
class OverviewPage extends ConsumerStatefulWidget {
  const OverviewPage({super.key});

  @override
  ConsumerState<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends ConsumerState<OverviewPage> {
  DateRangeSpec _range = const DateRangeSpec(RangeKey.d30);
  String? _day;
  int _refresh = 0;
  bool _effective = false;
  bool _sampleBusy = false;
  Json? _last;

  AnalyticsQuery get _query => (dataset: ref.read(datasetProvider), from: _range.fromIso, to: _range.toIso);

  void _refreshAll() {
    final ds = ref.read(datasetProvider);
    ref.invalidate(analyticsProvider);
    ref.invalidate(activityFeedProvider(ds));
    ref.read(systemStatusProvider.notifier).refresh();
    setState(() => _refresh++);
  }

  Future<void> _sample() async {
    setState(() => _sampleBusy = true);
    await runSampleInspection(context, ref);
    if (mounted) setState(() => _sampleBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    // a job finishing changes every figure on this page
    ref.listen<List<Job>>(activeJobsProvider, (prev, next) {
      if (prev != null && next.length < prev.length) _refreshAll();
    });
    final ds = ref.watch(datasetProvider);
    final q = (dataset: ds, from: _range.fromIso, to: _range.toIso);
    final live = ref.watch(analyticsProvider(q));
    if (live.hasValue) _last = live.requireValue;
    // keep the previous figures on screen while a new range/dataset loads
    final analytics = (!live.hasValue && !live.hasError && _last != null) ? AsyncValue<Json>.data(_last!) : live;
    final stale = !live.hasValue && !live.hasError && _last != null;
    final width = MediaQuery.sizeOf(context).width;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CommandHeader(
          analytics: analytics.value,
          sampleBusy: _sampleBusy,
          onSample: _sample,
          onRefresh: _refreshAll,
        ),
        SizedBox(height: EE.s4, child: stale ? const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator(minHeight: 1.5)) : null),
        AsyncView<Json>(
          analytics,
          onRetry: () => ref.invalidate(analyticsProvider(_query)),
          loadingLabel: 'Computing operational metrics',
          data: (a) {
            final k = a.obj('kpis');
            final empty = k.integer('total_inspections') == 0;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (empty) ...[_Onboarding(dataset: ds, busy: _sampleBusy, onSample: _sample), const SizedBox(height: EE.s4)],
              _Kpis(k: k, sample: a.obj('basis').obj('sample'), range: _range),
              const SizedBox(height: EE.s4),
              ResponsiveRow(
                breakpoint: 1080,
                flex: const [3, 2],
                children: [
                  _VolumePanel(
                    data: a,
                    range: _range,
                    selectedDay: _day,
                    onRange: (r) => setState(() {
                      _range = r;
                      _day = null;
                    }),
                    onDay: (d) => setState(() => _day = _day == d ? null : d),
                  ),
                  _VerdictPanel(data: a, effective: _effective, onMode: (v) => setState(() => _effective = v)),
                ],
              ),
            ]);
          },
        ),
        const SizedBox(height: EE.s4),
        RecentInspectionsTable(day: _day, onClearDay: () => setState(() => _day = null), refreshToken: _refresh),
        const SizedBox(height: EE.s4),
        ResponsiveRow(
          breakpoint: 1180,
          flex: const [2, 3],
          children: [
            const ActivityFeed(),
            Panel(
              eyebrow: 'G · Quality intelligence',
              title: 'Where inspections need attention',
              subtitle: 'Calculated from the latest completed version of each inspection in scope (${_range.describe}).',
              child: analytics.hasValue
                  ? QualityIntelligence(data: analytics.requireValue)
                  : analytics.hasError
                      ? ErrorView(analytics.error!, compact: true, onRetry: () => ref.invalidate(analyticsProvider(_query)))
                      : const LoadingView(),
            ),
          ],
        ),
        const SizedBox(height: EE.s4),
        ReadinessGrid(compact: width < 700),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// A · Command overview
// ---------------------------------------------------------------------------

class _CommandHeader extends ConsumerWidget {
  const _CommandHeader({required this.analytics, required this.sampleBusy, required this.onSample, required this.onRefresh});
  final Json? analytics;
  final bool sampleBusy;
  final VoidCallback onSample;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(systemStatusProvider);
    final s = status.value;
    final now = DateTime.now();
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final last = analytics?.obj('kpis').time('last_successful_inspection_at');

    String summary;
    Color summaryColor;
    if (status.hasError && s == null) {
      summary = 'Backend not reachable — figures below cannot be refreshed.';
      summaryColor = EE.fail;
    } else if (s == null) {
      summary = 'Checking subsystems…';
      summaryColor = EE.textMuted;
    } else {
      final ok = s.components.where((c) => c.state == 'ok').length;
      final issues = s.components.where((c) => c.state != 'ok').map((c) => '${c.label} ${(stateMeaning[c.state] ?? c.state).toLowerCase()}').toList();
      summary = '$ok of ${s.components.length} subsystems operational${issues.isEmpty ? '.' : ' · ${issues.join(' · ')}'}';
      summaryColor = issues.isEmpty ? EE.pass : (s.components.any((c) => c.state == 'error' || c.state == 'unavailable') ? EE.fail : EE.uncertain);
    }

    final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Eyebrow('A · Command overview · Local QA lab'),
      const SizedBox(height: 10),
      Text('Quality command', style: Theme.of(context).textTheme.displaySmall),
      const SizedBox(height: 6),
      Text(DateFormat('EEEE d MMMM yyyy · HH:mm').format(now), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.textMuted)),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: StatusDot(color: summaryColor, size: 7, pulse: s?.warmup == 'loading')),
        const SizedBox(width: 6),
        Expanded(child: Text(summary, style: TextStyle(fontSize: 13, color: summaryColor == EE.pass ? EE.text : summaryColor, height: 1.4))),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (s != null)
          for (final c in s.components)
            Tooltip(
              message: '${c.label}: ${stateMeaning[c.state] ?? c.state}\n${c.message}',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: EE.bg1.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: EE.line)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  StatusDot(color: EE.state(c.state), size: 5, pulse: c.state == 'loading'),
                  Text(c.label, style: const TextStyle(fontSize: 11, color: EE.textMuted)),
                ]),
              ),
            ),
      ]),
    ]);

    final right = Column(crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
      Wrap(spacing: 8, runSpacing: 8, alignment: narrow ? WrapAlignment.start : WrapAlignment.end, children: [
        OutlinedButton.icon(
          onPressed: sampleBusy ? null : onSample,
          icon: sampleBusy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.science_outlined, size: 17),
          label: const Text('Run sample inspection'),
        ),
        FilledButton.icon(onPressed: () => context.go('/console/new'), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New inspection')),
      ]),
      const SizedBox(height: 16),
      _Stat(label: 'Last successful inspection', value: last == null ? 'none yet' : fmtTime(last), sub: last == null ? null : ago(last)),
      const SizedBox(height: 10),
      _Stat(
        label: 'Model warm-up',
        value: s == null ? '—' : switch (s.warmup) { 'done' => 'complete', 'loading' => 'loading models…', 'idle' => 'on first use', _ => s.warmup },
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: narrow ? WrapAlignment.start : WrapAlignment.end, children: [
        const DatasetToggle(),
        IconButton(tooltip: 'Refresh all', icon: const Icon(Icons.refresh_rounded, size: 18), onPressed: onRefresh),
      ]),
    ]);

    return Container(
      padding: EdgeInsets.all(narrow ? 18 : 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EE.r3),
        border: Border.all(color: EE.cyan.withValues(alpha: 0.22)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1A2E), Color(0xFF0A1220), Color(0xFF120F2A)],
          stops: [0, 0.6, 1],
        ),
        boxShadow: [BoxShadow(color: EE.cyan.withValues(alpha: 0.06), blurRadius: 40, spreadRadius: -6)],
      ),
      child: Stack(children: [
        const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _HeaderLines()))),
        narrow
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [left, const SizedBox(height: 20), right])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: left), const SizedBox(width: 24), Expanded(flex: 2, child: right)]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.sub});
  final String label;
  final String value;
  final String? sub;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(label.toUpperCase(), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 9.5, letterSpacing: 1.3, color: EE.textDim)),
        const SizedBox(height: 3),
        Text(value + (sub == null ? '' : '  ·  $sub'), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5, color: EE.text)),
      ]);
}

/// Faint drafting lines and a measurement tick rail behind the command header.
class _HeaderLines extends CustomPainter {
  const _HeaderLines();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = EE.cyan.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = size.width * 0.55; x < size.width; x += 18) {
      canvas.drawLine(Offset(x, 0), Offset(x - size.height * 0.6, size.height), p);
    }
    final t = Paint()
      ..color = EE.cyan.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, size.height - 1), Offset(x, size.height - ((x ~/ 12) % 5 == 0 ? 7 : 3)), t);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Onboarding (empty database / empty scope)
// ---------------------------------------------------------------------------

class _Onboarding extends StatelessWidget {
  const _Onboarding({required this.dataset, required this.busy, required this.onSample});
  final String dataset;
  final bool busy;
  final VoidCallback onSample;

  @override
  Widget build(BuildContext context) {
    Widget step(String n, String title, String text) => SizedBox(
          width: 250,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 20, color: EE.cyan, fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 3),
                Text(text, style: const TextStyle(fontSize: 12, color: EE.textMuted, height: 1.4)),
              ]),
            ),
          ]),
        );
    return Panel(
      accent: EE.cyan,
      eyebrow: 'Getting started',
      title: dataset == 'real' ? 'No real inspections in this range yet' : 'No inspections recorded yet',
      subtitle: 'All metrics on this page are computed from persisted inspections, so they read zero until the first run completes.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 24, runSpacing: 16, children: [
          step('01', 'Create a case', 'Cabinet identifier, site and reference.'),
          step('02', 'Upload inputs', 'Cabinet photo, GA drawing (PDF) and the expected wire/label list (XLSX/CSV).'),
          step('03', 'Run & review', 'Watch the live stages, then review evidence and UNCERTAIN findings.'),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: busy ? null : onSample,
            icon: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: EE.bg0)) : const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Run sample inspection'),
          ),
          OutlinedButton.icon(onPressed: () => context.go('/console/new'), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New inspection')),
          const SizedBox(width: 6),
          const Text(
            'The sample uses bundled SYNTHETIC fixtures processed by the live pipeline and is labelled DEMO everywhere.',
            style: TextStyle(fontSize: 11.5, color: EE.textDim),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// B · KPIs
// ---------------------------------------------------------------------------

class _Kpis extends StatelessWidget {
  const _Kpis({required this.k, required this.sample, required this.range});
  final Json k;
  final Json sample;
  final DateRangeSpec range;

  @override
  Widget build(BuildContext context) {
    final avg = k.intN('avg_processing_ms');
    final med = k.intN('median_processing_ms');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Row(children: [
          const Eyebrow('B · Operational KPIs'),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${range.describe} (set on the activity timeline) · ${sample.integer('runs')} runs · verdict figures use the latest completed version per inspection, after human review',
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: EE.textDim)),
          ),
        ]),
      ),
      KpiGrid(minTileWidth: 210, children: [
        Kpi(
          label: 'Total inspections',
          value: '${k.integer('total_inspections')}',
          sub: '${sample.integer('completed_runs')} completed runs in range',
          icon: Icons.inventory_2_outlined,
          onTap: () => context.go('/console/history'),
        ),
        Kpi(
          label: 'Completed runs',
          value: '${k.integer('completed_runs')}',
          sub: '${k.integer('failed_runs')} failed run${k.integer('failed_runs') == 1 ? '' : 's'}',
          accent: EE.ice,
          icon: Icons.task_alt_rounded,
        ),
        Kpi(
          label: 'Requiring review',
          value: '${k.integer('inspections_requiring_review')}',
          sub: '${k.integer('review_queue_size')} findings in the review queue',
          accent: EE.uncertain,
          icon: Icons.fact_check_outlined,
          onTap: () => context.go('/console/review'),
        ),
        Kpi(
          label: 'Confirmed discrepancies',
          value: '${k.integer('confirmed_discrepancies')}',
          sub: 'FAIL after review · ${k.integer('uncertain_items')} UNCERTAIN open',
          accent: EE.fail,
          icon: Icons.report_gmailerrorred_rounded,
          onTap: () => context.go('/console/review'),
        ),
        Kpi(
          label: 'Verified items',
          value: '${k.integer('verified_items')}',
          sub: 'PASS after review${k.integer('waived_items') > 0 ? ' · ${k.integer('waived_items')} waived' : ''}',
          accent: EE.pass,
          icon: Icons.verified_outlined,
        ),
        Kpi(
          label: 'Avg processing time',
          value: avg == null ? '—' : fmtMs(avg),
          sub: med == null ? 'measured on completed runs' : 'median ${fmtMs(med)} · measured',
          accent: EE.violet,
          icon: Icons.timer_outlined,
          onTap: () => context.go('/console/analytics'),
        ),
        Kpi(
          label: 'Reinspection rate',
          value: pct(k.dbl('reinspection_rate')),
          sub: 'inspections with more than one version',
          accent: EE.ultraviolet,
          icon: Icons.replay_rounded,
          onTap: () => context.go('/console/history'),
        ),
        Kpi(
          label: 'Evidence completeness',
          value: pct(k.dbl('evidence_completeness')),
          sub: 'findings carrying an image crop',
          accent: EE.cyan,
          icon: Icons.photo_library_outlined,
          onTap: () => context.go('/console/evidence'),
        ),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------------------
// C · Volume time series
// ---------------------------------------------------------------------------

class _VolumePanel extends StatelessWidget {
  const _VolumePanel({required this.data, required this.range, required this.selectedDay, required this.onRange, required this.onDay});
  final Json data;
  final DateRangeSpec range;
  final String? selectedDay;
  final ValueChanged<DateRangeSpec> onRange;
  final ValueChanged<String> onDay;

  @override
  Widget build(BuildContext context) {
    final vol = data.objs('volume_by_day');
    final (from, to) = range.window(vol);
    final points = fillDays(vol, from, to);
    final total = points.fold<int>(0, (a, p) => a + p.runs);
    return Panel(
      eyebrow: 'C · Activity timeline',
      title: 'Inspection volume',
      subtitle: 'Runs per day by outcome. Tap a day to filter the inspection table.',
      actions: [RangeSelector(value: range, onChanged: onRange)],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 16, runSpacing: 6, children: [
          LegendDot(color: EE.cyan, label: 'Completed', value: '${points.fold<int>(0, (a, p) => a + p.completed)}', square: true),
          LegendDot(color: EE.fail, label: 'Failed', value: '${points.fold<int>(0, (a, p) => a + p.failed)}', square: true),
          LegendDot(color: EE.textDim, label: 'Other (draft / running / cancelled)', value: '${points.fold<int>(0, (a, p) => a + p.other)}', square: true),
        ]),
        const SizedBox(height: 14),
        Stack(children: [
          VolumeChart(points: points, selectedKey: selectedDay, onSelectDay: (p) => onDay(p.key)),
          if (total == 0)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: Text('No runs in this range', style: TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textDim))),
              ),
            ),
        ]),
        if (selectedDay != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.filter_alt_outlined, size: 14, color: EE.cyan),
              const SizedBox(width: 6),
              Text('Filtering inspections created on $selectedDay', style: const TextStyle(fontSize: 11.5, color: EE.cyan)),
              const SizedBox(width: 4),
              TextButton(onPressed: () => onDay(selectedDay!), child: const Text('Clear')),
            ]),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// D · Verdict distribution
// ---------------------------------------------------------------------------

class _VerdictPanel extends StatelessWidget {
  const _VerdictPanel({required this.data, required this.effective, required this.onMode});
  final Json data;
  final bool effective;
  final ValueChanged<bool> onMode;

  Map<String, int> _counts(Json m) => m.map((k, v) => MapEntry(k, (v as num).toInt()));

  @override
  Widget build(BuildContext context) {
    final counts = _counts(effective ? data.obj('effective_verdicts') : data.obj('machine_verdicts'));
    final queue = data.obj('kpis').integer('review_queue_size');
    return Panel(
      eyebrow: 'D · Verdict distribution',
      title: effective ? 'After human review' : 'Machine verdicts',
      actions: [
        Segmented<bool>(options: const {false: 'Machine', true: 'After review'}, value: effective, onChanged: onMode),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 6),
        Wrap(alignment: WrapAlignment.spaceEvenly, crossAxisAlignment: WrapCrossAlignment.center, spacing: 20, runSpacing: 16, children: [
          VerdictDonut(counts: counts, size: 176, onTap: (v) => context.go('/console/review')),
          VerdictLegend(counts: counts, includeWaived: effective),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: EE.uncertain.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(EE.r2),
            border: Border.all(color: EE.uncertain.withValues(alpha: 0.3)),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.help_outline_rounded, size: 15, color: EE.uncertain),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'UNCERTAIN findings need human review. They are counted neither as passes nor as confirmed failures until an inspector resolves them.',
                style: TextStyle(fontSize: 11.5, color: EE.textMuted, height: 1.4),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('$queue finding${queue == 1 ? '' : 's'} awaiting review', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted)),
          const Spacer(),
          TextButton.icon(onPressed: () => context.go('/console/review'), icon: const Icon(Icons.arrow_forward_rounded, size: 15), label: const Text('Review queue')),
        ]),
      ]),
    );
  }
}
