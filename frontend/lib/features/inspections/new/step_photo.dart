import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/file_drop.dart';
import 'step_common.dart';
import 'wizard_controller.dart';

const _photoExts = ['jpg', 'jpeg', 'png'];
const _photoMax = 25 * 1024 * 1024;

class PhotoStep extends StatefulWidget {
  const PhotoStep({super.key, required this.controller});
  final WizardController controller;
  @override
  State<PhotoStep> createState() => _PhotoStepState();
}

class _PhotoStepState extends State<PhotoStep> {
  String? _clientError;
  bool _removing = false;

  WizardController get c => widget.controller;

  Future<void> _upload(PickedFile f) async {
    setState(() => _clientError = null);
    await c.upload('photo', f);
  }

  Future<void> _replace() async {
    try {
      final f = await pickFile(_photoExts);
      if (f == null) return;
      final err = validatePicked(f, _photoExts, _photoMax);
      if (err != null) {
        setState(() => _clientError = err);
        return;
      }
      await _upload(f);
    } catch (e) {
      setState(() => _clientError = 'Could not read the file: $e');
    }
  }

  Future<void> _remove() async {
    setState(() => _removing = true);
    try {
      await c.removeAsset('photo');
    } on ApiException catch (e) {
      setState(() => _clientError = e.message);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = c.asset('photo');
    final busy = c.uploadProgress.containsKey('photo');
    final err = _clientError ?? c.uploadError['photo'];
    return StepFrame(
      controller: c,
      description:
          'Upload a sharp, evenly lit photograph of the open cabinet. The original file is preserved as evidence; '
          'quality diagnostics warn about blur, darkness or low resolution but do not block the run.',
      onPrimary: a != null && !busy ? c.next : null,
      secondary: a == null ? TextButton(onPressed: busy ? null : c.next, child: const Text('Skip for now')) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (err != null) ...[InlineError(err), const SizedBox(height: 14)],
          if (a == null || busy)
            FileDropZone(
              extensions: _photoExts,
              maxBytes: _photoMax,
              title: 'Drop the cabinet photograph',
              icon: Icons.photo_camera_outlined,
              busy: busy,
              progress: c.uploadProgress['photo'],
              enabled: c.editable,
              onFile: _upload,
              onRejected: (m) => setState(() => _clientError = m),
            )
          else
            _PhotoAnalysis(controller: c, asset: a, onReplace: _replace, onRemove: _remove, removing: _removing),
        ],
      ),
    );
  }
}

class _PhotoAnalysis extends StatelessWidget {
  const _PhotoAnalysis({required this.controller, required this.asset, required this.onReplace, required this.onRemove, required this.removing});
  final WizardController controller;
  final Asset asset;
  final VoidCallback onReplace;
  final VoidCallback onRemove;
  final bool removing;

  @override
  Widget build(BuildContext context) {
    final an = asset.analysis;
    final q = an.obj('quality');
    final warnings = q.objs('warnings');
    final rating = q.str('rating', '—');
    final ratingColor = switch (rating) {
      'good' => EE.pass,
      'acceptable' => EE.uncertain,
      'poor' => EE.fail,
      _ => EE.textMuted,
    };
    final bytes = controller.photoBytes;
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(EE.r2),
      child: Container(
        color: EE.bg0,
        constraints: const BoxConstraints(maxHeight: 340),
        width: double.infinity,
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)
            : Image.network(
                controller.api.url(asset.downloadUrl),
                fit: BoxFit.contain,
                errorBuilder: (_, e, _) => const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('Preview unavailable', style: TextStyle(color: EE.textDim)),
                  ),
                ),
              ),
      ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.image_outlined, size: 16, color: EE.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                asset.filename,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (asset.inherited) const Tag('inherited'),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${an.integer('width')} × ${an.integer('height')} px · ${fmtBytes(asset.sizeBytes)} · ${an.str('format')} · EXIF orientation ${an.integer('exif_orientation', 1)}',
          style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          'SHA-256 ${asset.sha256.substring(0, 16)}…',
          style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Text('Image quality', style: TextStyle(fontSize: 12.5, color: EE.textMuted)),
            const SizedBox(width: 10),
            Tag(rating.toUpperCase(), color: ratingColor, filled: true, mono: true),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Metric('Megapixels', '${q.dbl('megapixels') ?? '—'}'),
            Metric(
              'Sharpness',
              '${q.dbl('sharpness_laplacian_var') ?? '—'}',
              hint: 'Variance of the Laplacian at 1000 px long side; < 60 suggests blur, < 25 strong blur',
            ),
            Metric('Brightness', '${q.dbl('brightness_mean') ?? '—'}', hint: 'Mean grey level 0–255; < 55 dark, > 215 overexposed'),
            Metric('Contrast', '${q.dbl('contrast_std') ?? '—'}', hint: 'Grey-level standard deviation; < 28 low contrast'),
            Metric('Glare', pct(q.dbl('clipped_highlights_ratio'), digits: 1), hint: 'Share of saturated pixels'),
          ],
        ),
        const SizedBox(height: 12),
        if (warnings.isEmpty)
          const InlineError('No quality warnings. Small labels should be legible at this resolution.', color: EE.pass, icon: Icons.check_circle_outline_rounded)
        else
          Column(
            children: [
              for (final w in warnings) ...[
                InlineError('${w.str('message')}  [${w.str('code')}]', color: EE.uncertain, icon: Icons.warning_amber_rounded),
                const SizedBox(height: 6),
              ],
              const Text(
                'Warnings do not block the run; affected checks will report UNCERTAIN where evidence is insufficient.',
                style: TextStyle(fontSize: 11.5, color: EE.textDim),
              ),
            ],
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
              icon: removing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, cons) {
        if (cons.maxWidth < 720) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [preview, const SizedBox(height: 16), info]);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: preview),
            const SizedBox(width: 20),
            Expanded(flex: 5, child: info),
          ],
        );
      },
    );
  }
}
