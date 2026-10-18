import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/panel.dart';
import 'wizard_controller.dart';

/// Frame shared by every wizard step: numbered header, body and back/continue bar.
class StepFrame extends StatelessWidget {
  const StepFrame({
    super.key,
    required this.controller,
    required this.description,
    required this.child,
    this.primaryLabel = 'Continue',
    this.onPrimary,
    this.primaryBusy = false,
    this.secondary,
    this.showBack = true,
    this.trailingHeader,
  });

  final WizardController controller;
  final String description;
  final Widget child;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryBusy;
  final Widget? secondary;
  final bool showBack;
  final Widget? trailingHeader;

  @override
  Widget build(BuildContext context) {
    final s = controller.step;
    return Panel(
      padding: const EdgeInsets.all(EE.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow('Step ${(s.index + 1).toString().padLeft(2, '0')} / ${WizardStep.values.length.toString().padLeft(2, '0')}'),
                    const SizedBox(height: 6),
                    Text(s.title, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    Text(description, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              ?trailingHeader,
            ],
          ),
          const SizedBox(height: EE.s5),
          child,
          const SizedBox(height: EE.s5),
          const Divider(),
          const SizedBox(height: EE.s4),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (showBack && s.index > 0)
                OutlinedButton.icon(onPressed: controller.back, icon: const Icon(Icons.arrow_back_rounded, size: 16), label: const Text('Back'))
              else
                const SizedBox(),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ?secondary,
                  if (onPrimary != null || primaryBusy)
                    FilledButton.icon(
                      onPressed: primaryBusy ? null : onPrimary,
                      icon: primaryBusy
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: EE.textDim))
                          : const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: Text(primaryLabel),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key, this.color = EE.fail, this.icon = Icons.error_outline_rounded});
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(EE.r2),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: SelectableText(message, style: TextStyle(fontSize: 12.5, color: color, height: 1.4)),
        ),
      ],
    ),
  );
}

/// Small labelled measurement (e.g. "SHARPNESS 410.3").
class Metric extends StatelessWidget {
  const Metric(this.label, this.value, {super.key, this.color = EE.text, this.hint});
  final String label;
  final String value;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: EE.bg1,
        borderRadius: BorderRadius.circular(EE.r2),
        border: Border.all(color: EE.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(fontFamily: EE.fontMono, fontSize: 9.5, letterSpacing: 1.2, color: EE.textDim),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontFamily: EE.fontMono, fontSize: 13.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
    return hint == null ? body : Tooltip(message: hint!, child: body);
  }
}

class SubHeading extends StatelessWidget {
  const SubHeading(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, letterSpacing: 1.4, color: EE.textMuted, fontWeight: FontWeight.w600),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
