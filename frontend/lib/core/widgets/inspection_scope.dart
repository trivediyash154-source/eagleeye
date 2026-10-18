import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'badges.dart';
import 'panel.dart';
import 'states.dart';

/// Resolves (inspection, version) for inspection-scoped screens. When no inspection is
/// selected it shows a picker; otherwise it renders [builder] with a scope bar on top.
class InspectionScope extends ConsumerWidget {
  const InspectionScope({
    super.key,
    required this.inspectionId,
    required this.versionNo,
    required this.onSelect,
    required this.builder,
    this.pickerTitle = 'Select an inspection',
    this.pickerMessage = 'Choose a processed inspection to open in this view.',
    this.requireCompleted = true,
    this.showBar = true,
  });

  final String? inspectionId;
  final int? versionNo;
  final void Function(String inspectionId, int? versionNo) onSelect;
  final Widget Function(BuildContext context, Inspection inspection, Version version) builder;
  final String pickerTitle;
  final String pickerMessage;
  final bool requireCompleted;
  final bool showBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (inspectionId == null || inspectionId!.isEmpty) {
      return InspectionPicker(title: pickerTitle, message: pickerMessage, onPick: (i, v) => onSelect(i.id, v.no), requireCompleted: requireCompleted);
    }
    final insp = ref.watch(inspectionProvider(inspectionId!));
    return AsyncView<Inspection>(
      insp,
      onRetry: () => ref.invalidate(inspectionProvider(inspectionId!)),
      data: (i) {
        final versions = i.versions;
        Version? v = versionNo == null ? null : versions.where((x) => x.no == versionNo).firstOrNull;
        v ??= versions.where((x) => x.status == 'completed').lastOrNull ?? (versions.isEmpty ? null : versions.last);
        if (v == null) return const EmptyState(title: 'This inspection has no versions');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (showBar) ...[ScopeBar(inspection: i, version: v, onSelect: onSelect), const SizedBox(height: EE.s4)],
          Expanded(child: builder(context, i, v)),
        ]);
      },
    );
  }
}

class ScopeBar extends StatelessWidget {
  const ScopeBar({super.key, required this.inspection, required this.version, required this.onSelect});
  final Inspection inspection;
  final Version version;
  final void Function(String inspectionId, int? versionNo) onSelect;

  @override
  Widget build(BuildContext context) {
    final s = version.summary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: EE.surface, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line)),
      child: Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(inspection.code, style: const TextStyle(fontFamily: EE.fontMono, fontWeight: FontWeight.w600, color: EE.cyan, fontSize: 13)),
        Text(inspection.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        Text('Cabinet ${inspection.cabinetId}', style: const TextStyle(color: EE.textMuted, fontSize: 12.5)),
        if (inspection.isDemo) const DemoTag(compact: true),
        _VersionMenu(inspection: inspection, version: version, onSelect: onSelect),
        StatePill(version.status),
        if (version.status == 'completed')
          Row(mainAxisSize: MainAxisSize.min, children: [
            _count(s.pass, 'PASS'),
            _count(s.fail, 'FAIL'),
            _count(s.uncertain, 'UNCERTAIN'),
          ]),
        TextButton.icon(onPressed: () => onSelect('', null), icon: const Icon(Icons.swap_horiz_rounded, size: 16), label: const Text('Change')),
      ]),
    );
  }

  Widget _count(int n, String v) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: EE.verdict(v), shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text('$n', style: TextStyle(fontFamily: EE.fontMono, fontSize: 12.5, color: EE.verdict(v), fontWeight: FontWeight.w600)),
        ]),
      );
}

class _VersionMenu extends StatelessWidget {
  const _VersionMenu({required this.inspection, required this.version, required this.onSelect});
  final Inspection inspection;
  final Version version;
  final void Function(String, int?) onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Switch version',
      color: EE.surfaceHi,
      onSelected: (n) => onSelect(inspection.id, n),
      itemBuilder: (_) => [
        for (final v in inspection.versions)
          PopupMenuItem(
            value: v.no,
            child: Row(children: [
              Text('v${v.no}', style: const TextStyle(fontFamily: EE.fontMono, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Expanded(child: Text(v.label, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 10),
              StatePill(v.status),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(border: Border.all(color: EE.lineHi), borderRadius: BorderRadius.circular(EE.r1)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('v${version.no} · ${version.label}', style: const TextStyle(fontSize: 12.5)),
          const Icon(Icons.expand_more_rounded, size: 16),
        ]),
      ),
    );
  }
}

class InspectionPicker extends ConsumerWidget {
  const InspectionPicker({super.key, required this.onPick, this.title = 'Select an inspection', this.message, this.requireCompleted = true});
  final void Function(Inspection, Version) onPick;
  final String title;
  final String? message;
  final bool requireCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(recentInspectionsProvider);
    return AsyncView<List<Inspection>>(
      list,
      onRetry: () => ref.invalidate(recentInspectionsProvider),
      data: (items) {
        final usable = items.where((i) => !requireCompleted || i.versions.isEmpty || i.latest?.status == 'completed' || (i.latest?.findingCount ?? 0) > 0).toList();
        if (usable.isEmpty) {
          return EmptyState(
            title: 'No processed inspections yet',
            message: 'Create an inspection or run the sample inspection from the Overview to populate this view.',
            icon: Icons.inventory_2_outlined,
          );
        }
        return SingleChildScrollView(
          child: Panel(
            eyebrow: 'Inspection context',
            title: title,
            subtitle: message,
            child: Column(children: [
              for (final i in usable)
                _PickRow(
                  inspection: i,
                  onTap: () {
                    final v = i.latest;
                    if (v != null) onPick(i, v);
                  },
                ),
            ]),
          ),
        );
      },
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.inspection, required this.onTap});
  final Inspection inspection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = inspection.latest;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(EE.r1),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          SizedBox(width: 92, child: Text(inspection.code, style: const TextStyle(fontFamily: EE.fontMono, color: EE.cyan, fontSize: 12.5))),
          Expanded(child: Text(inspection.title, overflow: TextOverflow.ellipsis)),
          if (inspection.isDemo) const Padding(padding: EdgeInsets.only(right: 10), child: DemoTag(compact: true)),
          SizedBox(width: 90, child: Text(inspection.cabinetId, style: const TextStyle(color: EE.textMuted, fontSize: 12.5))),
          SizedBox(width: 60, child: Text(v == null ? '—' : 'v${v.no}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12))),
          SizedBox(width: 110, child: v == null ? const SizedBox() : StatePill(v.status)),
          SizedBox(width: 90, child: Text(ago(inspection.createdAt), style: const TextStyle(color: EE.textDim, fontSize: 12))),
          const Icon(Icons.chevron_right_rounded, color: EE.textDim),
        ]),
      ),
    );
  }
}
