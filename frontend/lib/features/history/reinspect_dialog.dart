import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/panel.dart';

/// Creates a new version of an inspection (earlier versions stay untouched) and starts it.
Future<void> showReinspectDialog(BuildContext context, Inspection inspection) =>
    showDialog<void>(context: context, builder: (_) => _ReinspectDialog(inspection: inspection));

class _ReinspectDialog extends ConsumerStatefulWidget {
  const _ReinspectDialog({required this.inspection});
  final Inspection inspection;
  @override
  ConsumerState<_ReinspectDialog> createState() => _ReinspectDialogState();
}

class _ReinspectDialogState extends ConsumerState<_ReinspectDialog> {
  final _label = TextEditingController(text: 'Reinspection after corrections');
  bool _reuse = false;
  Uint8List? _bytes;
  String? _name;
  double _progress = 0;
  bool _busy = false;
  String? _error;
  String? _stage;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png']);
    if (files.isEmpty) return;
    final f = files.first;
    final bytes = await f.readAsBytes();
    setState(() {
      _bytes = bytes;
      _name = f.name;
      _reuse = false;
      _error = null;
    });
  }

  Future<void> _submit({bool fixture = false}) async {
    final api = ref.read(apiProvider);
    setState(() {
      _busy = true;
      _error = null;
      _stage = fixture ? 'Creating reinspection from fixture photo v2' : 'Creating new version';
    });
    try {
      String jobId;
      if (fixture) {
        final res = await api.sampleReinspect(widget.inspection.id);
        jobId = res.obj('job').str('id');
      } else {
        final v = await api.reinspect(
          widget.inspection.id,
          label: _label.text.trim().isEmpty ? null : _label.text.trim(),
          photo: _reuse ? null : _bytes,
          photoName: _name,
          reusePhoto: _reuse,
          onProgress: (p) => setState(() => _progress = p),
        );
        setState(() => _stage = 'Version v${v.no} created — starting the pipeline');
        try {
          final job = await api.run(v.id);
          jobId = job.id;
        } on ApiException catch (e) {
          // the draft version exists; tell the user exactly what blocked the run
          setState(() {
            _busy = false;
            _error = 'Version v${v.no} was created but could not start: ${e.message}';
          });
          refreshInspectionData(ref, inspectionId: widget.inspection.id);
          return;
        }
      }
      refreshInspectionData(ref, inspectionId: widget.inspection.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.go('/console/live?job=$jobId');
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.inspection;
    final canSubmit = !_busy && (_reuse || _bytes != null);
    return AlertDialog(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Eyebrow('Reinspection'),
        const SizedBox(height: 6),
        Text('New version of ${i.code}'),
      ]),
      content: SizedBox(
        width: 540,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            'A reinspection creates a new version that inherits the GA drawing, expected list and configuration of the latest completed version. '
            'The earlier version, its findings, evidence and review decisions remain unchanged.',
            style: TextStyle(fontSize: 12.5, color: EE.textMuted, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(controller: _label, decoration: const InputDecoration(labelText: 'Version label')),
          const SizedBox(height: 16),
          _Option(
            selected: !_reuse,
            title: 'Upload a new cabinet photograph',
            subtitle: _name == null ? 'JPG or PNG of the corrected cabinet' : '$_name · ${fmtBytes(_bytes?.length)}',
            onTap: () => setState(() => _reuse = false),
            trailing: OutlinedButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload_file_rounded, size: 16), label: Text(_name == null ? 'Choose file' : 'Replace')),
          ),
          const SizedBox(height: 8),
          _Option(
            selected: _reuse,
            title: 'Reuse the previous photograph',
            subtitle: 'Re-runs the pipeline on the same image (e.g. after zone or alignment corrections)',
            onTap: () => setState(() => _reuse = true),
          ),
          if (i.isDemo) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: EE.violet.withValues(alpha: 0.08), border: Border.all(color: EE.violet.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(EE.r2)),
              child: Row(children: [
                const DemoTag(compact: true),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Demo inspection: use the bundled synthetic photo of the corrected cabinet (fixture v2).', style: TextStyle(fontSize: 12, color: EE.textMuted)),
                ),
                TextButton(onPressed: _busy ? null : () => _submit(fixture: true), child: const Text('Use fixture v2')),
              ]),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _bytes != null && !_reuse && _progress > 0 && _progress < 1 ? _progress : null, minHeight: 2),
            const SizedBox(height: 6),
            Text(_stage ?? '', style: const TextStyle(fontSize: 12, color: EE.textMuted)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(fontSize: 12.5, color: EE.fail)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton.icon(onPressed: canSubmit ? _submit : null, icon: const Icon(Icons.play_arrow_rounded, size: 18), label: const Text('Create version & run')),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.selected, required this.title, required this.subtitle, required this.onTap, this.trailing});
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(EE.r2),
        child: AnimatedContainer(
          duration: EE.fast,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? EE.cyan.withValues(alpha: 0.06) : EE.bg1,
            borderRadius: BorderRadius.circular(EE.r2),
            border: Border.all(color: selected ? EE.cyan.withValues(alpha: 0.5) : EE.line),
          ),
          child: Row(children: [
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 18, color: selected ? EE.cyan : EE.textDim),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11.5, color: EE.textMuted)),
              ]),
            ),
            ?trailing,
          ]),
        ),
      );
}
