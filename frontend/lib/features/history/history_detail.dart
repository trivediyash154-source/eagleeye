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
import 'reinspect_dialog.dart';
import 'version_compare.dart';

final timelineProvider = FutureProvider.family<List<Json>, String>((ref, id) => ref.watch(apiProvider).timeline(id));

class HistoryDetail extends ConsumerWidget {
  const HistoryDetail({super.key, required this.inspectionId});
  final String inspectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insp = ref.watch(inspectionProvider(inspectionId));
    return AsyncView<Inspection>(
      insp,
      onRetry: () => ref.invalidate(inspectionProvider(inspectionId)),
      data: (i) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Header(inspection: i),
        const SizedBox(height: EE.s4),
        _Versions(inspection: i),
        const SizedBox(height: EE.s4),
        VersionComparePanel(key: ValueKey('cmp-${i.id}-${i.versionCount}'), inspection: i),
        const SizedBox(height: EE.s4),
        _AuditTimeline(inspectionId: i.id),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.inspection});
  final Inspection inspection;

  @override
  Widget build(BuildContext context) {
    final i = inspection;
    final latest = i.latest ?? (i.versions.isEmpty ? null : i.versions.last);
    final hasCompleted = i.versions.any((v) => v.status == 'completed');
    final active = i.versions.any((v) => v.isActive);
    return Panel(
      eyebrow: 'Inspection ${i.code}',
      title: i.title,
      actions: [if (i.isDemo) const DemoTag()],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final kvs = [
            KV('Cabinet', i.cabinetId, mono: true, keyWidth: 110),
            KV('Site / facility', i.site, keyWidth: 110),
            KV('Reference', i.reference, keyWidth: 110),
            KV('Inspector', i.inspector, keyWidth: 110),
            KV('Project / customer', i.projectRef, keyWidth: 110),
            KV('Created', fmtTime(i.createdAt), keyWidth: 110),
          ];
          if (c.maxWidth < 700) return Column(children: kvs);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(children: kvs.sublist(0, 3))),
            const SizedBox(width: 24),
            Expanded(child: Column(children: kvs.sublist(3))),
          ]);
        }),
        if ((i.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(i.notes!, style: const TextStyle(fontSize: 12.5, color: EE.textMuted, height: 1.5)),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (latest != null)
            OutlinedButton.icon(
              onPressed: () => context.go(workspaceLink(i.id, version: latest.no)),
              icon: const Icon(Icons.view_quilt_outlined, size: 16),
              label: Text('Open v${latest.no} in workspace'),
            ),
          FilledButton.icon(
            onPressed: hasCompleted && !active ? () => showReinspectDialog(context, i) : null,
            icon: const Icon(Icons.replay_rounded, size: 16),
            label: const Text('Reinspect'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go('/console/reports?i=${i.id}'),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Reports'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go('/console/evidence?i=${i.id}'),
            icon: const Icon(Icons.photo_library_outlined, size: 16),
            label: const Text('Evidence'),
          ),
        ]),
        if (!hasCompleted || active)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              active ? 'A run is in progress; reinspection becomes available when it finishes.' : 'Reinspection requires a completed earlier version.',
              style: const TextStyle(fontSize: 11.5, color: EE.textDim),
            ),
          ),
      ]),
    );
  }
}

class _Versions extends StatelessWidget {
  const _Versions({required this.inspection});
  final Inspection inspection;

  @override
  Widget build(BuildContext context) {
    final versions = inspection.versions.reversed.toList();
    return Panel(
      eyebrow: 'Immutable versions',
      title: 'Version timeline',
      subtitle: '${versions.length} version${versions.length == 1 ? '' : 's'} · newest first',
      child: Column(children: [
        for (var k = 0; k < versions.length; k++)
          _VersionCard(inspection: inspection, version: versions[k], isLatest: k == 0, isLast: k == versions.length - 1),
      ]),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.inspection, required this.version, required this.isLatest, required this.isLast});
  final Inspection inspection;
  final Version version;
  final bool isLatest;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final v = version;
    final s = v.summary;
    final eff = v.effective;
    final parent = v.parentVersionId == null ? null : inspection.versions.where((x) => x.id == v.parentVersionId).firstOrNull;
    final color = EE.state(v.status);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 46,
          child: Column(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                border: Border.all(color: color.withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(EE.r2),
              ),
              child: Text('v${v.no}', style: TextStyle(fontFamily: EE.fontMono, fontWeight: FontWeight.w700, fontSize: 13, color: color)),
            ),
            if (!isLast) Expanded(child: Container(width: 1.5, margin: const EdgeInsets.symmetric(vertical: 4), color: EE.lineHi)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: isLast ? 0 : 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: isLatest ? EE.lineHi : EE.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(v.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                StatePill(v.status),
                if (isLatest) const Tag('LATEST', color: EE.cyan, mono: true),
                if (parent != null) Tag('from v${parent.no}', color: EE.textMuted, icon: Icons.subdirectory_arrow_right_rounded, mono: true),
              ]),
              const SizedBox(height: 6),
              Text(
                'Created ${fmtTime(v.createdAt)}'
                '${v.completedAt != null ? '  ·  completed ${fmtTime(v.completedAt)}' : ''}'
                '${v.durationMs != null ? '  ·  ${fmtMs(v.durationMs)}' : ''}',
                style: const TextStyle(fontSize: 11.5, color: EE.textDim),
              ),
              if (v.status == 'completed') ...[
                const SizedBox(height: 10),
                Wrap(spacing: 18, runSpacing: 8, children: [
                  _counts('Machine', {'PASS': s.pass, 'FAIL': s.fail, 'UNCERTAIN': s.uncertain}),
                  _counts('After review', {for (final k in const ['PASS', 'FAIL', 'UNCERTAIN', 'WAIVED']) k: eff[k] ?? 0}),
                  Text('${v.reviewedCount}/${v.findingCount} findings reviewed', style: const TextStyle(fontSize: 11.5, color: EE.textMuted)),
                  if (s.registration != null) Text('registration: ${s.registration}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textMuted)),
                ]),
              ],
              if (v.error != null) ...[
                const SizedBox(height: 8),
                Text(v.error!, style: const TextStyle(fontSize: 12, color: EE.fail)),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in v.assets)
                  Tag(
                    '${a.kind.replaceAll('_', ' ')}: ${a.filename}${a.inherited ? '  (inherited)' : ''}',
                    color: a.inherited ? EE.textDim : EE.ice,
                    icon: a.kind == 'photo' ? Icons.photo_camera_outlined : (a.kind == 'drawing' ? Icons.architecture_rounded : Icons.table_chart_outlined),
                  ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (v.status == 'completed' || v.findingCount > 0)
                  TextButton.icon(
                    onPressed: () => context.go(workspaceLink(inspection.id, version: v.no)),
                    icon: const Icon(Icons.view_quilt_outlined, size: 15),
                    label: const Text('Workspace'),
                  ),
                if (v.latestJobId != null)
                  TextButton.icon(
                    onPressed: () => context.go('/console/live?job=${v.latestJobId}'),
                    icon: Icon(v.isActive ? Icons.sensors_rounded : Icons.timeline_rounded, size: 15),
                    label: Text(v.isActive ? 'Live progress' : 'Processing stages'),
                  ),
                if (v.status == 'completed')
                  TextButton.icon(
                    onPressed: () => context.go('/console/reports?i=${inspection.id}'),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
                    label: const Text('Report'),
                  ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _counts(String label, Map<String, int> m) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label  ', style: const TextStyle(fontSize: 11, color: EE.textDim)),
        for (final e in m.entries)
          if (e.key != 'WAIVED' || e.value > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: e.key,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: EE.verdict(e.key), shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('${e.value}', style: TextStyle(fontFamily: EE.fontMono, fontSize: 12, fontWeight: FontWeight.w600, color: EE.verdict(e.key))),
                ]),
              ),
            ),
      ]);
}

class _AuditTimeline extends ConsumerStatefulWidget {
  const _AuditTimeline({required this.inspectionId});
  final String inspectionId;
  @override
  ConsumerState<_AuditTimeline> createState() => _AuditTimelineState();
}

class _AuditTimelineState extends ConsumerState<_AuditTimeline> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(timelineProvider(widget.inspectionId));
    return Panel(
      eyebrow: 'Audit trail',
      title: 'Event timeline',
      subtitle: 'Recorded events with actor and context. Actor “local-demo-reviewer” is the prototype identity (no authentication).',
      actions: [
        IconButton(tooltip: 'Refresh', onPressed: () => ref.invalidate(timelineProvider(widget.inspectionId)), icon: const Icon(Icons.refresh_rounded, size: 18)),
      ],
      child: AsyncView<List<Json>>(
        data,
        onRetry: () => ref.invalidate(timelineProvider(widget.inspectionId)),
        data: (events) {
          if (events.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('No events recorded.', style: TextStyle(color: EE.textMuted)));
          final shown = _all || events.length <= 14 ? events.reversed.toList() : events.reversed.take(14).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var k = 0; k < shown.length; k++) _Event(event: shown[k], last: k == shown.length - 1),
            if (events.length > 14)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: () => setState(() => _all = !_all), child: Text(_all ? 'Show recent only' : 'Show all ${events.length} events')),
              ),
          ]);
        },
      ),
    );
  }
}

class _Event extends StatelessWidget {
  const _Event({required this.event, required this.last});
  final Json event;
  final bool last;

  static Color _color(String t) {
    if (t.contains('failed') || t.contains('cancel')) return EE.fail;
    if (t.contains('completed')) return EE.pass;
    if (t.contains('review') || t.contains('zones') || t.contains('alignment')) return EE.uncertain;
    if (t.contains('report') || t.contains('export')) return EE.violet;
    if (t.contains('run_started') || t.contains('reinspection')) return EE.cyan;
    return EE.textMuted;
  }

  static String _summary(Json e) {
    final d = e.obj('details');
    final t = e.str('event_type');
    final parts = <String>[];
    switch (t) {
      case 'asset_uploaded':
        parts.add('${d.str('kind')}: ${d.str('filename')}');
        if (d.strN('sha256') != null) parts.add('sha256 ${d.str('sha256').substring(0, 12)}…');
      case 'run_completed':
        final s = d.obj('summary');
        parts.add('${s.integer('pass')} PASS · ${s.integer('fail')} FAIL · ${s.integer('uncertain')} UNCERTAIN');
        if (d.intN('duration_ms') != null) parts.add(fmtMs(d.intN('duration_ms')));
      case 'run_failed':
        parts.add('stage ${d.str('stage')}: ${d.str('error')}');
      case 'review_recorded':
        parts.add('#${d.integer('seq')} ${d.str('action')}${d.strN('resulting_verdict') != null ? ' → ${d.str('resulting_verdict')}' : ''}');
      case 'report_generated' || 'export_generated':
        parts.add(d.str('format').toUpperCase());
        if (d.intN('pages') != null) parts.add('${d.integer('pages')} pages');
      case 'reinspection_created':
        parts.add('v${d.integer('version_no')} from v${d.integer('parent_version_no')}${d.boolean('reuse_photo') ? ', photo reused' : ''}');
      case 'versions_compared':
        final c = d.obj('counts');
        parts.add('v${d.integer('from')} → v${d.integer('to')}: ${c.entries.map((x) => '${x.key.replaceAll('_', ' ')} ${x.value}').join(', ')}');
      default:
        for (final k in ['version_no', 'kind', 'fields', 'anchors', 'code']) {
          if (d[k] != null) parts.add('$k: ${d[k] is List ? (d[k] as List).join(', ') : d[k]}');
        }
    }
    if (d.containsKey('version_no') && !parts.any((p) => p.contains('v${d['version_no']}')) && t != 'reinspection_created') parts.insert(0, 'v${d['version_no']}');
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final t = event.str('event_type');
    final c = _color(t);
    final summary = _summary(event);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 138,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(fmtTime(event.time('created_at')), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim)),
          ),
        ),
        SizedBox(
          width: 22,
          child: Column(children: [
            Container(margin: const EdgeInsets.only(top: 3), width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: c, boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6)])),
            if (!last) Expanded(child: Container(width: 1, color: EE.line)),
          ]),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(titleCase(t), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c == EE.textMuted ? EE.text : c)),
                Text(event.str('actor'), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.textDim)),
              ]),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(summary, style: const TextStyle(fontSize: 11.5, color: EE.textMuted, height: 1.4)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
