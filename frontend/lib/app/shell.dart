import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api_client.dart';
import '../core/api/models.dart';
import '../core/config/app_config.dart';
import '../core/state/providers.dart';
import '../core/theme/tokens.dart';
import '../core/util/download.dart';
import '../core/util/format.dart';
import '../core/widgets/badges.dart';
import '../core/widgets/grid_background.dart';
import 'brand.dart';
import 'router.dart';

class ConsoleShell extends ConsumerWidget {
  const ConsoleShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = MediaQuery.sizeOf(context).width;
    final mode = w >= 1180 ? _NavMode.full : (w >= 720 ? _NavMode.rail : _NavMode.drawer);
    final current = navFor(location);
    final body = Column(children: [
      _TopBar(current: current, showMenu: mode == _NavMode.drawer),
      Expanded(
        child: Stack(children: [
          const Positioned.fill(child: GridBackground(opacity: 0.35)),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(w < 720 ? 14 : 28, 22, w < 720 ? 14 : 28, 0),
              child: child,
            ),
          ),
        ]),
      ),
    ]);
    return Scaffold(
      backgroundColor: EE.bg0,
      drawer: mode == _NavMode.drawer ? Drawer(backgroundColor: EE.bg1, width: 280, child: _Sidebar(current: current, compact: false, inDrawer: true)) : null,
      body: Row(children: [
        if (mode != _NavMode.drawer) _Sidebar(current: current, compact: mode == _NavMode.rail),
        Expanded(child: body),
      ]),
    );
  }
}

enum _NavMode { full, rail, drawer }

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.current, required this.compact, this.inDrawer = false});
  final NavItem? current;
  final bool compact;
  final bool inDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <String, List<NavItem>>{};
    for (final n in navItems) {
      groups.putIfAbsent(n.group, () => []).add(n);
    }
    return AnimatedContainer(
      duration: EE.med,
      width: compact ? 72 : 252,
      decoration: const BoxDecoration(color: EE.bg1, border: Border(right: BorderSide(color: EE.line))),
      child: Column(children: [
        InkWell(
          onTap: () => context.go('/console'),
          child: Padding(
            padding: EdgeInsets.fromLTRB(compact ? 0 : 20, 20, compact ? 0 : 16, 18),
            child: compact ? const Center(child: BrandMark(size: 26)) : const BrandLockup(),
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: [
            for (final g in groups.entries) ...[
              if (!compact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 16, 6),
                  child: Text(g.key.toUpperCase(), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 9.5, letterSpacing: 1.8, color: EE.textDim)),
                )
              else
                const SizedBox(height: 10),
              for (final n in g.value) _NavTile(item: n, selected: current == n, compact: compact, inDrawer: inDrawer),
            ],
          ]),
        ),
        const Divider(),
        if (!compact)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 16, 16),
            child: Row(children: [
              Icon(Icons.badge_outlined, size: 16, color: EE.textDim),
              SizedBox(width: 8),
              Expanded(
                child: Text('local-demo-reviewer\nNo authentication in this prototype', style: TextStyle(fontSize: 10.5, color: EE.textDim, height: 1.4)),
              ),
            ]),
          )
        else
          const Padding(padding: EdgeInsets.all(14), child: Icon(Icons.badge_outlined, size: 16, color: EE.textDim)),
      ]),
    );
  }
}

class _NavTile extends ConsumerWidget {
  const _NavTile({required this.item, required this.selected, required this.compact, required this.inDrawer});
  final NavItem item;
  final bool selected;
  final bool compact;
  final bool inDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeJobsProvider);
    final badge = item.path == '/console/live' && active.isNotEmpty ? '${active.length}' : null;
    final tile = AnimatedContainer(
      duration: EE.fast,
      margin: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: 1.5),
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? EE.cyan.withValues(alpha: 0.09) : Colors.transparent,
        borderRadius: BorderRadius.circular(EE.r2),
        border: Border.all(color: selected ? EE.cyan.withValues(alpha: 0.35) : Colors.transparent),
      ),
      child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
        Icon(item.icon, size: 18, color: selected ? EE.cyan : EE.textMuted),
        if (!compact) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(item.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? EE.text : EE.textMuted)),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: EE.cyan, borderRadius: BorderRadius.circular(8)),
              child: Text(badge, style: const TextStyle(fontSize: 10.5, color: EE.bg0, fontWeight: FontWeight.w700)),
            ),
        ],
      ]),
    );
    return Tooltip(
      message: compact ? item.label : '',
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        borderRadius: BorderRadius.circular(EE.r2),
        onTap: () {
          if (inDrawer) Navigator.of(context).pop();
          context.go(item.path);
        },
        child: tile,
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.current, required this.showMenu});
  final NavItem? current;
  final bool showMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(systemStatusProvider);
    final jobs = ref.watch(activeJobsProvider);
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final st = status.value;
    final apiState = status.hasError ? 'error' : (st == null ? 'loading' : 'ok');
    return Container(
      height: 58,
      padding: EdgeInsets.symmetric(horizontal: showMenu ? 6 : 24),
      decoration: const BoxDecoration(color: EE.bg1, border: Border(bottom: BorderSide(color: EE.line))),
      child: Row(children: [
        if (showMenu) IconButton(icon: const Icon(Icons.menu_rounded), onPressed: () => Scaffold.of(context).openDrawer()),
        if (!narrow) ...[
          const Icon(Icons.factory_outlined, size: 16, color: EE.textDim),
          const SizedBox(width: 8),
          const Text('Local QA lab', style: TextStyle(fontSize: 12.5, color: EE.textMuted)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('/', style: TextStyle(color: EE.textDim))),
        ],
        InkWell(onTap: () => context.go('/console'), child: const Text('Console', style: TextStyle(fontSize: 12.5, color: EE.textMuted))),
        if (current != null && current!.path != '/console') ...[
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('/', style: TextStyle(color: EE.textDim))),
          Flexible(child: Text(current!.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
        ],
        const Spacer(),
        if (jobs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () => context.go('/console/live?job=${jobs.first.id}'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: EE.cyan.withValues(alpha: 0.08), border: Border.all(color: EE.cyan.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(EE.r1)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const StatusDot(color: EE.cyan, pulse: true, size: 6),
                  const SizedBox(width: 4),
                  Text(
                    narrow ? '${jobs.length}' : '${jobs.first.inspectionCode ?? 'job'} · ${titleCase(jobs.first.currentStage ?? jobs.first.status)}${jobs.length > 1 ? ' +${jobs.length - 1}' : ''}',
                    style: const TextStyle(fontSize: 12, color: EE.cyan, fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
            ),
          ),
        _Indicator(label: 'API', state: apiState, tooltip: status.hasError ? status.error.toString() : 'Backend reachable at ${ref.watch(appConfigProvider).apiBase}'),
        if (!narrow) ...[
          _Indicator(label: 'DB', state: st?.byKey('database')?.state ?? 'pending', tooltip: st?.byKey('database')?.message ?? ''),
          _Indicator(label: 'YOLO', state: st?.byKey('detector')?.state ?? 'pending', tooltip: st?.byKey('detector')?.message ?? ''),
          _Indicator(label: 'OCR', state: st?.byKey('ocr')?.state ?? 'pending', tooltip: st?.byKey('ocr')?.message ?? ''),
        ],
        const SizedBox(width: 6),
        const _Notifications(),
        IconButton(tooltip: 'Help & API documentation', icon: const Icon(Icons.help_outline_rounded, size: 19), onPressed: () => _help(context, ref)),
        const Tooltip(
          message: 'Local demo reviewer identity — authentication is not enabled in this prototype',
          child: Padding(
            padding: EdgeInsets.only(left: 4, right: 4),
            child: CircleAvatar(radius: 14, backgroundColor: EE.titanium, child: Icon(Icons.person_outline_rounded, size: 16, color: EE.textMuted)),
          ),
        ),
      ]),
    );
  }

  void _help(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiProvider);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('EAGLE EYE help'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('Workflow', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text('1. New Inspection: enter case details, upload the cabinet photo, GA drawing (PDF) and expected list (XLSX/CSV).\n'
                '2. Validate inputs and run. Live Inspection shows the real backend stages.\n'
                '3. Inspection Workspace: review findings with image evidence; resolve UNCERTAIN items.\n'
                '4. Reinspect after corrections; History compares versions. Export reports from Reports & Exports.'),
            SizedBox(height: 14),
            Text('Verdicts', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text('PASS requires positive evidence. FAIL requires reliable contrary evidence. Everything else is UNCERTAIN and needs human review — '
                'it is never counted as a pass or a failure.'),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/welcome');
            },
            child: const Text('Product overview'),
          ),
          TextButton(onPressed: () => openUrl(api.url('/api/v1/docs')), child: const Text('Open API docs (OpenAPI)')),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({required this.label, required this.state, required this.tooltip});
  final String label;
  final String state;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '$label: $state${tooltip.isEmpty ? '' : '\n$tooltip'}',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            StatusDot(color: EE.state(state), size: 6, pulse: state == 'loading'),
            Text(label, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, letterSpacing: 0.8, color: EE.textMuted)),
          ]),
        ),
      );
}

class _Notifications extends ConsumerWidget {
  const _Notifications();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Recent activity',
      icon: const Icon(Icons.notifications_none_rounded, size: 19),
      onPressed: () async {
        final api = ref.read(apiProvider);
        final box = context.findRenderObject() as RenderBox?;
        final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
        List<Json> items = const [];
        Object? err;
        try {
          items = await api.activity(limit: 12);
        } catch (e) {
          err = e;
        }
        if (!context.mounted) return;
        showMenu<void>(
          context: context,
          color: EE.surfaceHi,
          position: RelativeRect.fromLTRB(pos.dx - 320, pos.dy + 44, pos.dx + 40, 0),
          items: [
            if (err != null) PopupMenuItem(enabled: false, child: Text('Unavailable: $err', style: const TextStyle(color: EE.fail, fontSize: 12))),
            if (err == null && items.isEmpty) const PopupMenuItem(enabled: false, child: Text('No activity yet', style: TextStyle(fontSize: 12.5))),
            for (final a in items)
              PopupMenuItem(
                onTap: () => context.go(workspaceLink(a.str('inspection_id'), version: a.intN('version_no'))),
                child: SizedBox(
                  width: 330,
                  child: Row(children: [
                    StatusDot(color: EE.state(a.str('event_type').contains('failed') ? 'failed' : (a.str('event_type').contains('completed') ? 'completed' : 'running')), size: 6),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${a.str('inspection_code')} · ${titleCase(a.str('event_type'))}${a.intN('version_no') != null ? ' v${a.intN('version_no')}' : ''}',
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                    Text(ago(a.time('created_at')), style: const TextStyle(fontSize: 11, color: EE.textDim)),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}
