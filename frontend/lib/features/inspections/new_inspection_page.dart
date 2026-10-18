import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/download.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import 'new/step_case.dart';
import 'new/step_common.dart';
import 'new/step_config.dart';
import 'new/step_drawing.dart';
import 'new/step_list.dart';
import 'new/step_photo.dart';
import 'new/step_validate_run.dart';
import 'new/wizard_controller.dart';
import 'new/wizard_rails.dart';

/// Guided inspection creation: case → photo → GA drawing → expected lists → checks → validate → run.
/// Every step talks to the real backend; nothing is simulated.
class NewInspectionPage extends ConsumerStatefulWidget {
  const NewInspectionPage({super.key});
  @override
  ConsumerState<NewInspectionPage> createState() => _NewInspectionPageState();
}

class _NewInspectionPageState extends ConsumerState<NewInspectionPage> {
  late WizardController _c;
  bool _loadingDemo = false;

  @override
  void initState() {
    super.initState();
    _c = WizardController(ref.read(apiProvider));
    _c.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  void _reset() {
    _c.removeListener(_onChange);
    _c.dispose();
    setState(() {
      _c = WizardController(ref.read(apiProvider));
      _c.addListener(_onChange);
    });
  }

  Future<void> _loadDemo() async {
    setState(() => _loadingDemo = true);
    try {
      final res = await _c.api.sampleInspection(run: false);
      final insp = Inspection(res.obj('inspection'));
      _c.load(insp);
      _c.goTo(WizardStep.photo);
      refreshInspectionData(ref, inspectionId: insp.id);
      if (mounted) showSnack(context, '${insp.code} created from the bundled SYNTHETIC fixtures. Walk through the steps, then run.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loadingDemo = false);
    }
  }

  Future<void> _showFixtures() async {
    Json? data;
    Object? err;
    try {
      data = await _c.api.fixtures();
    } catch (e) {
      err = e;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bundled demonstration fixtures'),
        content: SizedBox(
          width: 560,
          child: err != null
              ? Text('Could not load the fixture list: $err', style: const TextStyle(color: EE.fail))
              : !(data?.boolean('installed') ?? false)
              ? Text(data?.str('message') ?? 'Fixtures are not installed.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InlineError(data!.str('notice'), color: EE.violet, icon: Icons.science_outlined),
                    const SizedBox(height: 12),
                    for (final f in data.objs('files'))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_fixtureIcon(f.str('name')), size: 18, color: EE.textMuted),
                        title: Text(f.str('name'), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5)),
                        subtitle: Text('${titleCase(f.str('role'))} · ${fmtBytes(f.intN('size_bytes'))}', style: const TextStyle(fontSize: 11.5)),
                        trailing: IconButton(
                          tooltip: 'Download',
                          icon: const Icon(Icons.download_rounded, size: 18),
                          onPressed: f.boolean('present') ? () => openUrl(_c.api.url(f.str('url'))) : null,
                        ),
                      ),
                  ],
                ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  IconData _fixtureIcon(String n) =>
      n.endsWith('.pdf') ? Icons.picture_as_pdf_outlined : (n.endsWith('.jpg') ? Icons.image_outlined : Icons.table_chart_outlined);

  Widget _stepBody() => switch (_c.step) {
    WizardStep.caseInfo => CaseStep(controller: _c),
    WizardStep.photo => PhotoStep(controller: _c),
    WizardStep.drawing => DrawingStep(controller: _c),
    WizardStep.expectedList => ListStep(controller: _c),
    WizardStep.configure => ConfigStep(controller: _c),
    WizardStep.validate => ValidateStep(controller: _c),
    WizardStep.run => RunStep(controller: _c),
  };

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final content = AnimatedSwitcher(
      duration: reduce ? Duration.zero : EE.med,
      switchInCurve: EE.curve,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.015, 0), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey('${_c.step}-${_c.inspection?.id}'), child: _stepBody()),
    );
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              eyebrow: 'Operate · New inspection',
              title: 'New Inspection',
              description:
                  'Create a case, upload the cabinet photograph, its GA drawing and the expected component / wire list, validate everything '
                  'against the backend, then run the drawing-aware inspection pipeline.',
              actions: [
                if (_c.isDemo) const DemoTag(),
                OutlinedButton.icon(onPressed: _showFixtures, icon: const Icon(Icons.folder_zip_outlined, size: 16), label: const Text('Fixture files')),
                if (!_c.hasCase)
                  FilledButton.tonalIcon(
                    onPressed: _loadingDemo ? null : _loadDemo,
                    icon: _loadingDemo
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.science_outlined, size: 16),
                    label: const Text('Use bundled demo fixtures'),
                  )
                else
                  OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt_rounded, size: 16), label: const Text('Start another case')),
              ],
            ),
            if (_c.isDemo) ...[
              const InlineError(
                'Demonstration case: the photo, drawing and lists are bundled SYNTHETIC fixtures (computer-generated, not a real cabinet). '
                'Running it executes the live pipeline on those files; results are flagged as demonstration data everywhere.',
                color: EE.violet,
                icon: Icons.science_outlined,
              ),
              const SizedBox(height: EE.s4),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: EE.surface,
                borderRadius: BorderRadius.circular(EE.r2),
                border: Border.all(color: EE.line),
              ),
              child: StepRail(controller: _c),
            ),
            const SizedBox(height: EE.s4),
            LayoutBuilder(
              builder: (context, cons) {
                if (cons.maxWidth < 1100) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      content,
                      const SizedBox(height: EE.s4),
                      SummaryRail(controller: _c),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: content),
                    const SizedBox(width: EE.s4),
                    SizedBox(width: 340, child: SummaryRail(controller: _c)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
