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
import 'evidence_detail.dart';
import 'evidence_kinds.dart';

typedef _EvidenceQuery = ({String? inspectionId, String kinds, int page});

const _pageSize = 48;

final _evidenceProvider = FutureProvider.family<Page<Evidence>, _EvidenceQuery>((ref, q) {
  return ref.watch(apiProvider).evidence(inspectionId: q.inspectionId, kind: q.kinds.isEmpty ? null : q.kinds, page: q.page, pageSize: _pageSize);
});

class EvidencePage extends ConsumerStatefulWidget {
  const EvidencePage({super.key, this.inspectionId});
  final String? inspectionId;

  @override
  ConsumerState<EvidencePage> createState() => _EvidencePageState();
}

class _EvidencePageState extends ConsumerState<EvidencePage> {
  late String? _inspectionId = widget.inspectionId;
  final Set<String> _kinds = {};
  int _page = 1;

  @override
  void didUpdateWidget(covariant EvidencePage old) {
    super.didUpdateWidget(old);
    if (old.inspectionId != widget.inspectionId) {
      _inspectionId = widget.inspectionId;
      _page = 1;
    }
  }

  _EvidenceQuery get _query => (inspectionId: _inspectionId, kinds: (_kinds.toList()..sort()).join(','), page: _page);

  void _setInspection(String? id) {
    setState(() {
      _inspectionId = id;
      _page = 1;
    });
    context.go(id == null ? '/console/evidence' : '/console/evidence?i=$id');
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_evidenceProvider(_query));
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: PageHeader(
          eyebrow: 'Traceability',
          title: 'Evidence Explorer',
          description:
              'Every verdict traces back to stored pixels: original photographs, processing derivatives, detector and OCR overlays, the registered drawing and per-finding crops. '
              'Evidence that could not be produced is listed with the recorded reason instead of being hidden.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(_evidenceProvider(_query)),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(child: _filters()),
      const SliverToBoxAdapter(child: SizedBox(height: EE.s4)),
      if (data.hasValue)
        ..._grid(data.requireValue)
      else if (data.hasError)
        SliverToBoxAdapter(child: ErrorView(data.error!, onRetry: () => ref.invalidate(_evidenceProvider(_query))))
      else
        const SliverToBoxAdapter(child: LoadingView(label: 'Loading evidence')),
      const SliverToBoxAdapter(child: SizedBox(height: 40)),
    ]);
  }

  Widget _filters() {
    final inspections = ref.watch(recentInspectionsProvider);
    final items = inspections.value ?? const <Inspection>[];
    final known = _inspectionId == null || items.any((i) => i.id == _inspectionId);
    return Panel(
      padding: const EdgeInsets.fromLTRB(EE.s4, EE.s3, EE.s4, EE.s3),
      child: Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.filter_alt_outlined, size: 16, color: EE.textDim),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
            child: DropdownButton<String?>(
              value: known ? _inspectionId : null,
              isExpanded: true,
              isDense: true,
              dropdownColor: EE.surfaceHi,
              underline: const SizedBox(),
              hint: Text(_inspectionId ?? 'All inspections', style: const TextStyle(fontSize: 12.5)),
              style: const TextStyle(fontSize: 12.5, color: EE.text),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All inspections')),
                for (final i in items)
                  DropdownMenuItem<String?>(value: i.id, child: Text('${i.code} · ${i.title}${i.isDemo ? '  (demo)' : ''}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _setInspection,
            ),
          ),
        ]),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _KindChip(label: 'All kinds', selected: _kinds.isEmpty, onTap: () => setState(() {
                _kinds.clear();
                _page = 1;
              })),
          for (final k in evidenceKinds.keys)
            _KindChip(
              label: evidenceKindLabel(k),
              icon: evidenceKindIcon(k),
              color: evidenceKindColor(k),
              selected: _kinds.contains(k),
              onTap: () => setState(() {
                _kinds.contains(k) ? _kinds.remove(k) : _kinds.add(k);
                _page = 1;
              }),
            ),
        ]),
      ]),
    );
  }

  List<Widget> _grid(Page<Evidence> page) {
    if (page.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            title: _kinds.isEmpty && _inspectionId == null ? 'No evidence yet' : 'No evidence matches these filters',
            message: 'Evidence is produced when an inspection run completes. Run the sample inspection from the Overview or create a new inspection.',
            icon: Icons.photo_library_outlined,
          ),
        ),
      ];
    }
    final pages = (page.total / _pageSize).ceil().clamp(1, 100000);
    final missing = page.items.where((e) => e.url == null).length;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Text('${page.total} evidence asset${page.total == 1 ? '' : 's'}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.textMuted)),
            if (missing > 0) ...[
              const SizedBox(width: 12),
              Tag('$missing without image on this page', color: EE.uncertain, icon: Icons.report_gmailerrorred_rounded),
            ],
            const Spacer(),
            _Pager(page: _page, pages: pages, onPage: (p) => setState(() => _page = p)),
          ]),
        ),
      ),
      SliverLayoutBuilder(builder: (context, c) {
        final cols = (c.crossAxisExtent / 250).floor().clamp(1, 8);
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 304),
          delegate: SliverChildBuilderDelegate((context, i) => _EvidenceCard(evidence: page.items[i]), childCount: page.items.length),
        );
      }),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Align(alignment: Alignment.centerRight, child: _Pager(page: _page, pages: pages, onPage: (p) => setState(() => _page = p))),
        ),
      ),
    ];
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label, required this.selected, required this.onTap, this.icon, this.color = EE.cyan});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(EE.r1),
        onTap: onTap,
        child: AnimatedContainer(
          duration: EE.fast,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : EE.bg1,
            borderRadius: BorderRadius.circular(EE.r1),
            border: Border.all(color: selected ? color.withValues(alpha: 0.6) : EE.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 13, color: selected ? color : EE.textDim), const SizedBox(width: 5)],
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: selected ? EE.text : EE.textMuted)),
          ]),
        ),
      );
}

class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.pages, required this.onPage});
  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Previous page', onPressed: page > 1 ? () => onPage(page - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
        Text('Page $page / $pages', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.textMuted)),
        IconButton(tooltip: 'Next page', onPressed: page < pages ? () => onPage(page + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
      ]);
}

class _EvidenceCard extends ConsumerStatefulWidget {
  const _EvidenceCard({required this.evidence});
  final Evidence evidence;
  @override
  ConsumerState<_EvidenceCard> createState() => _EvidenceCardState();
}

class _EvidenceCardState extends ConsumerState<_EvidenceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.evidence;
    final api = ref.watch(apiProvider);
    final missing = e.url == null;
    final f = e.finding;
    final accent = missing ? EE.uncertain : evidenceKindColor(e.kind);
    return MouseRegion(
      cursor: missing ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: missing ? null : () => showEvidenceDetail(context, e),
        child: AnimatedContainer(
          duration: EE.fast,
          transform: Matrix4.translationValues(0, _hover && !missing ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: _hover ? EE.surfaceHi : EE.surface,
            borderRadius: BorderRadius.circular(EE.r2),
            border: Border.all(color: _hover ? accent.withValues(alpha: 0.6) : (missing ? EE.uncertain.withValues(alpha: 0.4) : EE.line)),
            boxShadow: _hover ? [BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 8))] : const [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 150,
              child: Stack(fit: StackFit.expand, children: [
                if (missing)
                  Container(
                    color: EE.bg1,
                    padding: const EdgeInsets.all(12),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.hide_image_outlined, color: EE.uncertain, size: 26),
                      const SizedBox(height: 8),
                      const Text('MISSING EVIDENCE', style: TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, letterSpacing: 1.4, color: EE.uncertain, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(e.error ?? 'No file was stored for this record.',
                          textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: EE.textMuted)),
                    ]),
                  )
                else
                  Container(
                    color: EE.bg0,
                    child: Image.network(
                      api.url(e.thumbUrl ?? e.url),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, err, _) => const Center(child: Icon(Icons.broken_image_outlined, color: EE.textDim)),
                    ),
                  ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: EE.bg0.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: accent.withValues(alpha: 0.5))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(evidenceKindIcon(e.kind), size: 12, color: accent),
                      const SizedBox(width: 4),
                      Text(evidenceKindLabel(e.kind), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: accent)),
                    ]),
                  ),
                ),
                if (e.isDemo) const Positioned(right: 8, top: 8, child: DemoTag(compact: true)),
                if (f != null) Positioned(right: 8, bottom: 8, child: VerdictBadge(f.str('verdict'), dense: true)),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(e.id, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.textDim)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text('${e.inspectionCode ?? '—'} · v${e.versionNo ?? '?'}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.cyan)),
                    const Spacer(),
                    Text(ago(e.createdAt), style: const TextStyle(fontSize: 10.5, color: EE.textDim)),
                  ]),
                  const SizedBox(height: 4),
                  if (f != null)
                    Text('#${f.integer('seq')} ${checkLabels[f.str('check_type')] ?? f.str('check_type')} · ${f.str('subject')}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: EE.textMuted))
                  else
                    const Text('Inspection-level evidence', style: TextStyle(fontSize: 11.5, color: EE.textMuted)),
                  const Spacer(),
                  Text('${e.operation}${e.algorithm == null ? '' : ' · ${e.algorithm}'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.textDim)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
