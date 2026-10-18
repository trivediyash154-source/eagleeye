import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme/tokens.dart';

/// Shared building blocks for the Drawing, Detection and OCR analysis screens.

/// Original-frame photo of a version (all persisted coordinates refer to it).
class PhotoRef {
  const PhotoRef(this.url, this.size, this.evidenceId);
  final String url;
  final Size? size;
  final String evidenceId;
}

PhotoRef? mediaImage(ApiClient api, Json media, String kind) {
  final o = media.obj('items').objN(kind);
  if (o == null || o.strN('url') == null) return null;
  final w = o.intN('width'), h = o.intN('height');
  return PhotoRef(api.url(o.str('url')), (w != null && h != null) ? Size(w.toDouble(), h.toDouble()) : null, o.str('id'));
}

/// Two-pane analysis layout: a flexible visual area and a fixed-width side panel on wide
/// screens; stacked with a fixed-height visual on narrow screens.
class AnalysisLayout extends StatelessWidget {
  const AnalysisLayout({super.key, required this.visual, required this.side, this.leading, this.sideWidth = 380, this.breakpoint = 900, this.narrowVisualHeight = 440});
  final Widget visual;
  final Widget side;
  final Widget? leading;
  final double sideWidth;
  final double breakpoint;
  final double narrowVisualHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= breakpoint) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (leading != null) ...[SizedBox(width: 320, child: leading), const SizedBox(width: EE.s4)],
          Expanded(child: visual),
          const SizedBox(width: EE.s4),
          SizedBox(width: sideWidth, child: side),
        ]);
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: EE.s8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: math.min(narrowVisualHeight, math.max(300, c.maxWidth * 0.8)), child: visual),
          const SizedBox(height: EE.s4),
          side,
          if (leading != null) ...[const SizedBox(height: EE.s4), leading!],
        ]),
      );
    });
  }

}

/// Compact segmented control in the console style.
class SegToggle<T> extends StatelessWidget {
  const SegToggle({super.key, required this.values, required this.value, required this.onChanged, this.dense = false});
  final Map<T, String> values;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final e in values.entries)
          InkWell(
            borderRadius: BorderRadius.circular(EE.r1 + 2),
            onTap: () => onChanged(e.key),
            child: AnimatedContainer(
              duration: EE.fast,
              padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 11, vertical: dense ? 4 : 6),
              decoration: BoxDecoration(
                color: e.key == value ? EE.cyan.withValues(alpha: 0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(EE.r1 + 2),
                border: Border.all(color: e.key == value ? EE.cyan.withValues(alpha: 0.45) : Colors.transparent),
              ),
              child: Text(e.value, style: TextStyle(fontSize: dense ? 11.5 : 12, fontWeight: FontWeight.w600, color: e.key == value ? EE.cyan : EE.textMuted)),
            ),
          ),
      ]),
    );
  }
}

/// Horizontal confidence bar with an optional threshold tick.
class ConfidenceBar extends StatelessWidget {
  const ConfidenceBar({super.key, required this.value, this.threshold, this.color = EE.cyan, this.width = 90, this.showValue = true});
  final double value;
  final double? threshold;
  final Color color;
  final double width;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: width,
        height: 6,
        child: CustomPaint(painter: _BarPainter(v, threshold, color)),
      ),
      if (showValue) ...[
        const SizedBox(width: 8),
        Text(v.toStringAsFixed(2), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.text)),
      ],
    ]);
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.v, this.t, this.c);
  final double v;
  final double? t;
  final Color c;

  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(3));
    canvas.drawRRect(r, Paint()..color = EE.titanium);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s.width * v, s.height), const Radius.circular(3)), Paint()..color = c);
    if (t != null) {
      final x = s.width * t!.clamp(0.0, 1.0);
      canvas.drawLine(Offset(x, -2), Offset(x, s.height + 2), Paint()
        ..color = EE.text
        ..strokeWidth = 1.2);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter o) => o.v != v || o.t != t || o.c != c;
}

/// Honest notice banner (limitations, unavailable capabilities).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.title, this.lines = const [], this.color = EE.uncertain, this.icon = Icons.info_outline_rounded, this.trailing});
  final String title;
  final List<String> lines;
  final Color color;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(EE.r2),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
              for (final l in lines) Padding(padding: const EdgeInsets.only(top: 3), child: Text(l, style: const TextStyle(fontSize: 12, color: EE.textMuted, height: 1.45))),
            ]),
          ),
          ?trailing,
        ]),
      );
}

/// Small labelled switch row.
class ToggleRow extends StatelessWidget {
  const ToggleRow({super.key, required this.label, required this.value, required this.onChanged, this.hint});
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12.5)),
            if (hint != null) Text(hint!, style: const TextStyle(fontSize: 11, color: EE.textDim)),
          ]),
        ),
        Transform.scale(scale: 0.8, child: Switch(value: value, onChanged: onChanged)),
      ]);
}

/// Thin section label inside panels.
class SubHead extends StatelessWidget {
  const SubHead(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Row(children: [
          Expanded(child: Text(text.toUpperCase(), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10, letterSpacing: 1.4, color: EE.textDim))),
          ?trailing,
        ]),
      );
}

String fmtBox(List<double>? b, {int digits = 0}) => b == null || b.length < 4 ? '—' : '[${b.map((v) => v.toStringAsFixed(digits)).join(', ')}]';

List<double>? boxOf(Json j, String key) => j.box(key);

List<List<double>>? quadOf(Json j, String key) {
  final q = j[key];
  if (q is! List || q.isEmpty) return null;
  return q.map((p) => (p as List).map((v) => (v as num).toDouble()).toList()).toList();
}

// ---------------------------------------------------------------------------
// Identifier normalisation and character-level comparison (mirrors backend rules)
// ---------------------------------------------------------------------------

const _dashes = '‐‑‒–—―−﹣－_~';
const confusableGroups = [
  {'0', 'O', 'D', 'Q'},
  {'1', 'I', 'L', '7'},
  {'2', 'Z'},
  {'5', 'S'},
  {'8', 'B'},
  {'6', 'G'},
];

String normalizeIdentifier(String raw) {
  var s = raw.trim().toUpperCase();
  s = s.split('').map((c) => _dashes.contains(c) ? '-' : c).join();
  const edge = " .,;:'\"|`!()[]{}";
  var a = 0, b = s.length;
  while (a < b && edge.contains(s[a])) {
    a++;
  }
  while (b > a && edge.contains(s[b - 1])) {
    b--;
  }
  s = s.substring(a, b).replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'-{2,}'), '-');
  return s;
}

bool areConfusable(String a, String b) => a != b && confusableGroups.any((g) => g.contains(a) && g.contains(b));

enum DiffOp { match, substitute, missing, extra }

class DiffCell {
  const DiffCell(this.op, this.expected, this.observed);
  final DiffOp op;
  final String? expected;
  final String? observed;
  bool get confusable => op == DiffOp.substitute && areConfusable(expected!, observed!);
}

/// Levenshtein alignment between expected and observed (both normalised).
List<DiffCell> alignChars(String expected, String observed) {
  final e = expected.split(''), o = observed.split('');
  final n = e.length, m = o.length;
  final d = List.generate(n + 1, (i) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final cost = e[i - 1] == o[j - 1] ? 0 : 1;
      d[i][j] = math.min(math.min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + cost);
    }
  }
  final out = <DiffCell>[];
  var i = n, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && d[i][j] == d[i - 1][j - 1] + (e[i - 1] == o[j - 1] ? 0 : 1)) {
      out.add(DiffCell(e[i - 1] == o[j - 1] ? DiffOp.match : DiffOp.substitute, e[i - 1], o[j - 1]));
      i--;
      j--;
    } else if (i > 0 && d[i][j] == d[i - 1][j] + 1) {
      out.add(DiffCell(DiffOp.missing, e[i - 1], null));
      i--;
    } else {
      out.add(DiffCell(DiffOp.extra, null, o[j - 1]));
      j--;
    }
  }
  return out.reversed.toList();
}

/// Two aligned monospace rows (expected / observed) with per-character highlighting.
class CharDiff extends StatelessWidget {
  const CharDiff({super.key, required this.expected, required this.observed});
  final String expected;
  final String observed;

  @override
  Widget build(BuildContext context) {
    final cells = alignChars(normalizeIdentifier(expected), normalizeIdentifier(observed));
    final edits = cells.where((c) => c.op != DiffOp.match).length;
    Widget cell(String? ch, DiffCell c, bool top) {
      Color border = EE.line, bg = EE.bg1, fg = EE.text;
      switch (c.op) {
        case DiffOp.match:
          break;
        case DiffOp.substitute:
          final col = c.confusable ? EE.uncertain : EE.fail;
          border = col;
          bg = col.withValues(alpha: 0.14);
          fg = col;
        case DiffOp.missing:
        case DiffOp.extra:
          border = EE.fail.withValues(alpha: 0.7);
          bg = EE.fail.withValues(alpha: 0.08);
          fg = EE.fail;
      }
      return Container(
        width: 22,
        height: 26,
        margin: const EdgeInsets.all(1.5),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3), border: Border.all(color: border)),
        child: Text(ch ?? '∅', style: TextStyle(fontFamily: EE.fontMono, fontSize: 13, fontWeight: FontWeight.w600, color: ch == null ? EE.textDim : fg)),
      );
    }

    Widget row(String label, bool top) => Row(children: [
          SizedBox(width: 68, child: Text(label, style: const TextStyle(fontSize: 11, color: EE.textDim))),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final c in cells) cell(top ? c.expected : c.observed, c, top)]),
            ),
          ),
        ]);
    final confusable = cells.where((c) => c.confusable).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      row('Expected', true),
      const SizedBox(height: 2),
      row('Observed', false),
      const SizedBox(height: 6),
      Text(
        edits == 0
            ? 'Exact match after normalisation (d = 0).'
            : 'Levenshtein d = $edits'
                '${confusable.isNotEmpty ? ' · confusable: ${confusable.map((c) => '${c.expected}↔${c.observed}').join(', ')}' : ''}'
                '${cells.any((c) => c.op == DiffOp.substitute && !c.confusable) ? ' · non-confusable substitution present' : ''}',
        style: const TextStyle(fontSize: 11.5, color: EE.textMuted),
      ),
    ]);
  }
}

String worstVerdict(Iterable<String> verdicts) {
  if (verdicts.contains('FAIL')) return 'FAIL';
  if (verdicts.contains('UNCERTAIN')) return 'UNCERTAIN';
  if (verdicts.contains('PASS')) return 'PASS';
  if (verdicts.contains('WAIVED')) return 'WAIVED';
  return '';
}
