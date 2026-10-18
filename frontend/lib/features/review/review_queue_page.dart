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
import '../inspections/finding_detail.dart';
import 'dataset_toggle.dart';

typedef _QueueKey = ({String dataset, String sort});

final _queueProvider = FutureProvider.family<Json, _QueueKey>((ref, k) => ref.watch(apiProvider).reviewQueue(sort: k.sort, dataset: k.dataset));

Color tierColor(int tier) => switch (tier) {
      1 => EE.fail,
      2 => EE.violet,
      3 => EE.uncertain,
      _ => EE.ice,
    };

class ReviewQueuePage extends ConsumerStatefulWidget {
  const ReviewQueuePage({super.key});
  @override
  ConsumerState<ReviewQueuePage> createState() => _ReviewQueuePageState();
}

class _ReviewQueuePageState extends ConsumerState<ReviewQueuePage> {
  String _sort = 'tier';
  String? _reason;
  String? _check;

  _QueueKey get _key => (dataset: ref.watch(datasetProvider), sort: _sort);

  void _refresh() {
    ref.invalidate(_queueProvider(_key));
    ref.invalidate(recentInspectionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(_queueProvider(_key));
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: PageHeader(
          eyebrow: 'Human oversight',
          title: 'Review Queue',
          description:
              'Findings that need a human decision: machine FAILs awaiting confirmation and every UNCERTAIN item, with the machine-readable reason it could not be decided. '
              'Review decisions are stored separately — the original machine finding is never edited.',
          actions: [
            const DatasetToggle(),
            OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Refresh')),
          ],
        ),
      ),
      if (q.hasValue)
        ..._content(q.requireValue)
      else if (q.hasError)
        SliverToBoxAdapter(child: ErrorView(q.error!, onRetry: _refresh))
      else
        const SliverToBoxAdapter(child: LoadingView(label: 'Loading review queue')),
      const SliverToBoxAdapter(child: SizedBox(height: 40)),
    ]);
  }

  List<Widget> _content(Json data) {
    final all = data.objs('items');
    final tiers = data.obj('tiers');
    // counts are computed from the unfiltered queue so the filter chips stay stable
    final reasonCounts = <String, int>{};
    final checkCounts = <String, int>{};
    final tierCounts = <int, int>{};
    for (final it in all) {
      for (final r in it.strs('reasons')) {
        reasonCounts[r] = (reasonCounts[r] ?? 0) + 1;
      }
      checkCounts[it.str('check_type')] = (checkCounts[it.str('check_type')] ?? 0) + 1;
      tierCounts[it.integer('tier')] = (tierCounts[it.integer('tier')] ?? 0) + 1;
    }
    final items = all.where((it) => (_reason == null || it.strs('reasons').contains(_reason)) && (_check == null || it.str('check_type') == _check)).toList();
    if (all.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Panel(
            child: EmptyState(
              title: 'Nothing needs review',
              message: 'No UNCERTAIN findings and no unconfirmed FAILs in the latest completed version of any inspection in this dataset.',
              icon: Icons.verified_outlined,
            ),
          ),
        ),
      ];
    }
    final summary = ResponsiveRow(flex: const [5, 6], breakpoint: 1050, children: [
      _TierLegend(tiers: tiers, counts: tierCounts, ordering: data.str('ordering')),
      _Filters(
        reasonCounts: reasonCounts,
        checkCounts: checkCounts,
        reason: _reason,
        check: _check,
        sort: _sort,
        total: all.length,
        shown: items.length,
        onReason: (r) => setState(() => _reason = r),
        onCheck: (c) => setState(() => _check = c),
        onSort: (s) => setState(() => _sort = s),
      ),
    ]);
    final slivers = <Widget>[SliverToBoxAdapter(child: summary), const SliverToBoxAdapter(child: SizedBox(height: EE.s5))];
    if (items.isEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: EmptyState(
          title: 'No items match these filters',
          icon: Icons.filter_alt_off_outlined,
          action: TextButton(onPressed: () => setState(() => _reason = _check = null), child: const Text('Clear filters')),
        ),
      ));
      return slivers;
    }
    if (_sort == 'tier') {
      final grouped = <int, List<Json>>{};
      for (final it in items) {
        grouped.putIfAbsent(it.integer('tier'), () => []).add(it);
      }
      for (final t in grouped.keys.toList()..sort()) {
        slivers.add(SliverToBoxAdapter(child: _TierHeader(tier: t, label: tiers.str('$t'), count: grouped[t]!.length)));
        slivers.add(SliverList.separated(
          itemCount: grouped[t]!.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _QueueRow(item: grouped[t]![i], onReviewed: _refresh),
        ));
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: EE.s5)));
      }
    } else {
      slivers.add(SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _QueueRow(item: items[i], onReviewed: _refresh),
      ));
    }
    return slivers;
  }
}

class _TierLegend extends StatelessWidget {
  const _TierLegend({required this.tiers, required this.counts, required this.ordering});
  final Json tiers;
  final Map<int, int> counts;
  final String ordering;

  @override
  Widget build(BuildContext context) {
    final keys = tiers.keys.map(int.parse).toList()..sort();
    return Panel(
      eyebrow: 'Prioritisation',
      title: 'Review tiers',
      subtitle: 'Defined categories, not an urgency score.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final t in keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 26,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tierColor(t).withValues(alpha: 0.12), border: Border.all(color: tierColor(t).withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(EE.r1)),
                child: Text('T$t', style: TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, fontWeight: FontWeight.w700, color: tierColor(t))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(tiers.str('$t'), style: const TextStyle(fontSize: 12.5))),
              SizedBox(width: 34, child: Text('${counts[t] ?? 0}', textAlign: TextAlign.right, style: TextStyle(fontFamily: EE.fontMono, fontSize: 13, fontWeight: FontWeight.w600, color: (counts[t] ?? 0) > 0 ? tierColor(t) : EE.textDim))),
            ]),
          ),
        const SizedBox(height: 6),
        Text('Ordering: $ordering.', style: const TextStyle(fontSize: 11.5, color: EE.textDim)),
      ]),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.reasonCounts,
    required this.checkCounts,
    required this.reason,
    required this.check,
    required this.sort,
    required this.total,
    required this.shown,
    required this.onReason,
    required this.onCheck,
    required this.onSort,
  });
  final Map<String, int> reasonCounts;
  final Map<String, int> checkCounts;
  final String? reason;
  final String? check;
  final String sort;
  final int total;
  final int shown;
  final ValueChanged<String?> onReason;
  final ValueChanged<String?> onCheck;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    final reasons = reasonCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Panel(
      eyebrow: 'Filter',
      title: 'Why items need review',
      subtitle: '$shown of $total items shown',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          _Chip(label: 'All reasons', count: total, selected: reason == null, onTap: () => onReason(null)),
          for (final r in reasons)
            _Chip(label: reasonLabels[r.key] ?? titleCase(r.key), count: r.value, selected: reason == r.key, onTap: () => onReason(reason == r.key ? null : r.key), color: r.key == 'unreviewed_fail' ? EE.fail : EE.uncertain),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Check  ', style: TextStyle(fontSize: 12, color: EE.textMuted)),
            DropdownButton<String?>(
              value: check,
              isDense: true,
              dropdownColor: EE.surfaceHi,
              underline: const SizedBox(),
              style: const TextStyle(fontSize: 12.5, color: EE.text),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All checks')),
                for (final c in checkCounts.entries) DropdownMenuItem<String?>(value: c.key, child: Text('${checkLabels[c.key] ?? titleCase(c.key)} (${c.value})')),
              ],
              onChanged: onCheck,
            ),
          ]),
          SegmentedPicker<String>(
            value: sort,
            options: const [('tier', 'By tier', Icons.layers_outlined), ('newest', 'Newest', Icons.schedule_rounded), ('inspection', 'By inspection', Icons.folder_open_outlined)],
            onChanged: onSort,
          ),
        ]),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.count, required this.selected, required this.onTap, this.color = EE.cyan});
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(EE.r1),
        child: AnimatedContainer(
          duration: EE.fast,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : EE.bg1,
            border: Border.all(color: selected ? color.withValues(alpha: 0.6) : EE.line),
            borderRadius: BorderRadius.circular(EE.r1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: selected ? EE.text : EE.textMuted)),
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: selected ? color : EE.textDim)),
          ]),
        ),
      );
}

class _TierHeader extends StatelessWidget {
  const _TierHeader({required this.tier, required this.label, required this.count});
  final int tier;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(width: 3, height: 16, color: tierColor(tier)),
          const SizedBox(width: 10),
          Text('TIER $tier', style: TextStyle(fontFamily: EE.fontMono, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w700, color: tierColor(tier))),
          const SizedBox(width: 10),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          const SizedBox(width: 10),
          Text('$count', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.textDim)),
        ]),
      );
}

class _QueueRow extends StatefulWidget {
  const _QueueRow({required this.item, required this.onReviewed});
  final Json item;
  final VoidCallback onReviewed;

  @override
  State<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<_QueueRow> {
  bool _expanded = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final tier = it.integer('tier');
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final verdict = it.str('effective_verdict');
    final machine = it.str('verdict');
    final expected = it.strN('expected_value');
    final observed = it.strN('observed_value');
    final ident = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        VerdictBadge(verdict, dense: true, reviewed: it.integer('review_count') > 0),
        if (machine != verdict) ...[const SizedBox(width: 6), Text('machine $machine', style: const TextStyle(fontSize: 10.5, color: EE.textDim))],
      ]),
      const SizedBox(height: 6),
      Text('#${it.integer('seq')} ${checkLabels[it.str('check_type')] ?? titleCase(it.str('check_type'))}', style: const TextStyle(fontSize: 12, color: EE.textMuted)),
      const SizedBox(height: 2),
      Text(it.str('subject'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      if (it.strN('zone_code') != null) Text('Zone ${it.str('zone_code')}', style: const TextStyle(fontSize: 11.5, color: EE.textDim)),
    ]);
    final evidence = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('expected', style: TextStyle(fontSize: 10.5, color: EE.textDim)),
        MonoValue(expected ?? '—'),
        const Icon(Icons.arrow_forward_rounded, size: 13, color: EE.textDim),
        const Text('observed', style: TextStyle(fontSize: 10.5, color: EE.textDim)),
        MonoValue(observed ?? '—', color: observed == null ? EE.textDim : EE.verdict(machine)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final r in it.strs('reasons')) r == 'unreviewed_fail' ? Tag(reasonLabels[r] ?? r, color: EE.fail) : ReasonChip(r)]),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Text(
          it.str('explanation'),
          maxLines: _expanded ? null : 2,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: EE.textMuted, height: 1.45),
        ),
      ),
    ]);
    final source = Column(crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
      Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (it.boolean('is_demo')) const DemoTag(compact: true),
        Text('${it.str('inspection_code')} · v${it.integer('version_no')}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.cyan)),
      ]),
      const SizedBox(height: 2),
      Text('Cabinet ${it.str('cabinet_id')} · ${ago(it.time('created_at'))}', style: const TextStyle(fontSize: 11.5, color: EE.textDim)),
      if (it.integer('review_count') > 0) Text('${it.integer('review_count')} review decision(s)', style: const TextStyle(fontSize: 11.5, color: EE.textMuted)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          onPressed: () => showFindingDrawer(context, it.str('finding_id'), onReviewed: widget.onReviewed),
          icon: const Icon(Icons.rate_review_outlined, size: 16),
          label: const Text('Review'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          onPressed: () => context.go(workspaceLink(it.str('inspection_id'), version: it.integer('version_no'), finding: it.str('finding_id'))),
          icon: const Icon(Icons.view_quilt_outlined, size: 16),
          label: const Text('Workspace'),
        ),
      ]),
    ]);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: EE.fast,
        decoration: BoxDecoration(
          color: _hover ? EE.surfaceHi : EE.surface,
          borderRadius: BorderRadius.circular(EE.r2),
          border: Border.all(color: _hover ? tierColor(tier).withValues(alpha: 0.45) : EE.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 14, 14, 14),
            child: narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [ident, const SizedBox(height: 12), evidence, const SizedBox(height: 12), source])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 190, child: ident),
                    const SizedBox(width: 18),
                    Expanded(child: evidence),
                    const SizedBox(width: 18),
                    SizedBox(width: 250, child: source),
                  ]),
          ),
          Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 3, color: tierColor(tier))),
        ]),
      ),
    );
  }
}
