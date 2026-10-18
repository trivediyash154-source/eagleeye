import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Thin-bordered titanium panel with an optional technical header.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.title,
    this.eyebrow,
    this.actions = const [],
    this.padding = const EdgeInsets.all(EE.s4),
    this.accent,
    this.expand = false,
    this.subtitle,
  });

  final Widget child;
  final String? title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  final EdgeInsets padding;
  final Color? accent;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final header = title == null && eyebrow == null
        ? null
        : Padding(
            padding: EdgeInsets.fromLTRB(padding.left, EE.s3 + 2, padding.right - 4, EE.s2),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (eyebrow != null) Eyebrow(eyebrow!, color: accent),
                  if (title != null) ...[
                    if (eyebrow != null) const SizedBox(height: 3),
                    Text(title!, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                  ],
                  if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall)),
                ]),
              ),
              ...actions,
            ]),
          );
    final body = Padding(padding: header == null ? padding : padding.copyWith(top: EE.s1), child: child);
    return Container(
      decoration: BoxDecoration(
        gradient: EE.panelGradient,
        borderRadius: BorderRadius.circular(EE.r3),
        border: Border.all(color: (accent ?? EE.line).withValues(alpha: accent == null ? 1 : 0.45)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          ?header,
          if (expand) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: color ?? EE.cyan),
      );
}

/// Page header used by every console screen.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.eyebrow, this.description, this.actions = const []});
  final String title;
  final String? eyebrow;
  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (eyebrow != null) ...[Eyebrow(eyebrow!), const SizedBox(height: 8)],
      Text(title, style: Theme.of(context).textTheme.headlineLarge),
      if (description != null) ...[
        const SizedBox(height: 8),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: Text(description!, style: Theme.of(context).textTheme.bodyLarge)),
      ],
    ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: EE.s6),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, if (actions.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: actions)]])
          : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: text), Wrap(spacing: 8, runSpacing: 8, children: actions)]),
    );
  }
}

/// Key/value row for dense technical detail.
class KV extends StatelessWidget {
  const KV(this.k, this.v, {super.key, this.mono = false, this.valueColor, this.keyWidth = 150});
  final String k;
  final String? v;
  final bool mono;
  final Color? valueColor;
  final double keyWidth;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: keyWidth, child: Text(k, style: const TextStyle(fontSize: 12, color: EE.textDim))),
          Expanded(
            child: SelectableText(
              (v == null || v!.isEmpty) ? '—' : v!,
              style: TextStyle(fontSize: mono ? 12 : 12.5, fontFamily: mono ? EE.fontMono : EE.fontBody, color: valueColor ?? EE.text),
            ),
          ),
        ]),
      );
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.vertical = 10});
  final double vertical;
  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.symmetric(vertical: vertical), child: const Divider());
}

/// Responsive helper: lays children in a row on wide screens and a column on narrow ones.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({super.key, required this.children, this.breakpoint = 1100, this.gap = EE.s4, this.flex});
  final List<Widget> children;
  final double breakpoint;
  final double gap;
  final List<int>? flex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(width: gap), Expanded(flex: flex?[i] ?? 1, child: children[i])],
      ]);
    });
  }
}
