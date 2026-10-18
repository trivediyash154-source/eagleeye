import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme/tokens.dart';

class VerdictBadge extends StatelessWidget {
  const VerdictBadge(this.verdict, {super.key, this.dense = false, this.reviewed = false});
  final String verdict;
  final bool dense;
  final bool reviewed;

  @override
  Widget build(BuildContext context) {
    final c = EE.verdict(verdict);
    final icon = switch (verdict) { 'PASS' => Icons.check_rounded, 'FAIL' => Icons.close_rounded, 'UNCERTAIN' => Icons.help_outline_rounded, 'WAIVED' => Icons.remove_rounded, _ => Icons.circle_outlined };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(EE.r1),
        border: Border.all(color: c.withValues(alpha: 0.55)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: dense ? 11 : 13, color: c),
        const SizedBox(width: 4),
        Text(verdict, style: TextStyle(fontFamily: EE.fontMono, fontWeight: FontWeight.w600, fontSize: dense ? 10 : 11, letterSpacing: 0.6, color: c)),
        if (reviewed) ...[const SizedBox(width: 4), Icon(Icons.person_rounded, size: dense ? 10 : 12, color: c)],
      ]),
    );
  }
}

class StatePill extends StatelessWidget {
  const StatePill(this.state, {super.key, this.label, this.pulse = false});
  final String state;
  final String? label;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final c = EE.state(state);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      StatusDot(color: c, pulse: pulse || state == 'running' || state == 'loading'),
      const SizedBox(width: 6),
      Text(label ?? state.replaceAll('_', ' '), style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
    ]);
  }
}

class StatusDot extends StatefulWidget {
  const StatusDot({super.key, required this.color, this.pulse = false, this.size = 8});
  final Color color;
  final bool pulse;
  final double size;
  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant StatusDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.pulse && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2.2,
      height: widget.size * 2.2,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(alignment: Alignment.center, children: [
          if (widget.pulse)
            Container(
              width: widget.size * (1 + 1.2 * _c.value),
              height: widget.size * (1 + 1.2 * _c.value),
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.35 * (1 - _c.value))),
            ),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color, boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 8)]),
          ),
        ]),
      ),
    );
  }
}

class ReasonChip extends StatelessWidget {
  const ReasonChip(this.reason, {super.key});
  final String reason;
  @override
  Widget build(BuildContext context) => Tag(reasonLabels[reason] ?? reason.replaceAll('_', ' '), color: EE.uncertain);
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = EE.textMuted, this.icon, this.mono = false, this.filled = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool mono;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(EE.r1),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color, fontFamily: mono ? EE.fontMono : EE.fontBody)),
        ]),
      );
}

class DemoTag extends StatelessWidget {
  const DemoTag({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Demonstration inspection: inputs are bundled SYNTHETIC fixtures. Results were produced by the live pipeline.',
        child: Tag(compact ? 'DEMO' : 'DEMO · SYNTHETIC INPUTS', color: EE.violet, icon: Icons.science_outlined, filled: true),
      );
}

/// Monospaced value chip, e.g. an identifier or measurement.
class MonoValue extends StatelessWidget {
  const MonoValue(this.text, {super.key, this.color = EE.text, this.size = 12.5, this.strike = false});
  final String text;
  final Color color;
  final double size;
  final bool strike;
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(fontFamily: EE.fontMono, fontSize: size, color: color, fontWeight: FontWeight.w500, decoration: strike ? TextDecoration.lineThrough : null));
}
