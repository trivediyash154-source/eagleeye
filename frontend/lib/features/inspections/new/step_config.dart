import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/badges.dart';
import 'step_common.dart';
import 'wizard_controller.dart';

const _order = ['component_presence', 'component_type', 'device_label', 'ferrule_label', 'wire_color', 'zone_correspondence', 'drawing_alignment'];

class ConfigStep extends StatefulWidget {
  const ConfigStep({super.key, required this.controller});
  final WizardController controller;
  @override
  State<ConfigStep> createState() => _ConfigStepState();
}

class _ConfigStepState extends State<ConfigStep> {
  List<Json>? _checks;
  Object? _checksError;
  late Set<String> _selected;
  late bool _clahe, _denoise, _deskew;
  late String _labelMode, _ferruleMode;
  double? _conf; // null = server default
  bool _saving = false;
  String? _error;

  WizardController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    final cfg = c.version?.config ?? const <String, dynamic>{};
    _selected = {...cfg.strs('checks')};
    if (_selected.isEmpty) _selected = {'component_presence', 'component_type', 'device_label', 'ferrule_label', 'zone_correspondence', 'drawing_alignment'};
    final pp = cfg.obj('preprocess');
    _clahe = pp.boolean('clahe', true);
    _denoise = pp.boolean('denoise');
    _deskew = pp.boolean('deskew');
    final pol = cfg.obj('policies');
    _labelMode = pol.obj('device_label').str('mode', 'confusion_aware');
    _ferruleMode = pol.obj('ferrule').str('mode', 'confusion_aware');
    _conf = cfg.obj('detector').dbl('conf');
    _loadChecks();
  }

  Future<void> _loadChecks() async {
    setState(() {
      _checks = null;
      _checksError = null;
    });
    try {
      final items = await c.api.checks();
      if (mounted) setState(() => _checks = items);
    } catch (e) {
      if (mounted) setState(() => _checksError = e);
    }
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      setState(() => _error = 'Select at least one check.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await c.saveConfig({
        'checks': _order.where(_selected.contains).toList(),
        'preprocess': {'clahe': _clahe, 'denoise': _denoise, 'deskew': _deskew},
        'policies': {
          'device_label': {'mode': _labelMode},
          'ferrule': {'mode': _ferruleMode},
        },
        'detector': {'conf': _conf},
      });
      c.next();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepFrame(
      controller: c,
      description:
          'Choose which verification checks to run. Availability reflects the models actually loaded on the backend: a check whose '
          'model is missing still runs but reports UNCERTAIN with the reason — it is never silently passed.',
      primaryLabel: 'Save configuration & continue',
      primaryBusy: _saving,
      onPrimary: c.editable ? _save : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[InlineError(_error!), const SizedBox(height: 14)],
          if (!c.editable) ...[
            InlineError('Version ${c.version?.no} is ${c.version?.status}; its configuration is immutable.', color: EE.uncertain),
            const SizedBox(height: 14),
          ],
          const SubHeading('Checks'),
          if (_checksError != null)
            InlineError('Could not load check availability: $_checksError')
          else if (_checks == null)
            const LinearProgressIndicator(minHeight: 2)
          else
            Column(
              children: [
                for (final key in _order)
                  if (_checks!.where((x) => x.str('key') == key).firstOrNull case final info?) _checkRow(info),
              ],
            ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, cons) {
              final pre = _preprocessPanel();
              final pol = _policyPanel();
              if (cons.maxWidth < 760) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [pre, const SizedBox(height: 16), pol]);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: pre),
                  const SizedBox(width: 16),
                  Expanded(child: pol),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _checkRow(Json info) {
    final key = info.str('key');
    final on = _selected.contains(key);
    final experimental = info.str('status') == 'experimental';
    final available = info.boolean('available', true);
    return InkWell(
      onTap: c.editable ? () => setState(() => on ? _selected.remove(key) : _selected.add(key)) : null,
      borderRadius: BorderRadius.circular(EE.r2),
      child: AnimatedContainer(
        duration: EE.fast,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
        decoration: BoxDecoration(
          color: on ? EE.cyan.withValues(alpha: 0.05) : EE.bg1,
          borderRadius: BorderRadius.circular(EE.r2),
          border: Border.all(color: on ? EE.cyan.withValues(alpha: 0.35) : EE.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: on, onChanged: c.editable ? (v) => setState(() => v == true ? _selected.add(key) : _selected.remove(key)) : null),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(info.str('title', checkLabels[key] ?? key), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        experimental
                            ? const Tag('EXPERIMENTAL', color: EE.violet, filled: true, mono: true)
                            : const Tag('IMPLEMENTED', color: EE.pass, mono: true),
                        if (!available) const Tag('MODEL NOT AVAILABLE', color: EE.uncertain, mono: true),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('Requires: ${info.str('requires')}', style: const TextStyle(fontSize: 12, color: EE.textMuted)),
                    if (!available && info.strN('note') != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('Will report UNCERTAIN: ${info.str('note')}', style: const TextStyle(fontSize: 12, color: EE.uncertain)),
                      ),
                    if (experimental)
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text(
                          'Heuristic colour classification; results depend on lighting and white balance and are flagged for review.',
                          style: TextStyle(fontSize: 11.5, color: EE.textDim),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(String title, String sub, bool v, ValueChanged<bool> f) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(sub, style: const TextStyle(fontSize: 11.5, color: EE.textMuted)),
            ],
          ),
        ),
        Switch(value: v, onChanged: c.editable ? f : null),
      ],
    ),
  );

  Widget _box(Widget child) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: EE.bg1,
      borderRadius: BorderRadius.circular(EE.r2),
      border: Border.all(color: EE.line),
    ),
    child: child,
  );

  Widget _preprocessPanel() => _box(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SubHeading('Image preprocessing'),
        _toggle('CLAHE contrast enhancement', 'Local contrast on the L channel; helps small labels', _clahe, (v) => setState(() => _clahe = v)),
        _toggle('Denoise', 'Non-local means; slower, for grainy low-light photos', _denoise, (v) => setState(() => _denoise = v)),
        _toggle('Deskew', 'Rotate by the dominant DIN-rail angle (0.3°–8°); coordinates are mapped back', _deskew, (v) => setState(() => _deskew = v)),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Detector confidence threshold', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('Detections below it count as weak evidence (UNCERTAIN), never as absence.', style: TextStyle(fontSize: 11.5, color: EE.textMuted)),
                ],
              ),
            ),
            Text(
              _conf == null ? 'server default' : _conf!.toStringAsFixed(2),
              style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5, color: EE.cyan),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _conf ?? 0.35,
                min: 0.15,
                max: 0.8,
                divisions: 13,
                onChanged: c.editable ? (v) => setState(() => _conf = double.parse(v.toStringAsFixed(2))) : null,
              ),
            ),
            TextButton(onPressed: c.editable && _conf != null ? () => setState(() => _conf = null) : null, child: const Text('Default')),
          ],
        ),
      ],
    ),
  );

  Widget _modeSelector(String label, String value, ValueChanged<String> f) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: EE.cyan.withValues(alpha: 0.16),
            selectedForegroundColor: EE.cyan,
            foregroundColor: EE.textMuted,
            side: const BorderSide(color: EE.lineHi),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          segments: const [
            ButtonSegment(value: 'confusion_aware', label: Text('Confusion-aware')),
            ButtonSegment(value: 'distance_bands', label: Text('Distance bands')),
          ],
          selected: {value},
          onSelectionChanged: c.editable ? (s) => f(s.first) : null,
        ),
      ],
    ),
  );

  Widget _policyPanel() => _box(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SubHeading('Identifier matching policy'),
        _modeSelector('Device labels', _labelMode, (v) => setState(() => _labelMode = v)),
        _modeSelector('Ferrules', _ferruleMode, (v) => setState(() => _ferruleMode = v)),
        const Text(
          'Confusion-aware (default): exact normalised match → PASS; differences that are only OCR-confusable characters (8/B, 0/O, 1/I, 5/S) '
          '→ UNCERTAIN; any other difference read with reliable confidence → FAIL. A one-character difference can be a different terminal '
          '(X12-4B vs X12-8B), so it is not automatically forgiven.\n\n'
          'Distance bands (slide-deck rule): Levenshtein d = 0 → PASS, d = 1 → UNCERTAIN, d ≥ 2 → FAIL.\n\n'
          'Both policies keep the raw OCR string, never rewrite it toward the expected value, and never FAIL on unreadable or low-confidence text.',
          style: TextStyle(fontSize: 11.5, color: EE.textMuted, height: 1.45),
        ),
      ],
    ),
  );
}
