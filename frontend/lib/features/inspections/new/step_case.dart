import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/tokens.dart';
import 'step_common.dart';
import 'wizard_controller.dart';

class CaseStep extends StatefulWidget {
  const CaseStep({super.key, required this.controller});
  final WizardController controller;
  @override
  State<CaseStep> createState() => _CaseStepState();
}

class _CaseStepState extends State<CaseStep> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _cabinet = TextEditingController();
  final _site = TextEditingController();
  final _reference = TextEditingController();
  final _inspector = TextEditingController();
  final _project = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  @override
  void didUpdateWidget(covariant CaseStep old) {
    super.didUpdateWidget(old);
    _fill();
  }

  String? _loadedId;

  void _fill() {
    final i = widget.controller.inspection;
    if (i == null || i.id == _loadedId) return;
    _loadedId = i.id;
    _title.text = i.title;
    _cabinet.text = i.cabinetId;
    _site.text = i.site ?? '';
    _reference.text = i.reference ?? '';
    _inspector.text = i.inspector ?? '';
    _project.text = i.projectRef ?? '';
    _notes.text = i.notes ?? '';
  }

  @override
  void dispose() {
    for (final c in [_title, _cabinet, _site, _reference, _inspector, _project, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.saveCase({
        'title': _title.text.trim(),
        'cabinet_id': _cabinet.text.trim(),
        'site': _opt(_site),
        'reference': _opt(_reference),
        'inspector': _opt(_inspector),
        'project_ref': _opt(_project),
        'notes': _opt(_notes),
      });
      _loadedId = widget.controller.inspection?.id;
      widget.controller.next();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    bool required = false,
    int maxLength = 200,
    int lines = 1,
    bool enabled = true,
    String? helper,
  }) {
    return TextFormField(
      controller: c,
      enabled: enabled,
      maxLines: lines,
      minLines: lines > 1 ? 3 : 1,
      maxLength: maxLength,
      decoration: InputDecoration(labelText: required ? '$label *' : label, hintText: hint, helperText: helper, counterText: ''),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final created = widget.controller.hasCase;
    final i = widget.controller.inspection;
    return StepFrame(
      controller: widget.controller,
      description: 'Identify the cabinet and the inspection context. The case is stored immediately; no sign-in is required in this prototype.',
      primaryLabel: created ? 'Save & continue' : 'Create case & continue',
      primaryBusy: _busy,
      onPrimary: _save,
      trailingHeader: created
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: EE.cyan.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(EE.r1),
              ),
              child: Text(
                i!.code,
                style: const TextStyle(fontFamily: EE.fontMono, color: EE.cyan, fontWeight: FontWeight.w600),
              ),
            )
          : null,
      child: Form(
        key: _form,
        child: LayoutBuilder(
          builder: (context, c) {
            final two = c.maxWidth > 560;
            Widget pair(Widget a, Widget b) => two
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: a),
                      const SizedBox(width: 14),
                      Expanded(child: b),
                    ],
                  )
                : Column(children: [a, const SizedBox(height: 14), b]);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[InlineError(_error!), const SizedBox(height: 14)],
                pair(
                  _field(_title, 'Inspection title', hint: 'e.g. CAB-07 pre-shipment QC', required: true),
                  _field(
                    _cabinet,
                    'Cabinet identifier',
                    hint: 'e.g. CAB-07',
                    required: true,
                    maxLength: 120,
                    enabled: !created,
                    helper: created ? 'Fixed once the case exists (versions refer to this cabinet).' : null,
                  ),
                ),
                const SizedBox(height: 14),
                pair(
                  _field(_site, 'Site or facility', hint: 'Panel shop / plant'),
                  _field(_reference, 'Inspection reference', hint: 'QC-2026-0142', maxLength: 120),
                ),
                const SizedBox(height: 14),
                pair(
                  _field(_inspector, 'Inspector', hint: 'Name or label (optional)', maxLength: 120),
                  _field(_project, 'Project / customer reference', hint: 'optional', maxLength: 120),
                ),
                const SizedBox(height: 14),
                _field(_notes, 'Inspection notes', hint: 'Scope, special instructions, known deviations…', lines: 4, maxLength: 5000),
              ],
            );
          },
        ),
      ),
    );
  }
}
