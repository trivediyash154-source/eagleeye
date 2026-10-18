import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/file_drop.dart';
import 'step_common.dart';
import 'wizard_controller.dart';

const _pdfExts = ['pdf'];
const _pdfMax = 50 * 1024 * 1024;

class DrawingStep extends StatefulWidget {
  const DrawingStep({super.key, required this.controller});
  final WizardController controller;
  @override
  State<DrawingStep> createState() => _DrawingStepState();
}

class _DrawingStepState extends State<DrawingStep> {
  String? _error;
  bool _savingPage = false;
  bool _removing = false;

  WizardController get c => widget.controller;

  Future<void> _upload(PickedFile f) async {
    setState(() => _error = null);
    await c.upload('drawing', f);
  }

  Future<void> _replace() async {
    final f = await pickFile(_pdfExts);
    if (f == null) return;
    final err = validatePicked(f, _pdfExts, _pdfMax);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    await _upload(f);
  }

  Future<void> _remove() async {
    setState(() => _removing = true);
    try {
      await c.removeAsset('drawing');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Future<void> _selectPage(int p) async {
    if (p == c.drawingPage) return;
    setState(() {
      _savingPage = true;
      _error = null;
    });
    try {
      await c.setDrawingPage(p);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _savingPage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = c.asset('drawing');
    final busy = c.uploadProgress.containsKey('drawing');
    final err = _error ?? c.uploadError['drawing'];
    return StepFrame(
      controller: c,
      description:
          'Upload the General Arrangement drawing (PDF) and choose the sheet that shows this cabinet. Vector PDFs give exact text and '
          'geometry; scanned (raster) pages are read by OCR and flagged as less reliable.',
      onPrimary: a != null && !busy ? c.next : null,
      secondary: a == null ? TextButton(onPressed: busy ? null : c.next, child: const Text('Continue without drawing')) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (err != null) ...[InlineError(err), const SizedBox(height: 14)],
          if (a == null) ...[
            const InlineError(
              'Without a GA drawing there are no zones and no photo-to-drawing registration: position-based checks (ferrules, zone correspondence, '
              'presence at expected position) will be reported UNCERTAIN.',
              color: EE.uncertain,
              icon: Icons.info_outline_rounded,
            ),
            const SizedBox(height: 14),
          ],
          if (a == null || busy)
            FileDropZone(
              extensions: _pdfExts,
              maxBytes: _pdfMax,
              title: 'Drop the GA drawing (PDF)',
              icon: Icons.architecture_rounded,
              busy: busy,
              progress: c.uploadProgress['drawing'],
              enabled: c.editable,
              onFile: _upload,
              onRejected: (m) => setState(() => _error = m),
            )
          else
            _DrawingAnalysis(
              controller: c,
              asset: a,
              onSelectPage: _selectPage,
              savingPage: _savingPage,
              onReplace: _replace,
              onRemove: _remove,
              removing: _removing,
            ),
        ],
      ),
    );
  }
}

class _DrawingAnalysis extends StatelessWidget {
  const _DrawingAnalysis({
    required this.controller,
    required this.asset,
    required this.onSelectPage,
    required this.savingPage,
    required this.onReplace,
    required this.onRemove,
    required this.removing,
  });
  final WizardController controller;
  final Asset asset;
  final ValueChanged<int> onSelectPage;
  final bool savingPage;
  final VoidCallback onReplace;
  final VoidCallback onRemove;
  final bool removing;

  Color _kindColor(String k) => switch (k) {
    'vector' => EE.pass,
    'mixed' => EE.ice,
    'raster' => EE.uncertain,
    _ => EE.fail,
  };

  @override
  Widget build(BuildContext context) {
    final an = asset.analysis;
    final pages = an.objs('pages');
    final warnings = an.objs('warnings');
    final meta = an.obj('metadata');
    final sel = controller.drawingPage.clamp(0, pages.isEmpty ? 0 : pages.length - 1);
    final page = pages.isEmpty ? <String, dynamic>{} : pages[sel];
    final api = controller.api;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.picture_as_pdf_outlined, size: 16, color: EE.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                asset.filename,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${an.integer('page_count')} page(s) · ${fmtBytes(asset.sizeBytes)}',
              style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted),
            ),
          ],
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            [for (final e in meta.entries) '${e.key}: ${e.value}'].join('  ·  '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: EE.textDim),
          ),
        ],
        const SizedBox(height: 14),
        SubHeading(
          'Select drawing page',
          trailing: savingPage ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : null,
        ),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: pages.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = pages[i];
              final active = i == sel;
              return InkWell(
                onTap: controller.editable && !savingPage ? () => onSelectPage(i) : null,
                borderRadius: BorderRadius.circular(EE.r2),
                child: AnimatedContainer(
                  duration: EE.fast,
                  width: 120,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: active ? EE.cyan.withValues(alpha: 0.08) : EE.bg1,
                    borderRadius: BorderRadius.circular(EE.r2),
                    border: Border.all(color: active ? EE.cyan : EE.line, width: active ? 1.4 : 1),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          color: Colors.white,
                          width: double.infinity,
                          child: Image.network(
                            api.pdfPreviewUrl(asset.id, i, zoom: 0.5),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, color: EE.textDim)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(
                            'P${i + 1}',
                            style: TextStyle(fontFamily: EE.fontMono, fontSize: 11, fontWeight: FontWeight.w600, color: active ? EE.cyan : EE.text),
                          ),
                          const Spacer(),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: _kindColor(p.str('kind')), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          Text(p.str('kind'), style: const TextStyle(fontSize: 10.5, color: EE.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, cons) {
            final preview = ClipRRect(
              borderRadius: BorderRadius.circular(EE.r2),
              child: Container(
                color: Colors.white,
                height: 360,
                width: double.infinity,
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6,
                  child: Image.network(
                    api.pdfPreviewUrl(asset.id, sel, zoom: 1.4),
                    key: ValueKey('pdf-$sel'),
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, prog) =>
                        prog == null ? child : const Center(child: SizedBox(width: 90, child: LinearProgressIndicator(minHeight: 2))),
                    errorBuilder: (_, e, _) => Center(
                      child: Text('Page render failed: $e', style: const TextStyle(color: EE.fail, fontSize: 12)),
                    ),
                  ),
                ),
              ),
            );
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SubHeading('Page ${sel + 1} analysis'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Metric('Content', page.str('kind', '—'), color: _kindColor(page.str('kind'))),
                    Metric('Text words', '${page.integer('words')}'),
                    Metric('Vector paths', '${page.integer('vector_paths')}'),
                    Metric('Images', '${page.integer('images')}'),
                    Metric('Size (pt)', '${page.dbl('width_pt')?.round() ?? '—'}×${page.dbl('height_pt')?.round() ?? '—'}'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      page.boolean('text_extractable') ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                      size: 16,
                      color: page.boolean('text_extractable') ? EE.pass : EE.uncertain,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        page.boolean('text_extractable')
                            ? 'Text layer present: identifiers will be extracted exactly with PyMuPDF.'
                            : 'No text layer: the page will be rendered at 300 DPI and read with OCR.',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 16, color: EE.pass),
                    SizedBox(width: 8),
                    Expanded(child: Text('Page render verified (preview generated by the backend).', style: TextStyle(fontSize: 12.5))),
                  ],
                ),
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final w in warnings) ...[
                    InlineError(w.str('message'), color: EE.uncertain, icon: Icons.warning_amber_rounded),
                    const SizedBox(height: 6),
                  ],
                ],
                const SizedBox(height: 10),
                const Text(
                  'Zones and component positions are extracted when the inspection runs; they can be corrected in Drawing Intelligence.',
                  style: TextStyle(fontSize: 11.5, color: EE.textDim),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: controller.editable ? onReplace : null,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: const Text('Replace'),
                    ),
                    OutlinedButton.icon(
                      onPressed: controller.editable && !removing ? onRemove : null,
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Remove'),
                    ),
                    if (asset.inherited) const Tag('inherited'),
                  ],
                ),
              ],
            );
            if (cons.maxWidth < 760) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [preview, const SizedBox(height: 16), info]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: preview),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: info),
              ],
            );
          },
        ),
      ],
    );
  }
}
