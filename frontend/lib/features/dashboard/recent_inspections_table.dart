import 'dart:async';

import 'package:flutter/material.dart' hide Page;
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

/// F · Recent inspections: search, filters, sorting and pagination over GET /inspections.
class RecentInspectionsTable extends ConsumerStatefulWidget {
  const RecentInspectionsTable({super.key, this.day, this.onClearDay, this.refreshToken = 0});

  /// yyyy-MM-dd; restricts the list to inspections created that day (set by the volume chart).
  final String? day;
  final VoidCallback? onClearDay;
  final int refreshToken;

  @override
  ConsumerState<RecentInspectionsTable> createState() => _RecentInspectionsTableState();
}

class _RecentInspectionsTableState extends ConsumerState<RecentInspectionsTable> {
  static const _pageSize = 10;
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  String? _status;
  String? _verdict;
  String _sort = 'created_at';
  String _order = 'desc';
  int _page = 1;
  Future<Page<Inspection>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RecentInspectionsTable old) {
    super.didUpdateWidget(old);
    if (old.day != widget.day || old.refreshToken != widget.refreshToken) {
      if (old.day != widget.day) _page = 1;
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _load() {
    final api = ref.read(apiProvider);
    final ds = ref.read(datasetProvider);
    setState(() {
      _future = api.inspections(
        q: _q,
        dataset: ds,
        status: _status,
        verdict: _verdict,
        sort: _sort,
        order: _order,
        page: _page,
        pageSize: _pageSize,
        dateFrom: widget.day,
        dateTo: widget.day,
      );
    });
  }

  void _set(VoidCallback f) {
    f();
    _page = 1;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(datasetProvider, (_, _) => _set(() {}));
    final narrow = MediaQuery.sizeOf(context).width < 640;
    return Panel(
      eyebrow: 'F · Inspections',
      title: 'Recent inspections',
      subtitle: 'Counts are machine verdicts of the latest version; review shows how many findings a human has reviewed.',
      actions: [
        IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded, size: 17), onPressed: _load),
        TextButton(onPressed: () => context.go('/console/history'), child: const Text('Full history')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _filters(narrow),
        if (widget.day != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              avatar: const Icon(Icons.event_rounded, size: 15, color: EE.cyan),
              label: Text('Created on ${widget.day}'),
              onDeleted: widget.onClearDay,
              deleteIcon: const Icon(Icons.close_rounded, size: 15),
            ),
          ),
        ],
        const SizedBox(height: 12),
        FutureBuilder<Page<Inspection>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(snap.error!, onRetry: _load, compact: true);
            if (!snap.hasData) return const SizedBox(height: 120, child: LoadingView(label: 'Loading inspections'));
            final page = snap.data!;
            if (page.items.isEmpty) {
              final filtered = _q.isNotEmpty || _status != null || _verdict != null || widget.day != null;
              return EmptyState(
                title: filtered ? 'No inspections match these filters' : 'No inspections yet',
                message: filtered ? 'Clear the search or filters to see all inspections.' : 'Create an inspection or run the sample inspection to get started.',
                icon: Icons.manage_search_rounded,
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              LayoutBuilder(builder: (context, c) => c.maxWidth < 860 ? _cards(page.items) : _table(page.items)),
              const SizedBox(height: 10),
              _pager(page),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _filters(bool narrow) {
    final search = SizedBox(
      width: narrow ? double.infinity : 260,
      child: TextField(
        controller: _search,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded, size: 18), hintText: 'Search ID, cabinet, title, site…'),
        onChanged: (v) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 350), () => _set(() => _q = v.trim()));
        },
      ),
    );
    Widget dd<T>(String label, T? value, Map<T?, String> opts, ValueChanged<T?> onChanged) => _Drop<T>(label: label, value: value, options: opts, onChanged: onChanged);
    return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      search,
      dd<String>('Status', _status, const {null: 'Any status', 'draft': 'Draft', 'queued': 'Queued', 'running': 'Running', 'completed': 'Completed', 'failed': 'Failed', 'cancelled': 'Cancelled'},
          (v) => _set(() => _status = v)),
      dd<String>('Verdict', _verdict, const {null: 'Any verdict', 'FAIL': 'Has FAIL', 'UNCERTAIN': 'Has UNCERTAIN', 'NEEDS_REVIEW': 'Needs review', 'PASS': 'Has PASS'},
          (v) => _set(() => _verdict = v)),
      dd<String>('Sort', _sort, const {'created_at': 'Created', 'code': 'Inspection ID', 'cabinet_id': 'Cabinet', 'title': 'Title', 'status': 'Status'},
          (v) => _set(() => _sort = v ?? 'created_at')),
      IconButton(
        tooltip: _order == 'desc' ? 'Descending' : 'Ascending',
        icon: Icon(_order == 'desc' ? Icons.south_rounded : Icons.north_rounded, size: 17),
        onPressed: () => _set(() => _order = _order == 'desc' ? 'asc' : 'desc'),
      ),
    ]);
  }

  Widget _pager(Page<Inspection> p) {
    final from = (p.page - 1) * p.pageSize + 1;
    final to = from + p.items.length - 1;
    final pages = (p.total / p.pageSize).ceil();
    return Row(children: [
      Text('$from–$to of ${p.total}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted)),
      const Spacer(),
      IconButton(
        tooltip: 'Previous page',
        icon: const Icon(Icons.chevron_left_rounded),
        onPressed: _page > 1
            ? () {
                _page--;
                _load();
              }
            : null,
      ),
      Text('$_page / ${pages < 1 ? 1 : pages}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5)),
      IconButton(
        tooltip: 'Next page',
        icon: const Icon(Icons.chevron_right_rounded),
        onPressed: _page < pages
            ? () {
                _page++;
                _load();
              }
            : null,
      ),
    ]);
  }

  // --- wide table --------------------------------------------------------------
  static const _cols = <(String, double?)>[
    ('Inspection', 112),
    ('Cabinet / case', null),
    ('Created', 112),
    ('Inputs', 84),
    ('Status', 128),
    ('PASS', 48),
    ('FAIL', 48),
    ('UNC', 48),
    ('Review', 112),
    ('', 84),
  ];

  Widget _cell(int i, Widget child) {
    final w = _cols[i].$2;
    final padded = Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: child);
    return w == null ? Expanded(child: padded) : SizedBox(width: w, child: padded);
  }

  Widget _table(List<Inspection> items) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: EE.lineHi))),
        child: Row(children: [
          for (var i = 0; i < _cols.length; i++)
            _cell(
              i,
              Text(_cols[i].$1.toUpperCase(),
                  textAlign: i >= 5 && i <= 7 ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    fontFamily: EE.fontMono,
                    fontSize: 9.5,
                    letterSpacing: 1.2,
                    color: i == 5 ? EE.pass : (i == 6 ? EE.fail : (i == 7 ? EE.uncertain : EE.textDim)),
                  )),
            ),
        ]),
      ),
      for (final insp in items) _row(insp),
    ]);
  }

  Widget _row(Inspection insp) {
    final v = insp.latest;
    final s = v?.summary;
    final done = v?.status == 'completed';
    return _HoverRow(
      onTap: () => context.go(workspaceLink(insp.id, version: v?.no)),
      child: Row(children: [
        _cell(
          0,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(insp.code, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5, color: EE.cyan, fontWeight: FontWeight.w600)),
            if (insp.isDemo) const Padding(padding: EdgeInsets.only(top: 3), child: DemoTag(compact: true)),
          ]),
        ),
        _cell(
          1,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(insp.cabinetId, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5, fontWeight: FontWeight.w600)),
            Text(insp.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: EE.textMuted)),
          ]),
        ),
        _cell(
          2,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fmtDate(insp.createdAt), style: const TextStyle(fontSize: 12)),
            Text(ago(insp.createdAt), style: const TextStyle(fontSize: 11, color: EE.textDim)),
          ]),
        ),
        _cell(3, InputCompleteness(version: v)),
        _cell(
          4,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            v == null ? const Text('—') : StatePill(v.status),
            if (v != null) Text('v${v.no}${insp.versionCount > 1 ? ' of ${insp.versionCount}' : ''}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.textDim)),
          ]),
        ),
        _cell(5, _num(done ? s!.pass : null, EE.pass)),
        _cell(6, _num(done ? s!.fail : null, EE.fail)),
        _cell(7, _num(done ? s!.uncertain : null, EE.uncertain)),
        _cell(8, ReviewStatus(version: v)),
        _cell(
          9,
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(
              tooltip: 'Open in workspace',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              onPressed: () => context.go(workspaceLink(insp.id, version: v?.no)),
            ),
            IconButton(
              tooltip: 'Inspection history',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.history_rounded, size: 16),
              onPressed: () => context.go('/console/history?i=${insp.id}'),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _num(int? n, Color c) => Text(
        n == null ? '—' : '$n',
        textAlign: TextAlign.right,
        style: TextStyle(fontFamily: EE.fontMono, fontSize: 13, fontWeight: FontWeight.w600, color: n == null || n == 0 ? EE.textDim : c),
      );

  // --- narrow cards ------------------------------------------------------------
  Widget _cards(List<Inspection> items) {
    return Column(children: [
      for (final insp in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => context.go(workspaceLink(insp.id, version: insp.latest?.no)),
            borderRadius: BorderRadius.circular(EE.r2),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(insp.code, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5, color: EE.cyan, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  if (insp.isDemo) const DemoTag(compact: true),
                  const Spacer(),
                  if (insp.latest != null) StatePill(insp.latest!.status),
                ]),
                const SizedBox(height: 6),
                Text('${insp.cabinetId} · ${insp.title}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 8),
                Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(ago(insp.createdAt), style: const TextStyle(fontSize: 11, color: EE.textDim)),
                  InputCompleteness(version: insp.latest),
                  if (insp.latest?.status == 'completed')
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final (n, c) in [(insp.latest!.summary.pass, EE.pass), (insp.latest!.summary.fail, EE.fail), (insp.latest!.summary.uncertain, EE.uncertain)])
                        Padding(padding: const EdgeInsets.only(right: 8), child: Text('$n', style: TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: c, fontWeight: FontWeight.w600))),
                    ]),
                  ReviewStatus(version: insp.latest),
                ]),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Which of the three required inputs exist on a version.
class InputCompleteness extends StatelessWidget {
  const InputCompleteness({super.key, required this.version});
  final Version? version;

  @override
  Widget build(BuildContext context) {
    const kinds = [('photo', Icons.photo_camera_outlined, 'Cabinet photo'), ('drawing', Icons.architecture_rounded, 'GA drawing'), ('expected_list', Icons.table_chart_outlined, 'Expected list')];
    final present = kinds.where((k) => version?.asset(k.$1) != null).length;
    return Tooltip(
      message: kinds.map((k) {
        final a = version?.asset(k.$1);
        return '${k.$3}: ${a == null ? 'missing' : a.filename}';
      }).join('\n'),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final k in kinds)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(k.$2, size: 15, color: version?.asset(k.$1) != null ? EE.cyan : EE.textDim.withValues(alpha: 0.6)),
          ),
        Text('$present/3', style: TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: present == 3 ? EE.textMuted : EE.uncertain)),
      ]),
    );
  }
}

class ReviewStatus extends StatelessWidget {
  const ReviewStatus({super.key, required this.version});
  final Version? version;

  @override
  Widget build(BuildContext context) {
    final v = version;
    if (v == null || v.findingCount == 0) return const Text('—', style: TextStyle(color: EE.textDim));
    final open = v.effective['UNCERTAIN'] ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('${v.reviewedCount}/${v.findingCount} reviewed', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textMuted)),
      if (open > 0)
        Text('$open uncertain open', style: const TextStyle(fontSize: 10.5, color: EE.uncertain, fontWeight: FontWeight.w600))
      else
        const Text('no open uncertain', style: TextStyle(fontSize: 10.5, color: EE.textDim)),
    ]);
  }
}

class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: EE.fast,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: _h ? EE.surfaceHi : Colors.transparent,
              border: const Border(bottom: BorderSide(color: EE.line)),
            ),
            child: widget.child,
          ),
        ),
      );
}

class _Drop<T> extends StatelessWidget {
  const _Drop({required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final T? value;
  final Map<T?, String> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T?>(
      tooltip: label,
      color: EE.surfaceHi,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final e in options.entries)
          PopupMenuItem<T?>(
            value: e.key,
            child: Row(children: [
              Icon(e.key == value ? Icons.check_rounded : Icons.circle_outlined, size: 14, color: e.key == value ? EE.cyan : Colors.transparent),
              const SizedBox(width: 8),
              Text(e.value, style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: EE.bg1, border: Border.all(color: value == null ? EE.line : EE.cyan.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(EE.r2)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ', style: const TextStyle(fontSize: 12, color: EE.textDim)),
          Text(options[value] ?? '$value', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, size: 16, color: EE.textMuted),
        ]),
      ),
    );
  }
}
