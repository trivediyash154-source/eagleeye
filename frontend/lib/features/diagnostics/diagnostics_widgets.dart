import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Shared building blocks for the diagnostics and health screens.

String dv(Object? v, {String suffix = ''}) {
  if (v == null) return '—';
  if (v is bool) return v ? 'yes' : 'no';
  if (v is double) return '${v.toStringAsFixed(v.abs() < 10 ? 3 : 1)}$suffix';
  final s = v.toString();
  return s.isEmpty ? '—' : '$s$suffix';
}

String prettyJson(Object? v) {
  try {
    return const JsonEncoder.withIndent('  ').convert(v);
  } catch (_) {
    return v.toString();
  }
}

/// Amber/red/cyan callout with an icon, used for limitations, caveats and honest notes.
class Callout extends StatelessWidget {
  const Callout({super.key, required this.child, this.color = EE.uncertain, this.icon = Icons.warning_amber_rounded, this.title});
  final Widget child;
  final Color color;
  final IconData icon;
  final String? title;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(EE.r2),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) ...[
                Text(title!, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
                const SizedBox(height: 4),
              ],
              DefaultTextStyle.merge(style: const TextStyle(fontSize: 12.5, height: 1.45, color: EE.text), child: child),
            ]),
          ),
        ]),
      );
}

/// Small labelled monospaced metric, denser than a KPI tile.
class MiniStat extends StatelessWidget {
  const MiniStat(this.label, this.value, {super.key, this.color = EE.text});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: EE.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 9.5, letterSpacing: 1.1, color: EE.textDim)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontFamily: EE.fontMono, fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

/// Human-readable meaning of a subsystem state, shared by the health grid and the legend.
const stateMeaning = <String, String>{
  'ok': 'Functioning — verified by a live check on the backend.',
  'degraded': 'Running with reduced capability (e.g. generic COCO weights without cabinet classes).',
  'loading': 'Model warm-up in progress; it will become available shortly.',
  'not_loaded': 'Installed but not yet loaded into memory. Loads on first use or via “Load models now”.',
  'unavailable': 'Dependency missing — package, weights or model files not installed or not downloadable.',
  'disabled': 'Turned off by configuration.',
  'error': 'The live check failed. See the message and the operational log.',
  'unsupported': 'Operation not supported by the currently loaded models.',
  'unknown': 'State unknown — the backend could not be reached.',
};

const stateLabels = <String, String>{
  'ok': 'Functioning',
  'degraded': 'Degraded',
  'loading': 'Loading',
  'not_loaded': 'Not loaded',
  'unavailable': 'Unavailable',
  'disabled': 'Disabled',
  'error': 'Error',
  'unsupported': 'Unsupported',
  'unknown': 'Unknown',
};

Color stateColor(String s) => switch (s) {
      'unsupported' => EE.violet,
      'unknown' => EE.textDim,
      _ => EE.state(s),
    };

/// Fixed-height scrollable table with a header row; used for detections, OCR regions and logs.
class DenseTable extends StatelessWidget {
  const DenseTable({super.key, required this.columns, required this.rows, this.flex, this.maxHeight = 260, this.empty = 'No rows'});
  final List<String> columns;
  final List<List<Widget>> rows;
  final List<int>? flex;
  final double maxHeight;
  final String empty;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> cells, {bool header = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: header ? EE.surfaceHi : null,
            border: const Border(bottom: BorderSide(color: EE.line)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < cells.length; i++) Expanded(flex: flex?[i] ?? 1, child: Padding(padding: const EdgeInsets.only(right: 8), child: cells[i])),
          ]),
        );
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row([
          for (final c in columns) Text(c.toUpperCase(), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 9.5, letterSpacing: 1.1, color: EE.textMuted)),
        ], header: true),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(14), child: Text(empty, style: const TextStyle(fontSize: 12.5, color: EE.textDim)))
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView.builder(shrinkWrap: true, itemCount: rows.length, itemBuilder: (_, i) => row(rows[i])),
          ),
      ]),
    );
  }
}

TextStyle get monoCell => const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.text);
TextStyle get cell => const TextStyle(fontSize: 12.5, color: EE.text);
