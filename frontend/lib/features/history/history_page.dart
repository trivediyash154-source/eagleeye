import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import '../review/dataset_toggle.dart';
import 'history_detail.dart';

typedef _ListKey = ({String q, String dataset, int page, String sort});

const _pageSize = 15;

final _listProvider = FutureProvider.family<Page<Inspection>, _ListKey>(
    (ref, k) => ref.watch(apiProvider).inspections(q: k.q, dataset: k.dataset, page: k.page, pageSize: _pageSize, sort: k.sort, order: k.sort == 'created_at' ? 'desc' : 'asc'));

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, this.inspectionId});
  final String? inspectionId;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _search = TextEditingController();
  String _q = '';
  int _page = 1;
  String _sort = 'created_at';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _select(String? id) => context.go(id == null ? '/console/history' : '/console/history?i=$id');

  _ListKey get _key => (q: _q, dataset: ref.watch(datasetProvider), page: _page, sort: _sort);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    final selected = widget.inspectionId;
    final header = PageHeader(
      eyebrow: 'Audit trail',
      title: 'Inspection History',
      description: 'Every inspection keeps an immutable sequence of versions. Reinspections never overwrite earlier runs; outcomes are compared by stable finding keys.',
      actions: [
        const DatasetToggle(),
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(_listProvider(_key));
            if (selected != null) {
              ref.invalidate(inspectionProvider(selected));
              ref.invalidate(timelineProvider(selected));
            }
          },
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh'),
        ),
      ],
    );
    if (!wide) {
      if (selected != null) {
        return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => _select(null), icon: const Icon(Icons.arrow_back_rounded, size: 16), label: const Text('All inspections')),
          ),
          const SizedBox(height: 8),
          HistoryDetail(inspectionId: selected),
        ]);
      }
      return ListView(padding: const EdgeInsets.only(bottom: 40), children: [header, _list(null, shrink: true)]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 380, child: _list(selected, shrink: false)),
          const SizedBox(width: EE.s4),
          Expanded(
            child: selected == null
                ? const Panel(
                    child: EmptyState(
                      title: 'Select an inspection',
                      message: 'Choose an inspection on the left to see its versions, comparisons and audit trail.',
                      icon: Icons.history_rounded,
                    ),
                  )
                : SingleChildScrollView(padding: const EdgeInsets.only(bottom: 40), child: HistoryDetail(inspectionId: selected)),
          ),
        ]),
      ),
    ]);
  }

  Widget _list(String? selected, {required bool shrink}) {
    final data = ref.watch(_listProvider(_key));
    final body = AsyncView<Page<Inspection>>(
      data,
      onRetry: () => ref.invalidate(_listProvider(_key)),
      data: (p) {
        if (p.items.isEmpty) {
          return EmptyState(
            title: _q.isEmpty ? 'No inspections yet' : 'No inspections match “$_q”',
            message: _q.isEmpty ? 'Create an inspection or run the sample inspection from the Overview.' : null,
            icon: Icons.search_off_rounded,
          );
        }
        final pages = (p.total / _pageSize).ceil().clamp(1, 100000);
        final rows = [for (final i in p.items) _InspectionRow(inspection: i, selected: i.id == selected, onTap: () => _select(i.id))];
        final pager = Row(children: [
          Text('${p.total} inspection${p.total == 1 ? '' : 's'}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textDim)),
          const Spacer(),
          IconButton(onPressed: _page > 1 ? () => setState(() => _page--) : null, icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Previous page'),
          Text('$_page / $pages', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted)),
          IconButton(onPressed: _page < pages ? () => setState(() => _page++) : null, icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Next page'),
        ]);
        if (shrink) return Column(children: [...rows, pager]);
        return Column(children: [Expanded(child: ListView(children: rows)), pager]);
      },
    );
    return Panel(
      eyebrow: 'Inspections',
      title: 'Cases',
      expand: !shrink,
      padding: const EdgeInsets.fromLTRB(EE.s3, EE.s1, EE.s3, EE.s2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            hintText: 'Search code, title, cabinet, site, reference',
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => setState(() {
                      _search.clear();
                      _q = '';
                      _page = 1;
                    }),
                  ),
          ),
          onSubmitted: (v) => setState(() {
            _q = v.trim();
            _page = 1;
          }),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Sort ', style: TextStyle(fontSize: 11.5, color: EE.textDim)),
          DropdownButton<String>(
            value: _sort,
            isDense: true,
            underline: const SizedBox(),
            dropdownColor: EE.surfaceHi,
            style: const TextStyle(fontSize: 12, color: EE.text),
            items: const [
              DropdownMenuItem(value: 'created_at', child: Text('Newest first')),
              DropdownMenuItem(value: 'code', child: Text('Inspection code')),
              DropdownMenuItem(value: 'cabinet_id', child: Text('Cabinet')),
              DropdownMenuItem(value: 'status', child: Text('Status')),
            ],
            onChanged: (v) => setState(() {
              _sort = v ?? 'created_at';
              _page = 1;
            }),
          ),
        ]),
        const SizedBox(height: 4),
        if (shrink) body else Expanded(child: body),
      ]),
    );
  }
}

class _InspectionRow extends StatelessWidget {
  const _InspectionRow({required this.inspection, required this.selected, required this.onTap});
  final Inspection inspection;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = inspection.latest;
    final s = v?.summary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(EE.r2),
      child: AnimatedContainer(
        duration: EE.fast,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? EE.cyan.withValues(alpha: 0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(EE.r2),
          border: Border.all(color: selected ? EE.cyan.withValues(alpha: 0.45) : EE.line.withValues(alpha: 0.6)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(inspection.code, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.cyan, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (inspection.isDemo) const DemoTag(compact: true),
            const Spacer(),
            Text(ago(inspection.createdAt), style: const TextStyle(fontSize: 11, color: EE.textDim)),
          ]),
          const SizedBox(height: 4),
          Text(inspection.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(children: [
            Text('${inspection.cabinetId} · ${inspection.versionCount} version${inspection.versionCount == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11.5, color: EE.textMuted)),
            const Spacer(),
            if (v != null) StatePill(v.status),
          ]),
          if (s != null && v!.status == 'completed') ...[
            const SizedBox(height: 6),
            Row(children: [
              _mini('PASS', s.pass),
              _mini('FAIL', s.fail),
              _mini('UNCERTAIN', s.uncertain),
              const Spacer(),
              if (v.reviewedCount > 0) Text('${v.reviewedCount} reviewed', style: const TextStyle(fontSize: 10.5, color: EE.textDim)),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _mini(String verdict, int n) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: EE.verdict(verdict), shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('$n', style: TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.verdict(verdict))),
        ]),
      );
}
