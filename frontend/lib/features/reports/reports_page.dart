import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/download.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';

final _reportsProvider = FutureProvider.family<List<Json>, String?>((ref, inspectionId) => ref.watch(apiProvider).reports(inspectionId: inspectionId));

const _formats = <(String, String, IconData, String)>[
  ('pdf', 'PDF report', Icons.picture_as_pdf_outlined, 'Branded, paginated report with annotated photo, findings table, evidence crops for FAIL/UNCERTAIN items, review decisions and limitations.'),
  ('json', 'JSON export', Icons.data_object_rounded, 'Complete structured record: inputs with hashes, expected records, detections, OCR observations, findings, reviews and evidence references.'),
  ('csv', 'CSV findings', Icons.table_rows_outlined, 'One row per finding with expected/observed values, machine and effective verdicts, confidences and review status.'),
  ('xlsx', 'Excel workbook', Icons.grid_on_rounded, 'Findings sheet with verdict colouring plus a summary sheet for QA hand-over.'),
];

Color _formatColor(String f) => switch (f) { 'pdf' => EE.fail, 'json' => EE.violet, 'csv' => EE.pass, 'xlsx' => EE.pass, _ => EE.textMuted };

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key, this.inspectionId});
  final String? inspectionId;

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  late String? _filter = widget.inspectionId;

  @override
  void didUpdateWidget(covariant ReportsPage old) {
    super.didUpdateWidget(old);
    if (old.inspectionId != widget.inspectionId) _filter = widget.inspectionId;
  }

  void _refresh() {
    ref.invalidate(_reportsProvider(_filter));
    ref.invalidate(_reportsProvider(null));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      PageHeader(
        eyebrow: 'Hand-over',
        title: 'Reports & Exports',
        description: 'Generate a professional PDF report or structured exports for any completed inspection version. Every file is stored with a SHA-256 hash for integrity verification.',
        actions: [OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Refresh'))],
      ),
      ResponsiveRow(flex: const [3, 2], breakpoint: 1050, children: [
        _Generator(
          initialInspectionId: widget.inspectionId,
          onGenerated: (inspectionId) {
            ref.invalidate(_reportsProvider(inspectionId));
            ref.invalidate(_reportsProvider(null));
          },
        ),
        const _Contents(),
      ]),
      const SizedBox(height: EE.s4),
      _ReportList(
        filter: _filter,
        onFilter: (id) {
          setState(() => _filter = id);
          context.go(id == null ? '/console/reports' : '/console/reports?i=$id');
        },
      ),
    ]);
  }
}

class _Generator extends ConsumerStatefulWidget {
  const _Generator({required this.initialInspectionId, required this.onGenerated});
  final String? initialInspectionId;
  final ValueChanged<String> onGenerated;

  @override
  ConsumerState<_Generator> createState() => _GeneratorState();
}

class _GeneratorState extends ConsumerState<_Generator> {
  late String? _inspectionId = widget.initialInspectionId;
  int? _versionNo;
  String? _busy;
  Json? _last;
  String? _error;

  Future<void> _generate(Version v, String format) async {
    final api = ref.read(apiProvider);
    setState(() {
      _busy = format;
      _error = null;
    });
    try {
      final r = await api.createReport(v.id, format);
      if (!mounted) return;
      setState(() {
        _busy = null;
        _last = r;
      });
      widget.onGenerated(v.inspectionId);
      showSnack(context, '${r.str('filename')} generated (${fmtBytes(r.integer('size_bytes'))})');
      await openUrl(api.url(r.str('download_url')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(recentInspectionsProvider);
    final items = (list.value ?? const <Inspection>[]).where((i) => i.versions.isNotEmpty || i.latest != null).toList();
    final inspection = _inspectionId == null ? null : ref.watch(inspectionProvider(_inspectionId!));
    return Panel(
      eyebrow: 'Generate',
      title: 'Create a report or export',
      subtitle: 'Reports can be generated for completed versions only.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (list.hasError) ErrorView(list.error!, compact: true, onRetry: () => ref.invalidate(recentInspectionsProvider)),
        Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 420),
            child: DropdownButtonFormField<String>(
              initialValue: items.any((i) => i.id == _inspectionId) ? _inspectionId : null,
              isExpanded: true,
              dropdownColor: EE.surfaceHi,
              decoration: const InputDecoration(labelText: 'Inspection'),
              items: [
                for (final i in items)
                  DropdownMenuItem(value: i.id, child: Text('${i.code} · ${i.title}${i.isDemo ? '  (demo)' : ''}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (id) => setState(() {
                _inspectionId = id;
                _versionNo = null;
                _last = null;
              }),
            ),
          ),
          if (inspection != null)
            inspection.when(
              loading: () => const SizedBox(width: 100, child: LinearProgressIndicator(minHeight: 2)),
              error: (e, _) => Text('$e', style: const TextStyle(color: EE.fail, fontSize: 12)),
              data: (i) {
                final done = i.versions.where((v) => v.status == 'completed').toList();
                if (done.isEmpty) return const Text('No completed version yet', style: TextStyle(color: EE.uncertain, fontSize: 12.5));
                final sel = done.where((v) => v.no == _versionNo).firstOrNull ?? done.last;
                return ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 200, maxWidth: 300),
                  child: DropdownButtonFormField<int>(
                    initialValue: sel.no,
                    isExpanded: true,
                    dropdownColor: EE.surfaceHi,
                    decoration: const InputDecoration(labelText: 'Version'),
                    items: [for (final v in done) DropdownMenuItem(value: v.no, child: Text('v${v.no} · ${v.label}', overflow: TextOverflow.ellipsis))],
                    onChanged: (n) => setState(() => _versionNo = n),
                  ),
                );
              },
            ),
        ]),
        const SizedBox(height: 16),
        _formatButtons(inspection?.value),
        if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: EE.fail, fontSize: 12.5))],
        if (_last != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: EE.pass.withValues(alpha: 0.07), border: Border.all(color: EE.pass.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(EE.r2)),
            child: Row(children: [
              const Icon(Icons.check_circle_outline_rounded, color: EE.pass, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_last!.str('filename'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text('${fmtBytes(_last!.integer('size_bytes'))}${_last!.intN('pages') != null ? ' · ${_last!.integer('pages')} pages' : ''} · sha256 ${_last!.str('sha256').substring(0, 16)}…',
                      style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textMuted)),
                ]),
              ),
              TextButton.icon(
                onPressed: () => openUrl(ref.read(apiProvider).url(_last!.str('download_url'))),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download again'),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _formatButtons(Inspection? i) {
    Version? v;
    if (i != null) {
      final done = i.versions.where((x) => x.status == 'completed').toList();
      v = done.where((x) => x.no == _versionNo).firstOrNull ?? done.lastOrNull;
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 640 ? 4 : (c.maxWidth > 380 ? 2 : 1);
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (fmt, label, icon, _) in _formats)
          SizedBox(
            width: w,
            child: _FormatButton(
              label: label,
              icon: icon,
              color: _formatColor(fmt),
              busy: _busy == fmt,
              enabled: v != null && _busy == null,
              onTap: v == null ? null : () => _generate(v!, fmt),
            ),
          ),
      ]);
    });
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({required this.label, required this.icon, required this.color, required this.busy, required this.enabled, this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final bool busy;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(EE.r2),
        child: AnimatedContainer(
          duration: EE.fast,
          height: 74,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: enabled ? EE.bg1 : EE.bg1.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(EE.r2),
            border: Border.all(color: enabled ? color.withValues(alpha: 0.45) : EE.line),
          ),
          child: Row(children: [
            busy ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: color)) : Icon(icon, color: enabled ? color : EE.textDim, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: enabled ? EE.text : EE.textDim)),
                Text(busy ? 'Generating…' : 'Generate & download', style: const TextStyle(fontSize: 11, color: EE.textDim)),
              ]),
            ),
          ]),
        ),
      );
}

class _Contents extends StatelessWidget {
  const _Contents();

  @override
  Widget build(BuildContext context) => Panel(
        eyebrow: 'What you get',
        title: 'Report contents',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (fmt, label, icon, desc) in _formats)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 16, color: _formatColor(fmt)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(desc, style: const TextStyle(fontSize: 11.5, color: EE.textMuted, height: 1.4)),
                  ]),
                ),
              ]),
            ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: EE.uncertain.withValues(alpha: 0.07), border: Border.all(color: EE.uncertain.withValues(alpha: 0.35)), borderRadius: BorderRadius.circular(EE.r2)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.gavel_rounded, size: 16, color: EE.uncertain),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Reports support inspection and human review. They are not certificates of compliance: UNCERTAIN items are listed as open, '
                  'and generating a report never marks a cabinet as approved.',
                  style: TextStyle(fontSize: 11.5, color: EE.textMuted, height: 1.45),
                ),
              ),
            ]),
          ),
        ]),
      );
}

class _ReportList extends ConsumerWidget {
  const _ReportList({required this.filter, required this.onFilter});
  final String? filter;
  final ValueChanged<String?> onFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_reportsProvider(filter));
    final inspections = ref.watch(recentInspectionsProvider).value ?? const <Inspection>[];
    return Panel(
      eyebrow: 'Archive',
      title: 'Generated reports and exports',
      actions: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: DropdownButton<String?>(
            value: inspections.any((i) => i.id == filter) ? filter : null,
            isDense: true,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: EE.surfaceHi,
            style: const TextStyle(fontSize: 12.5, color: EE.text),
            hint: Text(filter ?? 'All inspections', style: const TextStyle(fontSize: 12.5)),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All inspections')),
              for (final i in inspections) DropdownMenuItem<String?>(value: i.id, child: Text('${i.code} · ${i.cabinetId}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onFilter,
          ),
        ),
      ],
      child: AsyncView<List<Json>>(
        data,
        onRetry: () => ref.invalidate(_reportsProvider(filter)),
        data: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No reports yet',
              message: 'A PDF report is generated automatically at the end of every inspection run; exports appear here when generated.',
              icon: Icons.description_outlined,
            );
          }
          return LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 820;
            return Column(children: [
              if (!narrow)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: EE.line))),
                  child: const Row(children: [
                    SizedBox(width: 70, child: _H('Format')),
                    Expanded(flex: 4, child: _H('File')),
                    Expanded(flex: 2, child: _H('Inspection')),
                    SizedBox(width: 90, child: _H('Size')),
                    Expanded(flex: 2, child: _H('SHA-256')),
                    SizedBox(width: 130, child: _H('Created')),
                    SizedBox(width: 44),
                  ]),
                ),
              for (final r in rows) _ReportRow(report: r, narrow: narrow),
            ]);
          });
        },
      ),
    );
  }
}

class _ReportRow extends ConsumerWidget {
  const _ReportRow({required this.report, required this.narrow});
  final Json report;
  final bool narrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = report;
    final api = ref.watch(apiProvider);
    final fmt = r.str('format');
    final c = _formatColor(fmt);
    final sha = r.str('sha256');
    final download = IconButton(
      tooltip: 'Download',
      onPressed: () => openUrl(api.url(r.str('download_url'))),
      icon: const Icon(Icons.download_rounded, size: 18, color: EE.cyan),
    );
    final shaText = Tooltip(
      message: 'SHA-256 $sha (click to copy)',
      child: InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: sha));
          showSnack(context, 'SHA-256 copied');
        },
        child: Text(sha.length > 16 ? '${sha.substring(0, 16)}…' : sha, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textMuted)),
      ),
    );
    final inspection = Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text('${r.str('inspection_code')} · v${r.integer('version_no')}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.cyan))),
      if (r.boolean('is_demo')) const Padding(padding: EdgeInsets.only(left: 6), child: DemoTag(compact: true)),
    ]);
    final formatTag = Tag(fmt.toUpperCase(), color: c, mono: true, filled: true);
    if (narrow) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: EE.line))),
        child: Row(children: [
          formatTag,
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.str('filename'), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              inspection,
              const SizedBox(height: 2),
              Text('${fmtBytes(r.integer('size_bytes'))} · ${fmtTime(r.time('created_at'))}', style: const TextStyle(fontSize: 11, color: EE.textDim)),
              shaText,
            ]),
          ),
          download,
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: EE.line))),
      child: Row(children: [
        SizedBox(width: 70, child: Align(alignment: Alignment.centerLeft, child: formatTag)),
        Expanded(
          flex: 4,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.str('filename'), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            if (r.intN('pages') != null) Text('${r.integer('pages')} pages', style: const TextStyle(fontSize: 11, color: EE.textDim)),
          ]),
        ),
        Expanded(flex: 2, child: inspection),
        SizedBox(width: 90, child: Text(fmtBytes(r.integer('size_bytes')), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5))),
        Expanded(flex: 2, child: shaText),
        SizedBox(width: 130, child: Text(fmtTime(r.time('created_at')), style: const TextStyle(fontSize: 11.5, color: EE.textMuted))),
        SizedBox(width: 44, child: download),
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
