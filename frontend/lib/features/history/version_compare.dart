import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';

typedef CompareKey = ({String inspectionId, int from, int to});

final compareProvider = FutureProvider.family<Json, CompareKey>((ref, k) => ref.watch(apiProvider).compare(k.inspectionId, from: k.from, to: k.to));

const categoryOrder = [
  'resolved', 'persistent', 'unconfirmed', 'new_discrepancy', 'clarified_fail', 'still_uncertain', 'regressed_to_uncertain',
  'clarified_pass', 'waived', 'new_check', 'not_rechecked', 'unchanged_pass',
];

Color categoryColor(String c) => switch (c) {
      'resolved' || 'clarified_pass' => EE.pass,
      'persistent' || 'new_discrepancy' || 'clarified_fail' => EE.fail,
      'unconfirmed' || 'still_uncertain' || 'regressed_to_uncertain' => EE.uncertain,
      'unchanged_pass' => EE.pass.withValues(alpha: 0.55),
      'waived' => EE.waived,
      'new_check' => EE.ice,
      _ => EE.textDim,
    };

/// Version-to-version comparison by stable finding keys.
class VersionComparePanel extends ConsumerStatefulWidget {
  const VersionComparePanel({super.key, required this.inspection});
  final Inspection inspection;
  @override
  ConsumerState<VersionComparePanel> createState() => _VersionComparePanelState();
}

class _VersionComparePanelState extends ConsumerState<VersionComparePanel> {
  int? _from;
  int? _to;
  String? _category;
  bool _hideUnchanged = true;

  @override
  Widget build(BuildContext context) {
    final done = widget.inspection.versions.where((v) => v.status == 'completed').map((v) => v.no).toList()..sort();
    if (done.length < 2) {
      return Panel(
        eyebrow: 'Reinspection loop',
        title: 'Version comparison',
        child: EmptyState(
          title: 'Comparison needs two completed versions',
          message: done.isEmpty
              ? 'No version of this inspection has completed yet.'
              : 'Only v${done.first} has completed. Create a reinspection after corrections to compare outcomes — the current version will be preserved.',
          icon: Icons.compare_arrows_rounded,
        ),
      );
    }
    final to = _to != null && done.contains(_to) ? _to! : done.last;
    final fromOptions = done.where((n) => n < to).toList();
    final from = _from != null && fromOptions.contains(_from) ? _from! : fromOptions.last;
    final key = (inspectionId: widget.inspection.id, from: from, to: to);
    final data = ref.watch(compareProvider(key));
    return Panel(
      eyebrow: 'Reinspection loop',
      title: 'Version comparison',
      subtitle: 'A discrepancy counts as resolved only when the newer run verified it as PASS. Earlier versions are preserved unchanged.',
      actions: [
        _VersionDrop(label: 'from', value: from, options: fromOptions, onChanged: (v) => setState(() => _from = v)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.arrow_forward_rounded, size: 16, color: EE.textDim)),
        _VersionDrop(label: 'to', value: to, options: done.where((n) => n > done.first).toList(), onChanged: (v) => setState(() => _to = v)),
      ],
      child: AsyncView<Json>(
        data,
        onRetry: () => ref.invalidate(compareProvider(key)),
        loadingLabel: 'Comparing versions',
        data: (c) => _body(c),
      ),
    );
  }

  Widget _body(Json c) {
    final counts = c.obj('summary').obj('counts').map((k, v) => MapEntry(k, (v as num).toInt()));
    final cats = c.obj('categories');
    var items = c.objs('items');
    final total = items.length;
    if (_category != null) {
      items = items.where((i) => i.str('category') == _category).toList();
    } else if (_hideUnchanged) {
      items = items.where((i) => i.str('category') != 'unchanged_pass').toList();
    }
    final ordered = categoryOrder.where(counts.containsKey).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in ordered)
          _CategoryTile(
            name: k,
            count: counts[k]!,
            description: cats.str(k),
            selected: _category == k,
            onTap: () => setState(() => _category = _category == k ? null : k),
          ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Text(_category == null ? '${items.length} of $total items' : '${items.length} × ${titleCase(_category!)}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted)),
        const Spacer(),
        if (_category == null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Hide unchanged passes', style: TextStyle(fontSize: 12, color: EE.textMuted)),
            Switch(value: _hideUnchanged, onChanged: (v) => setState(() => _hideUnchanged = v)),
          ])
        else
          TextButton(onPressed: () => setState(() => _category = null), child: const Text('Show all categories')),
      ]),
      const SizedBox(height: 6),
      _CompareTable(items: items, inspectionId: widget.inspection.id, fromNo: c.integer('from_version'), toNo: c.integer('to_version')),
    ]);
  }
}

class _VersionDrop extends StatelessWidget {
  const _VersionDrop({required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(border: Border.all(color: EE.lineHi), borderRadius: BorderRadius.circular(EE.r1)),
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          underline: const SizedBox(),
          dropdownColor: EE.surfaceHi,
          style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5, color: EE.text),
          items: [for (final o in options) DropdownMenuItem(value: o, child: Text('$label v$o'))],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.name, required this.count, required this.description, required this.selected, required this.onTap});
  final String name;
  final int count;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = categoryColor(name);
    return Tooltip(
      message: description,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(EE.r2),
        child: AnimatedContainer(
          duration: EE.fast,
          width: 150,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.14) : EE.bg1,
            borderRadius: BorderRadius.circular(EE.r2),
            border: Border.all(color: selected ? c.withValues(alpha: 0.7) : EE.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$count', style: TextStyle(fontFamily: EE.fontDisplay, fontSize: 22, fontWeight: FontWeight.w600, color: c, height: 1)),
            const SizedBox(height: 4),
            Text(titleCase(name), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: EE.textMuted)),
          ]),
        ),
      ),
    );
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.items, required this.inspectionId, required this.fromNo, required this.toNo});
  final List<Json> items;
  final String inspectionId;
  final int fromNo;
  final int toNo;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Padding(padding: EdgeInsets.all(18), child: Text('No items in this selection.', style: TextStyle(color: EE.textMuted, fontSize: 12.5)));
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 760;
      return Column(children: [
        if (!narrow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: EE.line))),
            child: Row(children: [
              const Expanded(flex: 3, child: _H('Check · subject')),
              const Expanded(flex: 2, child: _H('Expected')),
              Expanded(flex: 3, child: _H('v$fromNo (after review)')),
              Expanded(flex: 3, child: _H('v$toNo')),
              const Expanded(flex: 2, child: _H('Outcome')),
            ]),
          ),
        for (final it in items) narrow ? _narrowRow(context, it) : _row(context, it),
      ]);
    });
  }

  Widget _side(Json? side, {required bool from}) {
    if (side == null) return const Text('not checked', style: TextStyle(fontSize: 12, color: EE.textDim, fontStyle: FontStyle.italic));
    final verdict = from ? side.str('effective_verdict') : side.str('verdict');
    final machine = side.strN('machine_verdict');
    return Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      VerdictBadge(verdict, dense: true, reviewed: from && machine != null && machine != verdict),
      if (side.strN('observed') != null) MonoValue(side.str('observed'), size: 11.5, color: EE.textMuted),
    ]);
  }

  Widget _row(BuildContext context, Json it) {
    final cat = it.str('category');
    final target = it.objN('to') ?? it.objN('from');
    final version = it.objN('to') != null ? toNo : fromNo;
    return InkWell(
      onTap: target == null ? null : () => context.go(workspaceLink(inspectionId, version: version, finding: target.str('finding_id'))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: EE.line))),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(checkLabels[it.str('check_type')] ?? titleCase(it.str('check_type')), style: const TextStyle(fontSize: 11, color: EE.textDim)),
              Text('${it.str('subject')}${it.strN('zone_code') != null ? '  ·  ${it.str('zone_code')}' : ''}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          Expanded(flex: 2, child: MonoValue(it.strN('expected') ?? '—', size: 11.5)),
          Expanded(flex: 3, child: _side(it.objN('from'), from: true)),
          Expanded(flex: 3, child: _side(it.objN('to'), from: false)),
          Expanded(flex: 2, child: Tag(titleCase(cat), color: categoryColor(cat), filled: true)),
        ]),
      ),
    );
  }

  Widget _narrowRow(BuildContext context, Json it) {
    final cat = it.str('category');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: EE.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${it.str('subject')} · ${checkLabels[it.str('check_type')] ?? it.str('check_type')}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          Tag(titleCase(cat), color: categoryColor(cat), filled: true),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Text('v$fromNo ', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim)),
          Flexible(child: _side(it.objN('from'), from: true)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text('v$toNo ', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim)),
          Flexible(child: _side(it.objN('to'), from: false)),
        ]),
      ]),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Text(t.toUpperCase(), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10, letterSpacing: 1.1, color: EE.textDim));
}
