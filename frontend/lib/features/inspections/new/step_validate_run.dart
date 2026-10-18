import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/badges.dart';
import 'step_common.dart';
import 'wizard_controller.dart';

IconData _icon(String s) => switch (s) {
  'ok' => Icons.check_circle_rounded,
  'warning' => Icons.warning_amber_rounded,
  _ => Icons.cancel_rounded,
};
Color _color(String s) => switch (s) {
  'ok' => EE.pass,
  'warning' => EE.uncertain,
  _ => EE.fail,
};

class ReadinessList extends StatelessWidget {
  const ReadinessList({super.key, required this.items});
  final List<Json> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final i in items)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: EE.bg1,
            borderRadius: BorderRadius.circular(EE.r2),
            border: Border.all(color: EE.line),
          ),
          child: Stack(
            children: [
              Positioned(left: 0, top: 0, bottom: 0, width: 3, child: ColoredBox(color: _color(i.str('status')))),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 10, 12, 10),
                child: LayoutBuilder(
                  builder: (context, cons) {
                    final label = Text(i.str('label'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5));
                    final msg = Text(i.str('message'), style: const TextStyle(fontSize: 12.5, color: EE.textMuted));
                    final icon = Icon(_icon(i.str('status')), size: 17, color: _color(i.str('status')));
                    if (cons.maxWidth < 480) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label, const SizedBox(height: 2), msg]),
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        const SizedBox(width: 10),
                        SizedBox(width: 190, child: label),
                        Expanded(child: msg),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class ValidateStep extends StatefulWidget {
  const ValidateStep({super.key, required this.controller});
  final WizardController controller;
  @override
  State<ValidateStep> createState() => _ValidateStepState();
}

class _ValidateStepState extends State<ValidateStep> {
  WizardController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (c.readiness == null && !c.readinessLoading) WidgetsBinding.instance.addPostFrameCallback((_) => c.loadReadiness());
  }

  @override
  Widget build(BuildContext context) {
    final r = c.readiness;
    final errors = r?.items.where((i) => i.str('status') == 'error').length ?? 0;
    final warns = r?.items.where((i) => i.str('status') == 'warning').length ?? 0;
    return StepFrame(
      controller: c,
      description:
          'The backend re-checks every input before execution: files readable, selected page valid, expected data parseable, detector and OCR '
          'actually loaded, storage writable. Errors block the run; warnings mean some checks will report UNCERTAIN.',
      onPrimary: r != null && r.ready ? c.next : null,
      secondary: OutlinedButton.icon(
        onPressed: c.readinessLoading ? null : c.loadReadiness,
        icon: c.readinessLoading
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('Re-validate'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.readinessError != null) InlineError('Validation request failed: ${c.readinessError}'),
          if (r == null && c.readinessLoading) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: LinearProgressIndicator(minHeight: 2)),
          if (r != null) ...[
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Tag(r.ready ? 'READY TO RUN' : 'NOT READY', color: r.ready ? EE.pass : EE.fail, filled: true, mono: true),
                Text(
                  '${r.items.length - errors - warns} ok · $warns warning(s) · $errors error(s)',
                  style: const TextStyle(fontSize: 12.5, color: EE.textMuted),
                ),
                if (c.readinessLoading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 14),
            ReadinessList(items: r.items),
            if (!r.ready) ...[
              const SizedBox(height: 8),
              const Text('Resolve the errors (go back to the relevant step), then re-validate.', style: TextStyle(fontSize: 12, color: EE.textDim)),
            ],
          ],
        ],
      ),
    );
  }
}

class RunStep extends StatefulWidget {
  const RunStep({super.key, required this.controller});
  final WizardController controller;
  @override
  State<RunStep> createState() => _RunStepState();
}

class _RunStepState extends State<RunStep> {
  bool _submitting = false;
  String? _error;
  List<Json> _blocking = const [];

  WizardController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (c.readiness == null && !c.readinessLoading) WidgetsBinding.instance.addPostFrameCallback((_) => c.loadReadiness());
  }

  Future<void> _run() async {
    if (_submitting) return; // guard against double submission
    setState(() {
      _submitting = true;
      _error = null;
      _blocking = const [];
    });
    try {
      final job = await c.api.run(c.version!.id);
      if (mounted) context.go('/console/live?job=${job.id}');
    } on ApiException catch (e) {
      if (e.code == 'already_running' && e.details is Map && (e.details as Map)['job_id'] != null) {
        if (mounted) context.go('/console/live?job=${(e.details as Map)['job_id']}');
        return;
      }
      setState(() {
        _error = e.message;
        if (e.details is List) _blocking = (e.details as List).map((x) => (x as Map).cast<String, dynamic>()).toList();
        _submitting = false;
      });
      await c.loadReadiness();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = c.version;
    final r = c.readiness;
    final ready = r?.ready ?? false;
    final checks = (v?.config['checks'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final stages = const [
      'Input validation',
      'Image preprocessing',
      'Drawing extraction',
      'Object detection (YOLOv8)',
      'OCR label discovery',
      'Photo-to-drawing registration',
      'Verification rules',
      'Evidence generation',
      'Report generation',
    ];
    return StepFrame(
      controller: c,
      description:
          'Submits the stored files and configuration to the backend as a persisted job. Progress on the next screen comes from the real job '
          'stages; nothing is animated ahead of the backend.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[InlineError(_error!), const SizedBox(height: 10)],
          if (_blocking.isNotEmpty) ...[ReadinessList(items: _blocking), const SizedBox(height: 10)],
          if (v != null && !v.editable)
            InlineError('Version ${v.no} is ${v.status}. Completed versions are immutable — create a reinspection from History instead.', color: EE.uncertain),
          LayoutBuilder(
            builder: (context, cons) {
              final plan = Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: EE.bg1,
                  borderRadius: BorderRadius.circular(EE.r2),
                  border: Border.all(color: EE.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SubHeading('Pipeline stages'),
                    for (var i = 0; i < stages.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Text(
                              (i + 1).toString().padLeft(2, '0'),
                              style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.cyan),
                            ),
                            const SizedBox(width: 10),
                            Text(stages[i], style: const TextStyle(fontSize: 12.5)),
                          ],
                        ),
                      ),
                  ],
                ),
              );
              final what = Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: EE.bg1,
                  borderRadius: BorderRadius.circular(EE.r2),
                  border: Border.all(color: EE.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SubHeading('Checks to run'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final k in checks) Tag(checkLabels[k] ?? k, color: k == 'wire_color' ? EE.violet : EE.cyan)],
                    ),
                    const SizedBox(height: 14),
                    const SubHeading('Inputs'),
                    for (final kind in const ['photo', 'drawing', 'expected_list'])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                              c.asset(kind) != null ? Icons.check_rounded : Icons.remove_rounded,
                              size: 15,
                              color: c.asset(kind) != null ? EE.pass : EE.textDim,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(c.asset(kind)?.filename ?? 'not supplied', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
              if (cons.maxWidth < 700) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [what, const SizedBox(height: 12), plan]);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: what),
                  const SizedBox(width: 12),
                  Expanded(child: plan),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                onPressed: ready && !_submitting && (v?.editable ?? false) ? _run : null,
                icon: _submitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: EE.textDim))
                    : const Icon(Icons.play_arrow_rounded, size: 22),
                label: Text(_submitting ? 'Submitting…' : 'Run Inspection'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              ready ? 'All required inputs validated.' : (c.readinessLoading ? 'Validating…' : 'Run is disabled until validation passes (step 06).'),
              style: TextStyle(fontSize: 12, color: ready ? EE.pass : EE.textDim),
            ),
          ),
        ],
      ),
    );
  }
}
