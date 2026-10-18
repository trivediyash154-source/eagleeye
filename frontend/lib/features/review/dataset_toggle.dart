import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';

/// Segmented switch between real inspections, demonstration inspections, or both.
class DatasetToggle extends ConsumerWidget {
  const DatasetToggle({super.key});

  static const _options = [('all', 'All data'), ('real', 'Real'), ('demo', 'Demo')];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(datasetProvider);
    return Tooltip(
      message: 'Demonstration inspections use bundled synthetic fixtures and are kept separate from real inspections.',
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (key, label) in _options)
            InkWell(
              borderRadius: BorderRadius.circular(EE.r1),
              onTap: () => ref.read(datasetProvider.notifier).set(key),
              child: AnimatedContainer(
                duration: EE.fast,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: current == key ? EE.cyan.withValues(alpha: 0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(EE.r1),
                  border: Border.all(color: current == key ? EE.cyan.withValues(alpha: 0.45) : Colors.transparent),
                ),
                child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: current == key ? EE.text : EE.textMuted)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Compact segmented selector for local view options.
class SegmentedPicker<T> extends StatelessWidget {
  const SegmentedPicker({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String, IconData?)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, label, icon) in options)
            InkWell(
              borderRadius: BorderRadius.circular(EE.r1),
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: EE.fast,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: v == value ? EE.cyan.withValues(alpha: 0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(EE.r1),
                  border: Border.all(color: v == value ? EE.cyan.withValues(alpha: 0.45) : Colors.transparent),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, size: 14, color: v == value ? EE.cyan : EE.textMuted), const SizedBox(width: 6)],
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: v == value ? EE.text : EE.textMuted)),
                ]),
              ),
            ),
        ]),
      );
}
