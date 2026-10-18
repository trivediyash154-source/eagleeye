import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import 'diagnostics_widgets.dart';

/// Live test operation: runs the real detector or OCR engine on a supplied image (or the
/// bundled synthetic fixture) and shows the actual output. Nothing here is simulated.
class ModelTestCard extends ConsumerStatefulWidget {
  const ModelTestCard({super.key, required this.kind, this.onCompleted});
  final String kind; // detector | ocr
  final VoidCallback? onCompleted;

  @override
  ConsumerState<ModelTestCard> createState() => _ModelTestCardState();
}

class _ModelTestCardState extends ConsumerState<ModelTestCard> {
  bool _running = false;
  DateTime? _started;
  Timer? _ticker;
  Json? _result;
  Uint8List? _annotated;
  Object? _error;
  String? _input;

  bool get _detector => widget.kind == 'detector';

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _run({required bool upload}) async {
    Uint8List? bytes;
    String? name;
    if (upload) {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png']);
      if (files.isEmpty) return;
      bytes = await files.first.readAsBytes();
      name = files.first.name;
    }
    setState(() {
      _running = true;
      _started = DateTime.now();
      _error = null;
      _result = null;
      _annotated = null;
      _input = name ?? 'bundled synthetic fixture';
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final api = ref.read(apiProvider);
    try {
      final r = _detector ? await api.detectorTest(bytes: bytes, filename: name) : await api.ocrTest(bytes: bytes, filename: name);
      Uint8List? img;
      final dataUrl = r['annotated_image'] as String?;
      if (dataUrl != null) {
        try {
          img = UriData.parse(dataUrl).contentAsBytes();
        } catch (_) {
          img = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _result = r;
        _annotated = img;
      });
      widget.onCompleted?.call();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _ticker?.cancel();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _detector ? 'Detector test' : 'OCR test';
    final elapsed = _started == null ? 0 : DateTime.now().difference(_started!).inSeconds;
    return Panel(
      eyebrow: _detector ? 'Live inference · YOLOv8' : 'Live inference · OCR',
      title: title,
      subtitle: _detector
          ? 'Runs the loaded detector (full image + tiles) and returns its real boxes and confidences.'
          : 'Runs the active OCR engine on the full image and returns every recognised region.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _running ? null : () => _run(upload: false),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Run on bundled fixture'),
          ),
          OutlinedButton.icon(
            onPressed: _running ? null : () => _run(upload: true),
            icon: const Icon(Icons.upload_file_rounded, size: 17),
            label: const Text('Upload image & run'),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('The bundled fixture is a SYNTHETIC cabinet render. CPU inference can take tens of seconds.', style: TextStyle(fontSize: 11.5, color: EE.textDim)),
        if (_running) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          Text('Running on ${_input ?? 'image'} · ${elapsed}s elapsed (waiting for the backend; no progress is simulated)',
              style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted)),
        ],
        if (_error != null) ...[const SizedBox(height: 14), ErrorView(_error!, compact: true, onRetry: () => _run(upload: false))],
        if (_result != null) ...[const SizedBox(height: 14), _ResultView(kind: widget.kind, result: _result!, image: _annotated, input: _input)],
      ]),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.kind, required this.result, required this.image, required this.input});
  final String kind;
  final Json result;
  final Uint8List? image;
  final String? input;

  @override
  Widget build(BuildContext context) {
    final det = kind == 'detector';
    final items = det ? result.objs('detections') : result.objs('regions');
    final above = det ? items.where((d) => d.boolean('above_threshold')).length : items.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        MiniStat('Duration', fmtMs(result.intN('duration_ms')), color: EE.cyan),
        if (det) MiniStat('Device', dv(result['device'])),
        if (det) MiniStat('Tiles', dv(result['tiles'])),
        if (det) MiniStat('Conf ≥', dv(result['conf_threshold'])),
        MiniStat(det ? 'Detections ≥ thr' : 'Text regions', '$above', color: above > 0 ? EE.pass : EE.uncertain),
        if (det) MiniStat('Stored (≥ min)', '${items.length}'),
      ]),
      const SizedBox(height: 10),
      KV('Source', dv(result['source']), keyWidth: 110),
      KV(det ? 'Model' : 'Engine', det ? '${dv(result['model'])} (${dv(result['kind'])})' : dv(result['engine']), mono: true, keyWidth: 110),
      if (det && result.str('kind') == 'generic_coco')
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Callout(child: Text('Generic COCO weights: zero cabinet detections is the expected, honest result for this model.')),
        ),
      if (image != null) ...[
        const SizedBox(height: 10),
        _AnnotatedPreview(bytes: image!, title: det ? 'Detector output' : 'OCR output'),
      ],
      const SizedBox(height: 10),
      if (det)
        DenseTable(
          columns: const ['Class', 'Confidence', 'Box (px)', 'Status'],
          flex: const [4, 3, 6, 3],
          empty: 'No detections returned by the model.',
          rows: [
            for (final d in items)
              [
                Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: EE.detClass(d.str('class_name')), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(d.str('class_name'), style: monoCell, overflow: TextOverflow.ellipsis)),
                ]),
                Text(fmtConf(d['confidence']), style: monoCell),
                Text(_box(d.box('bbox')), style: monoCell.copyWith(color: EE.textMuted)),
                d.boolean('above_threshold') ? const Tag('≥ thr', color: EE.pass) : const Tag('low', color: EE.textDim),
              ],
          ],
        )
      else
        DenseTable(
          columns: const ['Text', 'Confidence', 'Box (px)'],
          flex: const [4, 2, 6],
          empty: 'No text regions recognised.',
          rows: [
            for (final r in items)
              [
                Text(r.str('text'), style: monoCell.copyWith(fontWeight: FontWeight.w600)),
                Text(fmtConf(r['confidence']), style: monoCell.copyWith(color: (r.dbl('confidence') ?? 0) < 0.5 ? EE.uncertain : EE.text)),
                Text(_box(r.box('bbox')), style: monoCell.copyWith(color: EE.textMuted)),
              ],
          ],
        ),
    ]);
  }

  static String _box(List<double>? b) => b == null ? '—' : b.map((v) => v.toStringAsFixed(0)).join(', ');
}

class _AnnotatedPreview extends StatelessWidget {
  const _AnnotatedPreview({required this.bytes, required this.title});
  final Uint8List bytes;
  final String title;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
                child: Row(children: [
                  Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              Flexible(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(EE.r3)),
                  child: InteractiveViewer(maxScale: 8, child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)),
                ),
              ),
            ]),
          ),
        ),
        child: Container(
          height: 240,
          decoration: BoxDecoration(color: EE.bg0, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line)),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned.fill(child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: EE.bg0.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: EE.line)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.zoom_in_rounded, size: 13, color: EE.textMuted),
                  SizedBox(width: 4),
                  Text('Expand', style: TextStyle(fontSize: 11, color: EE.textMuted)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
