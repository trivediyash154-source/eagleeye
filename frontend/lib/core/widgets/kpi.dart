import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class Kpi extends StatelessWidget {
  const Kpi({super.key, required this.label, required this.value, this.sub, this.accent = EE.cyan, this.icon, this.onTap});
  final String label;
  final String value;
  final String? sub;
  final Color accent;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _Hover(
      onTap: onTap,
      builder: (hover) => AnimatedContainer(
        duration: EE.fast,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: hover ? EE.surfaceHi : EE.surface,
          borderRadius: BorderRadius.circular(EE.r2),
          border: Border.all(color: hover ? accent.withValues(alpha: 0.5) : EE.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(width: 3, height: 12, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10, letterSpacing: 1.2, color: EE.textMuted))),
            if (icon != null) Icon(icon, size: 14, color: EE.textDim),
          ]),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontFamily: EE.fontDisplay, fontSize: 30, fontWeight: FontWeight.w600, height: 1, letterSpacing: -0.8, color: EE.text)),
          ),
          if (sub != null) ...[const SizedBox(height: 6), Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: EE.textDim))],
        ]),
      ),
    );
  }
}

class _Hover extends StatefulWidget {
  const _Hover({required this.builder, this.onTap});
  final Widget Function(bool hover) builder;
  final VoidCallback? onTap;
  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(onTap: widget.onTap, child: widget.builder(_h && widget.onTap != null)),
      );
}

/// Grid of KPI tiles that reflows by width.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children, this.minTileWidth = 190});
  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / minTileWidth).floor().clamp(1, children.length);
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}
