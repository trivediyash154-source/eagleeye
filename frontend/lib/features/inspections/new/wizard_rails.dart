import 'package:flutter/material.dart';

import '../../../core/api/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/panel.dart';
import 'wizard_controller.dart';

/// Horizontal rail of numbered technical step markers.
class StepRail extends StatelessWidget {
  const StepRail({super.key, required this.controller});
  final WizardController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final s in WizardStep.values) ...[
            if (s.index > 0)
              AnimatedContainer(
                duration: EE.med,
                width: 26,
                height: 1.4,
                color: c.isComplete(WizardStep.values[s.index - 1]) ? EE.cyan.withValues(alpha: 0.6) : EE.line,
              ),
            _Marker(controller: c, step: s),
          ],
        ],
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.controller, required this.step});
  final WizardController controller;
  final WizardStep step;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final current = c.step == step;
    final done = c.isComplete(step);
    final enabled = c.canEnter(step);
    final color = current ? EE.cyan : (done ? EE.pass : (enabled ? EE.textMuted : EE.textDim));
    return Tooltip(
      message: enabled ? step.title : 'Create the case first',
      child: InkWell(
        onTap: enabled ? () => c.goTo(step) : null,
        borderRadius: BorderRadius.circular(EE.r2),
        child: AnimatedContainer(
          duration: EE.fast,
          padding: const EdgeInsets.fromLTRB(8, 7, 12, 7),
          decoration: BoxDecoration(
            color: current ? EE.cyan.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(EE.r2),
            border: Border.all(color: current ? EE.cyan.withValues(alpha: 0.5) : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: EE.fast,
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done && !current ? EE.pass.withValues(alpha: 0.12) : EE.bg1,
                  borderRadius: BorderRadius.circular(EE.r1),
                  border: Border.all(color: color.withValues(alpha: current || done ? 0.9 : 0.5)),
                  boxShadow: current ? [BoxShadow(color: EE.cyan.withValues(alpha: 0.35), blurRadius: 10)] : null,
                ),
                child: done && !current
                    ? const Icon(Icons.check_rounded, size: 14, color: EE.pass)
                    : Text(
                        (step.index + 1).toString().padLeft(2, '0'),
                        style: TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                step.short,
                style: TextStyle(fontSize: 12.5, fontWeight: current ? FontWeight.w600 : FontWeight.w500, color: current ? EE.text : color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Right-hand rail: case summary, input completeness and readiness.
class SummaryRail extends StatelessWidget {
  const SummaryRail({super.key, required this.controller});
  final WizardController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final i = c.inspection;
    final v = c.version;
    final photo = c.asset('photo'), drawing = c.asset('drawing'), list = c.asset('expected_list');
    final required = [photo, list].where((a) => a != null).length;
    final completeness = (required + (drawing != null ? 1 : 0)) / 3;
    final r = c.readiness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          eyebrow: 'Case',
          title: i?.title ?? 'New inspection case',
          actions: [if (i?.isDemo ?? false) const DemoTag(compact: true)],
          child: i == null
              ? const Text(
                  'Fill in step 01 to create the case. It is persisted immediately with version 1 in draft.',
                  style: TextStyle(fontSize: 12.5, color: EE.textMuted),
                )
              : Column(
                  children: [
                    KV('Inspection', i.code, mono: true, valueColor: EE.cyan, keyWidth: 96),
                    KV('Cabinet', i.cabinetId, mono: true, keyWidth: 96),
                    if (i.site != null) KV('Site', i.site, keyWidth: 96),
                    if (i.reference != null) KV('Reference', i.reference, keyWidth: 96),
                    if (i.inspector != null) KV('Inspector', i.inspector, keyWidth: 96),
                    if (v != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 96,
                              child: Text('Version', style: TextStyle(fontSize: 12, color: EE.textDim)),
                            ),
                            Text('v${v.no} · ', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12)),
                            StatePill(v.status),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: EE.s4),
        Panel(
          eyebrow: 'Input completeness',
          title: '${(completeness * 100).round()}% of inputs supplied',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: completeness),
                  duration: EE.slow,
                  builder: (_, val, _) => LinearProgressIndicator(value: val, minHeight: 4, color: completeness == 1 ? EE.pass : EE.cyan),
                ),
              ),
              const SizedBox(height: 12),
              _InputRow(
                label: 'Cabinet photo',
                required: true,
                name: photo?.filename,
                detail: photo == null
                    ? null
                    : '${photo.analysis.integer('width')}×${photo.analysis.integer('height')} · quality ${photo.analysis.obj('quality').str('rating')}',
                busy: c.uploadProgress.containsKey('photo'),
                onTap: c.hasCase ? () => c.goTo(WizardStep.photo) : null,
              ),
              _InputRow(
                label: 'GA drawing',
                required: false,
                name: drawing?.filename,
                detail: drawing == null
                    ? null
                    : 'page ${c.drawingPage + 1}/${drawing.analysis.integer('page_count')} · ${_pageKind(drawing.analysis, c.drawingPage)}',
                busy: c.uploadProgress.containsKey('drawing'),
                onTap: c.hasCase ? () => c.goTo(WizardStep.drawing) : null,
              ),
              _InputRow(
                label: 'Expected lists',
                required: true,
                name: list?.filename,
                detail: list == null ? null : '${c.sheets.where((s) => s.include).length} sheet(s) included${c.sheetsDirty ? ' · unsaved mapping' : ''}',
                busy: c.uploadProgress.containsKey('expected_list'),
                onTap: c.hasCase ? () => c.goTo(WizardStep.expectedList) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: EE.s4),
        Panel(
          eyebrow: 'Readiness',
          title: r == null ? 'Not validated yet' : (r.ready ? 'Ready to run' : 'Blocking issues'),
          accent: r == null ? null : (r.ready ? EE.pass : EE.fail),
          actions: [
            IconButton(
              tooltip: 'Validate now',
              onPressed: c.hasCase && !c.readinessLoading ? c.loadReadiness : null,
              icon: c.readinessLoading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 18),
            ),
          ],
          child: r == null
              ? Text(
                  c.hasCase ? 'Validation runs on the backend against the stored files and loaded models.' : 'Create the case to validate inputs.',
                  style: const TextStyle(fontSize: 12.5, color: EE.textMuted),
                )
              : Column(
                  children: [
                    for (final item in r.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                              switch (item.str('status')) {
                                'ok' => Icons.check_circle_rounded,
                                'warning' => Icons.warning_amber_rounded,
                                _ => Icons.cancel_rounded,
                              },
                              size: 14,
                              color: switch (item.str('status')) {
                                'ok' => EE.pass,
                                'warning' => EE.uncertain,
                                _ => EE.fail,
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(item.str('label'), style: const TextStyle(fontSize: 12.5))),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  static String _pageKind(Map<String, dynamic> analysis, int page) {
    final pages = (analysis['pages'] as List?) ?? const [];
    if (page >= pages.length) return '—';
    return (pages[page] as Map)['kind']?.toString() ?? '—';
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({required this.label, required this.required, required this.name, required this.detail, required this.busy, this.onTap});
  final String label;
  final bool required;
  final String? name;
  final String? detail;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ok = name != null;
    final color = ok ? EE.pass : (required ? EE.uncertain : EE.textDim);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(EE.r1),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: busy
                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 15, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Text(required ? 'required' : 'recommended', style: const TextStyle(fontSize: 10.5, color: EE.textDim)),
                    ],
                  ),
                  Text(
                    name ?? 'not uploaded',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: ok ? EE.textMuted : EE.textDim),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.textDim),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
