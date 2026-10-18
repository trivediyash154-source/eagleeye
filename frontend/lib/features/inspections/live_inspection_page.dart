import 'dart:async';

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

/// Real-time view of a processing job. Every stage state shown here is the persisted backend
/// state, polled every 1.5 s; progress is the share of stages the backend reports as finished.
class LiveInspectionPage extends ConsumerWidget {
  const LiveInspectionPage({super.key, this.jobId});
  final String? jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (jobId == null || jobId!.isEmpty) return const _JobList();
    return _JobMonitor(key: ValueKey(jobId), jobId: jobId!);
  }
}

class _JobList extends ConsumerStatefulWidget {
  const _JobList();
  @override
  ConsumerState<_JobList> createState() => _JobListState();
}

class _JobListState extends ConsumerState<_JobList> {
  late Future<List<Job>> _jobs = ref.read(apiProvider).jobs(limit: 30);

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      PageHeader(
        eyebrow: 'Operate',
        title: 'Live Inspection',
        description: 'Follow processing jobs stage by stage. Select a running or recent job to open its live view.',
        actions: [
          OutlinedButton.icon(onPressed: () => setState(() => _jobs = ref.read(apiProvider).jobs(limit: 30)), icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Refresh')),
          FilledButton.icon(onPressed: () => context.go('/console/new'), icon: const Icon(Icons.add_rounded, size: 16), label: const Text('New inspection')),
        ],
      ),
      FutureBuilder<List<Job>>(
        future: _jobs,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(snap.error!, onRetry: () => setState(() => _jobs = ref.read(apiProvider).jobs(limit: 30)));
          if (!snap.hasData) return const LoadingView(label: 'Loading jobs');
          final jobs = snap.data!;
          if (jobs.isEmpty) {
            return EmptyState(
              title: 'No processing jobs yet',
              message: 'Run an inspection from New Inspection, or start the bundled sample inspection from the Overview.',
              icon: Icons.sensors_off_rounded,
              action: FilledButton(onPressed: () => context.go('/console'), child: const Text('Go to Overview')),
            );
          }
          return Panel(
            eyebrow: 'Processing jobs',
            title: '${jobs.length} most recent',
            child: Column(children: [
              for (final j in jobs)
                InkWell(
                  onTap: () => context.go('/console/live?job=${j.id}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(children: [
                      SizedBox(width: 92, child: Text(j.inspectionCode ?? '—', style: const TextStyle(fontFamily: EE.fontMono, color: EE.cyan, fontSize: 12.5))),
                      SizedBox(width: 60, child: Text('v${j.versionNo ?? '?'}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12))),
                      Expanded(child: Text(j.cabinetId ?? '', style: const TextStyle(fontSize: 13))),
                      SizedBox(width: 130, child: StatePill(j.status)),
                      SizedBox(width: 150, child: Text(j.currentStage != null ? titleCase(j.currentStage!) : (j.error != null ? 'error' : ''), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: EE.textMuted))),
                      SizedBox(width: 90, child: Text(ago(j.createdAt), style: const TextStyle(fontSize: 12, color: EE.textDim))),
                      const Icon(Icons.chevron_right_rounded, color: EE.textDim),
                    ]),
                  ),
                ),
            ]),
          );
        },
      ),
    ]);
  }
}

class _JobMonitor extends ConsumerStatefulWidget {
  const _JobMonitor({super.key, required this.jobId});
  final String jobId;
  @override
  ConsumerState<_JobMonitor> createState() => _JobMonitorState();
}

class _JobMonitorState extends ConsumerState<_JobMonitor> {
  Job? _job;
  Object? _error;
  Timer? _timer;
  Timer? _clock;
  int _failures = 0;
  bool _busy = false;
  int? _redirectIn;
  Inspection? _insp;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_redirectIn != null) {
        if (_redirectIn! <= 1) {
          _openWorkspace();
        } else {
          setState(() => _redirectIn = _redirectIn! - 1);
        }
      } else if (_job != null && !_job!.isTerminal) {
        setState(() {}); // elapsed-time ticker
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final j = await ref.read(apiProvider).job(widget.jobId);
      if (!mounted) return;
      // only a transition observed on this screen triggers the refresh + auto-open countdown
      final becameTerminal = j.isTerminal && _job != null && !_job!.isTerminal;
      setState(() {
        _job = j;
        _error = null;
        _failures = 0;
      });
      if (_insp == null) {
        ref.read(apiProvider).inspection(j.inspectionId).then((i) {
          if (mounted) setState(() => _insp = i);
        }).catchError((_) {});
      }
      if (j.isTerminal) {
        _timer?.cancel();
        if (becameTerminal) {
          refreshInspectionData(ref, inspectionId: j.inspectionId, versionId: j.versionId);
          ref.read(activeJobsProvider.notifier).refresh();
          if (j.status == 'completed' && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) setState(() => _redirectIn = 6);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failures++;
        _error = e;
      });
      if (_failures >= 20) _timer?.cancel(); // stop after ~30 s of failures; user can retry
    }
  }

  void _openWorkspace() {
    _clock?.cancel();
    final j = _job;
    if (j == null) return;
    final v = _insp?.versions.where((x) => x.id == j.versionId).firstOrNull;
    context.go(workspaceLink(j.inspectionId, version: v?.no));
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      final j = await ref.read(apiProvider).cancelJob(widget.jobId);
      if (mounted) setState(() => _job = j);
      if (mounted) showSnack(context, 'Cancellation requested — it takes effect between stages.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    final j = _job;
    if (j == null) return;
    setState(() => _busy = true);
    try {
      final nj = await ref.read(apiProvider).run(j.versionId);
      if (mounted) context.go('/console/live?job=${nj.id}');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = _job;
    if (j == null) {
      return _error != null ? ErrorView(_error!, onRetry: _poll) : const LoadingView(label: 'Connecting to job');
    }
    final stages = j.stages;
    final done = stages.where((s) => const {'completed', 'skipped', 'failed', 'needs_review'}.contains(s.status)).length;
    final progress = stages.isEmpty ? 0.0 : done / stages.length;
    final start = j.startedAt ?? j.createdAt;
    final end = j.finishedAt ?? DateTime.now();
    final elapsed = start == null ? null : end.difference(start).inMilliseconds;
    final v = _insp?.versions.where((x) => x.id == j.versionId).firstOrNull;
    final wide = MediaQuery.sizeOf(context).width >= 1180;

    final header = PageHeader(
      eyebrow: 'Live inspection · job ${j.id.substring(0, 12)}…',
      title: _insp == null ? 'Processing' : '${_insp!.code} · ${_insp!.title}',
      description: 'Stage states are read from the backend job record. Nothing on this screen is simulated: a stage is shown as complete only after the server recorded its outcome.',
      actions: [
        if (_insp?.isDemo == true) const DemoTag(),
        if (!j.isTerminal) OutlinedButton.icon(onPressed: _busy || j.cancelRequested ? null : _cancel, icon: const Icon(Icons.stop_circle_outlined, size: 16), label: Text(j.cancelRequested ? 'Cancelling…' : 'Cancel')),
        if (j.status == 'failed' || j.status == 'cancelled') OutlinedButton.icon(onPressed: _busy ? null : _retry, icon: const Icon(Icons.replay_rounded, size: 16), label: const Text('Run again')),
        if (j.status == 'completed') FilledButton.icon(onPressed: _openWorkspace, icon: const Icon(Icons.view_quilt_outlined, size: 16), label: const Text('Open Inspection Workspace')),
      ],
    );

    final summary = Panel(
      eyebrow: 'Job status',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          StatePill(j.status, pulse: !j.isTerminal),
          const Spacer(),
          Text(fmtMs(elapsed), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 22, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(value: progress, minHeight: 4, color: j.status == 'failed' ? EE.fail : (j.status == 'completed' ? EE.pass : EE.cyan)),
        ),
        const SizedBox(height: 6),
        Text('$done of ${stages.length} stages finished${j.currentStage != null && !j.isTerminal ? ' · running: ${titleCase(j.currentStage!)}' : ''}',
            style: const TextStyle(fontSize: 12, color: EE.textMuted)),
        if (_error != null) ...[const SizedBox(height: 8), ErrorView(_error!, compact: true, onRetry: _poll)],
        if (j.error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: EE.fail.withValues(alpha: 0.08), border: Border.all(color: EE.fail.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(EE.r1)),
            child: SelectableText(j.error!, style: const TextStyle(color: EE.fail, fontSize: 12.5)),
          ),
          if (v != null && v.editable)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Version ${v.no} is still editable: fix the inputs in New Inspection or run again.', style: const TextStyle(fontSize: 12, color: EE.textMuted)),
            ),
        ],
        if (j.status == 'completed' && v != null) ...[
          const Hairline(),
          Row(children: [
            _Count('PASS', v.summary.pass),
            _Count('FAIL', v.summary.fail),
            _Count('UNCERTAIN', v.summary.uncertain),
          ]),
          if (_redirectIn != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text('Opening the workspace in $_redirectIn s…', style: const TextStyle(fontSize: 12.5, color: EE.textMuted))),
              TextButton(onPressed: () => setState(() => _redirectIn = null), child: const Text('Stay here')),
            ]),
          ],
        ],
        const Hairline(),
        KV('Inspection', _insp == null ? '…' : '${_insp!.code} · cabinet ${_insp!.cabinetId}'),
        KV('Version', v == null ? '…' : 'v${v.no} · ${v.label}'),
        KV('Queued', fmtTime(j.createdAt)),
        KV('Started', fmtTime(j.startedAt)),
        KV('Finished', fmtTime(j.finishedAt)),
      ]),
    );

    final pipeline = Panel(
      eyebrow: 'Pipeline stages',
      title: 'Backend-reported state',
      child: Column(children: [for (var i = 0; i < stages.length; i++) _StageRow(stage: stages[i], index: i, last: i == stages.length - 1)]),
    );

    return ListView(children: [
      header,
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 380, child: summary),
          const SizedBox(width: EE.s4),
          Expanded(child: pipeline),
        ])
      else ...[summary, const SizedBox(height: EE.s4), pipeline],
      const SizedBox(height: 40),
    ]);
  }
}

class _Count extends StatelessWidget {
  const _Count(this.verdict, this.n);
  final String verdict;
  final int n;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$n', style: TextStyle(fontFamily: EE.fontDisplay, fontSize: 28, fontWeight: FontWeight.w600, color: EE.verdict(verdict))),
          Text(verdict, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, letterSpacing: 1.2, color: EE.textMuted)),
        ]),
      );
}

class _StageRow extends StatefulWidget {
  const _StageRow({required this.stage, required this.index, required this.last});
  final Stage stage;
  final int index;
  final bool last;
  @override
  State<_StageRow> createState() => _StageRowState();
}

class _StageRowState extends State<_StageRow> {
  bool _open = false;

  IconData _icon(String s) => switch (s) {
        'completed' => Icons.check_circle_rounded,
        'running' => Icons.autorenew_rounded,
        'failed' => Icons.error_rounded,
        'skipped' => Icons.remove_circle_outline_rounded,
        'needs_review' => Icons.flag_circle_rounded,
        _ => Icons.radio_button_unchecked_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final s = widget.stage;
    final c = EE.state(s.status);
    final details = s.details;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 34,
          child: Column(children: [
            const SizedBox(height: 12),
            s.status == 'running'
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c))
                : Icon(_icon(s.status), size: 20, color: c),
            if (!widget.last) Expanded(child: Container(width: 1.5, margin: const EdgeInsets.only(top: 6), color: s.status == 'pending' ? EE.line : c.withValues(alpha: 0.5))),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('${(widget.index + 1).toString().padLeft(2, '0')}  ', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.textDim)),
                Expanded(child: Text(s.title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: s.status == 'pending' ? EE.textMuted : EE.text))),
                StatePill(s.status),
                const SizedBox(width: 12),
                SizedBox(width: 64, child: Text(fmtMs(s.durationMs), textAlign: TextAlign.right, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.textMuted))),
                if (details.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _open ? 'Hide details' : 'Show stage details',
                    onPressed: () => setState(() => _open = !_open),
                    icon: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                  ),
              ]),
              if (s.message != null) Padding(padding: const EdgeInsets.only(top: 4, left: 28), child: Text(s.message!, style: TextStyle(fontSize: 12.5, color: s.status == 'failed' ? EE.fail : EE.textMuted))),
              AnimatedSize(
                duration: EE.med,
                child: !_open
                    ? const SizedBox(width: double.infinity)
                    : Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8, left: 28),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: EE.line)),
                        child: SelectableText(_pretty(details), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textMuted, height: 1.45)),
                      ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  String _pretty(Object? v, [String indent = '']) {
    if (v is Map) {
      return v.entries.map((e) {
        final val = e.value;
        if (val is Map || (val is List && val.isNotEmpty && val.first is Map)) return '$indent${e.key}:\n${_pretty(val, '$indent  ')}';
        return '$indent${e.key}: ${val is List ? val.join(', ') : val}';
      }).join('\n');
    }
    if (v is List) return v.take(12).map((x) => _pretty(x, indent)).join('\n$indent---\n');
    return '$indent$v';
  }
}
