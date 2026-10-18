import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/file_drop.dart';
import 'step_common.dart';
import 'wizard_controller.dart';

const _listExts = ['xlsx', 'xls', 'csv'];
const _listMax = 10 * 1024 * 1024;

class ListStep extends StatefulWidget {
  const ListStep({super.key, required this.controller});
  final WizardController controller;
  @override
  State<ListStep> createState() => _ListStepState();
}

class _ListStepState extends State<ListStep> {
  String? _error;
  bool _validating = false;
  bool _saving = false;
  bool _removing = false;

  WizardController get c => widget.controller;

  Future<void> _upload(PickedFile f) async {
    setState(() => _error = null);
    await c.upload('expected_list', f);
  }

  Future<void> _replace() async {
    final f = await pickFile(_listExts);
    if (f == null) return;
    final err = validatePicked(f, _listExts, _listMax);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    await _upload(f);
  }

  Future<void> _remove() async {
    setState(() => _removing = true);
    try {
      await c.removeAsset('expected_list');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Future<void> _validate() async {
    setState(() => _validating = true);
    await c.validateMapping();
    if (mounted) setState(() => _validating = false);
  }

  Future<void> _saveAndContinue() async {
    if (!c.sheets.any((s) => s.include && s.derivedRole != 'unknown')) {
      setState(() => _error = 'Include at least one sheet with a Component ID, Ferrule or Terminal column mapped.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (c.sheetsDirty || c.version?.config['sheets'] == null) await c.saveMapping();
      c.next();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = c.asset('expected_list');
    final busy = c.uploadProgress.containsKey('expected_list');
    final err = _error ?? c.uploadError['expected_list'];
    return StepFrame(
      controller: c,
      description:
          'Upload the expected component list and/or wire list (XLSX, XLS or CSV). No fixed schema is assumed: headers are detected per sheet '
          'and mapped to inspection fields. Review the mapping, validate it against the file, then save.',
      primaryLabel: c.sheetsDirty ? 'Save mapping & continue' : 'Continue',
      primaryBusy: _saving,
      onPrimary: a != null && !busy ? _saveAndContinue : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (err != null) ...[InlineError(err), const SizedBox(height: 14)],
          if (a == null || busy)
            FileDropZone(
              extensions: _listExts,
              maxBytes: _listMax,
              title: 'Drop the expected component / wire list',
              icon: Icons.table_chart_outlined,
              busy: busy,
              progress: c.uploadProgress['expected_list'],
              enabled: c.editable,
              onFile: _upload,
              onRejected: (m) => setState(() => _error = m),
            )
          else ...[
            Row(
              children: [
                const Icon(Icons.table_chart_outlined, size: 16, color: EE.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.filename,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${c.sheets.length} sheet(s) · ${fmtBytes(a.sizeBytes)}',
                  style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted),
                ),
                const SizedBox(width: 8),
                IconButton(tooltip: 'Replace file', onPressed: c.editable ? _replace : null, icon: const Icon(Icons.swap_horiz_rounded, size: 18)),
                IconButton(
                  tooltip: 'Remove file',
                  onPressed: c.editable && !_removing ? _remove : null,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (c.sheets.isEmpty) const InlineError('The workbook contains no readable sheets.', color: EE.uncertain),
            for (final s in c.sheets) ...[_SheetCard(controller: c, sheet: s), const SizedBox(height: 12)],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _validating ? null : _validate,
                  icon: _validating
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.rule_rounded, size: 16),
                  label: const Text('Validate mapping'),
                ),
                if (c.sheetsDirty) const Tag('Unsaved mapping changes', color: EE.uncertain, icon: Icons.edit_note_rounded),
                if (!c.sheetsDirty && c.version?.config['sheets'] != null) const Tag('Mapping saved', color: EE.pass, icon: Icons.check_rounded),
              ],
            ),
            if (c.listPreviewError != null) ...[const SizedBox(height: 12), InlineError(c.listPreviewError!)],
            if (c.listPreview != null) ...[const SizedBox(height: 16), _PreviewResult(result: c.listPreview!)],
          ],
        ],
      ),
    );
  }
}

class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.controller, required this.sheet});
  final WizardController controller;
  final SheetCfg sheet;

  @override
  Widget build(BuildContext context) {
    final s = sheet;
    final fields = controller.fieldLabels;
    final role = s.derivedRole;
    final roleColor = switch (role) {
      'components' => EE.cyan,
      'wires' => EE.violet,
      _ => EE.textDim,
    };
    final dups = s.duplicateFields;
    final maxHeader = (s.detectedHeaderRow + 8).clamp(8, 15);
    return AnimatedOpacity(
      duration: EE.fast,
      opacity: s.include ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: EE.bg1,
          borderRadius: BorderRadius.circular(EE.r2),
          border: Border.all(color: s.include ? EE.lineHi : EE.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: s.include,
                      onChanged: controller.editable
                          ? (v) {
                              s.include = v;
                              controller.markSheetsDirty();
                            }
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
                Tag(role == 'unknown' ? 'not recognised' : '$role list', color: roleColor, filled: true),
                Text('${s.rowCount} data rows', style: const TextStyle(fontSize: 12, color: EE.textMuted)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Header row', style: TextStyle(fontSize: 12, color: EE.textMuted)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: s.headerRow,
                      isDense: true,
                      underline: const SizedBox(),
                      dropdownColor: EE.surfaceHi,
                      style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5, color: EE.text),
                      items: [
                        for (var i = 0; i <= maxHeader; i++)
                          DropdownMenuItem(value: i, child: Text('Row ${i + 1}${i == s.detectedHeaderRow ? '  (detected)' : ''}')),
                      ],
                      onChanged: controller.editable && !s.remapping ? (v) => v == null ? null : controller.changeHeaderRow(s, v) : null,
                    ),
                    if (s.remapping)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                  ],
                ),
              ],
            ),
            const Text('Row numbers count non-empty rows from the top of the sheet.', style: TextStyle(fontSize: 11, color: EE.textDim)),
            if (s.remapError != null) ...[const SizedBox(height: 10), InlineError(s.remapError!, color: EE.uncertain)],
            if (s.include && s.columns.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SubHeading('Column → field mapping'),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final col in s.columns)
                    Container(
                      width: 230,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                        color: EE.surface,
                        borderRadius: BorderRadius.circular(EE.r2),
                        border: Border.all(color: s.mapping[col] != null ? EE.cyan.withValues(alpha: 0.35) : EE.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  col,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted),
                                ),
                              ),
                              if ((s.scores[col] ?? 0) > 0 && s.mapping[col] != null)
                                Tooltip(
                                  message: 'Header similarity to the field synonym list',
                                  child: Text(
                                    'auto ${s.scores[col]}%',
                                    style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10, color: EE.textDim),
                                  ),
                                ),
                            ],
                          ),
                          DropdownButton<String?>(
                            value: fields.containsKey(s.mapping[col]) ? s.mapping[col] : null,
                            isExpanded: true,
                            isDense: true,
                            underline: const SizedBox(),
                            dropdownColor: EE.surfaceHi,
                            style: const TextStyle(fontSize: 12.5, color: EE.text),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('— ignore column —', style: TextStyle(color: EE.textDim)),
                              ),
                              for (final f in fields.entries)
                                DropdownMenuItem<String?>(
                                  value: f.key,
                                  child: Text(f.value, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: controller.editable
                                ? (v) {
                                    s.mapping[col] = v;
                                    controller.markSheetsDirty();
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (dups.isNotEmpty) ...[
                const SizedBox(height: 10),
                InlineError(
                  'Field(s) mapped more than once: ${dups.map((d) => fields[d] ?? d).join(', ')}. Only one column per field is used.',
                  color: EE.uncertain,
                ),
              ],
              if (role == 'unknown') ...[
                const SizedBox(height: 10),
                const InlineError(
                  'Map a Component ID column (component list) or a Ferrule / Terminal column (wire list); otherwise this sheet is ignored.',
                  color: EE.uncertain,
                ),
              ],
            ],
            if (s.include && s.previewMatchesHeader) ...[
              const SizedBox(height: 14),
              const SubHeading('Row preview'),
              _RowPreview(sheet: s, fields: fields),
            ] else if (s.include && s.columns.isNotEmpty && s.headerRow != s.detectedHeaderRow) ...[
              const SizedBox(height: 10),
              const Text(
                'Row preview is shown for the detected header row; use “Validate mapping” to see parsed records for this header row.',
                style: TextStyle(fontSize: 11.5, color: EE.textDim),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RowPreview extends StatelessWidget {
  const _RowPreview({required this.sheet, required this.fields});
  final SheetCfg sheet;
  final Map<String, String> fields;

  @override
  Widget build(BuildContext context) {
    final rows = sheet.preview.take(6).toList();
    const cellPad = EdgeInsets.symmetric(horizontal: 10, vertical: 7);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: const TableBorder(horizontalInside: BorderSide(color: EE.line)),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: EE.surfaceHi),
            children: [
              const Padding(
                padding: cellPad,
                child: Text(
                  '#',
                  style: TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim),
                ),
              ),
              for (final c in sheet.columns)
                Padding(
                  padding: cellPad,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      Text(
                        sheet.mapping[c] == null ? 'ignored' : (fields[sheet.mapping[c]] ?? sheet.mapping[c]!),
                        style: TextStyle(fontSize: 10.5, color: sheet.mapping[c] == null ? EE.textDim : EE.cyan),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          for (final r in rows)
            TableRow(
              children: [
                Padding(
                  padding: cellPad,
                  child: Text(
                    '${r.integer('row')}',
                    style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim),
                  ),
                ),
                for (final c in sheet.columns)
                  Padding(
                    padding: cellPad,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        r.obj('values')[c]?.toString() ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PreviewResult extends StatelessWidget {
  const _PreviewResult({required this.result});
  final Json result;

  @override
  Widget build(BuildContext context) {
    final counts = result.obj('counts');
    final warnings = result.objs('warnings');
    final comps = result.objs('components');
    final ids = result.objs('identifiers');
    final byCode = <String, int>{};
    for (final w in warnings) {
      byCode[w.str('code')] = (byCode[w.str('code')] ?? 0) + 1;
    }
    final total = counts.integer('components') + counts.integer('identifiers');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EE.surface,
        borderRadius: BorderRadius.circular(EE.r2),
        border: Border.all(color: total == 0 ? EE.fail.withValues(alpha: 0.5) : EE.lineHi),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SubHeading('Validation result (parsed by the backend)'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Metric('Components', '${counts.integer('components')}', color: EE.cyan),
              Metric('Wire / ferrule records', '${counts.integer('identifiers')}', color: EE.violet),
              Metric('Warnings', '${warnings.length}', color: warnings.isEmpty ? EE.pass : EE.uncertain),
            ],
          ),
          if (total == 0) ...[
            const SizedBox(height: 10),
            const InlineError('No records were parsed. Check the header row and that an ID / ferrule column is mapped.'),
          ],
          if (byCode.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final e in byCode.entries) Tag('${titleCase(e.key)} × ${e.value}', color: EE.uncertain)]),
            const SizedBox(height: 8),
            for (final w in warnings.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${w.str('sheet')}${w.intN('row') != null ? ' row ${w.intN('row')}' : ''}: ${w.str('message')}',
                  style: const TextStyle(fontSize: 12, color: EE.textMuted),
                ),
              ),
            if (warnings.length > 10) Text('… and ${warnings.length - 10} more', style: const TextStyle(fontSize: 11.5, color: EE.textDim)),
          ],
          if (comps.isNotEmpty) ...[
            const SizedBox(height: 14),
            const SubHeading('Expected components (first rows)'),
            _records(
              comps.take(8).toList(),
              const ['tag', 'component_type', 'expected_label', 'zone_code', 'quantity', 'source_row'],
              const ['Component', 'Type', 'Label', 'Zone', 'Qty', 'Row'],
            ),
          ],
          if (ids.isNotEmpty) ...[
            const SizedBox(height: 14),
            const SubHeading('Expected wires / ferrules (first rows)'),
            _records(
              ids.take(8).toList(),
              const ['terminal_ref', 'value', 'wire_color', 'component_tag', 'zone_code', 'source_row'],
              const ['Terminal', 'Ferrule', 'Colour', 'From', 'Zone', 'Row'],
            ),
          ],
        ],
      ),
    );
  }

  Widget _records(List<Json> rows, List<String> keys, List<String> labels) {
    const pad = EdgeInsets.symmetric(horizontal: 10, vertical: 6);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: const TableBorder(horizontalInside: BorderSide(color: EE.line)),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: EE.surfaceHi),
            children: [
              for (final l in labels)
                Padding(
                  padding: pad,
                  child: Text(l, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          for (final r in rows)
            TableRow(
              children: [
                for (final k in keys)
                  Padding(
                    padding: pad,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(
                        r[k]?.toString() ?? '—',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
