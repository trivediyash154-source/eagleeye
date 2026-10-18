import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/tokens.dart';

/// Shared chart widgets for EAGLE EYE. Every value shown comes from the caller; nothing is
/// synthesised here. Entrance animations are short and disabled under reduced motion.

bool _reduce(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

Duration _dur(BuildContext context) => _reduce(context) ? Duration.zero : const Duration(milliseconds: 650);

const _axisStyle = TextStyle(fontFamily: EE.fontMono, fontSize: 10, color: EE.textDim);

const verdictOrder = ['PASS', 'FAIL', 'UNCERTAIN', 'WAIVED'];

// ---------------------------------------------------------------------------
// Legend
// ---------------------------------------------------------------------------

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label, this.value, this.square = false});
  final Color color;
  final String label;
  final String? value;
  final bool square;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: square ? BoxShape.rectangle : BoxShape.circle, borderRadius: square ? BorderRadius.circular(2) : null),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11.5, color: EE.textMuted)),
        if (value != null) ...[
          const SizedBox(width: 6),
          Text(value!, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.text, fontWeight: FontWeight.w600)),
        ],
      ]);
}

// ---------------------------------------------------------------------------
// Verdict donut
// ---------------------------------------------------------------------------

/// Donut of PASS / FAIL / UNCERTAIN (/ WAIVED) counts with the total in the centre.
class VerdictDonut extends StatefulWidget {
  const VerdictDonut({super.key, required this.counts, this.size = 190, this.centerLabel = 'FINDINGS', this.onTap});
  final Map<String, int> counts;
  final double size;
  final String centerLabel;
  final ValueChanged<String>? onTap;

  @override
  State<VerdictDonut> createState() => _VerdictDonutState();
}

class _VerdictDonutState extends State<VerdictDonut> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final keys = verdictOrder.where((k) => (widget.counts[k] ?? 0) > 0).toList();
    final total = widget.counts.values.fold<int>(0, (a, b) => a + b);
    final ring = widget.size * 0.13;
    final sections = total == 0
        ? [PieChartSectionData(value: 1, color: EE.titanium, radius: ring, showTitle: false)]
        : [
            for (var i = 0; i < keys.length; i++)
              PieChartSectionData(
                value: (widget.counts[keys[i]] ?? 0).toDouble(),
                color: EE.verdict(keys[i]).withValues(alpha: _touched == null || _touched == i ? 1 : 0.45),
                radius: _touched == i ? ring + 6 : ring,
                showTitle: false,
                borderSide: BorderSide(color: EE.bg0.withValues(alpha: 0.6), width: 1),
              ),
          ];
    final touchedKey = _touched != null && _touched! < keys.length ? keys[_touched!] : null;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(alignment: Alignment.center, children: [
        PieChart(
          PieChartData(
            sections: sections,
            centerSpaceRadius: widget.size / 2 - ring - 8,
            sectionsSpace: total == 0 ? 0 : 2,
            startDegreeOffset: -90,
            borderData: FlBorderData(show: false),
            pieTouchData: PieTouchData(
              enabled: total > 0,
              touchCallback: (event, resp) {
                final idx = resp?.touchedSection?.touchedSectionIndex;
                if (event is FlTapUpEvent && idx != null && idx >= 0 && idx < keys.length) widget.onTap?.call(keys[idx]);
                final next = (event.isInterestedForInteractions && idx != null && idx >= 0) ? idx : null;
                if (next != _touched) setState(() => _touched = next);
              },
            ),
          ),
          duration: _dur(context),
          curve: EE.curve,
        ),
        IgnorePointer(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              touchedKey == null ? '$total' : '${widget.counts[touchedKey]}',
              style: TextStyle(
                fontFamily: EE.fontDisplay,
                fontSize: widget.size * 0.17,
                fontWeight: FontWeight.w600,
                height: 1,
                letterSpacing: -1,
                color: touchedKey == null ? EE.text : EE.verdict(touchedKey),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              touchedKey == null ? widget.centerLabel : '$touchedKey · ${total == 0 ? 0 : ((widget.counts[touchedKey] ?? 0) * 100 / total).round()}%',
              style: const TextStyle(fontFamily: EE.fontMono, fontSize: 9.5, letterSpacing: 1.2, color: EE.textMuted),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Legend rows for verdict counts with percentages.
class VerdictLegend extends StatelessWidget {
  const VerdictLegend({super.key, required this.counts, this.includeWaived = true});
  final Map<String, int> counts;
  final bool includeWaived;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final keys = verdictOrder.where((k) => includeWaived || k != 'WAIVED').where((k) => k != 'WAIVED' || (counts[k] ?? 0) > 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (final k in keys)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 3, height: 22, decoration: BoxDecoration(color: EE.verdict(k), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            SizedBox(width: 92, child: Text(k, style: TextStyle(fontFamily: EE.fontMono, fontSize: 11, letterSpacing: 0.8, color: EE.verdict(k), fontWeight: FontWeight.w600))),
            SizedBox(
              width: 44,
              child: Text('${counts[k] ?? 0}', textAlign: TextAlign.right, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 13, fontWeight: FontWeight.w600, color: EE.text)),
            ),
            SizedBox(
              width: 52,
              child: Text(total == 0 ? '—' : '${((counts[k] ?? 0) * 100 / total).toStringAsFixed(0)}%',
                  textAlign: TextAlign.right, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim)),
            ),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Volume time series (stacked bars per day)
// ---------------------------------------------------------------------------

class VolumePoint {
  const VolumePoint({required this.date, required this.runs, required this.completed, required this.failed});
  final DateTime date;
  final int runs, completed, failed;
  int get other => math.max(0, runs - completed - failed);
  String get key => DateFormat('yyyy-MM-dd').format(date);
}

/// Fills every day in [from]..[to] (inclusive) so empty days appear as gaps.
List<VolumePoint> fillDays(List<Map<String, dynamic>> raw, DateTime from, DateTime to) {
  final byKey = {for (final r in raw) r['date'] as String: r};
  final out = <VolumePoint>[];
  var d = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  var guard = 0;
  while (!d.isAfter(end) && guard < 800) {
    final k = DateFormat('yyyy-MM-dd').format(d);
    final r = byKey[k];
    out.add(VolumePoint(
      date: d,
      runs: (r?['runs'] as num?)?.toInt() ?? 0,
      completed: (r?['completed'] as num?)?.toInt() ?? 0,
      failed: (r?['failed'] as num?)?.toInt() ?? 0,
    ));
    d = DateTime(d.year, d.month, d.day + 1);
    guard++;
  }
  return out;
}

class VolumeChart extends StatelessWidget {
  const VolumeChart({super.key, required this.points, this.selectedKey, this.onSelectDay, this.height = 220});
  final List<VolumePoint> points;
  final String? selectedKey;
  final ValueChanged<VolumePoint>? onSelectDay;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxY = points.fold<int>(0, (m, p) => math.max(m, p.runs));
    final top = maxY <= 4 ? 4.0 : (maxY * 1.2).ceilToDouble();
    final n = points.length;
    final barW = n <= 14 ? 14.0 : (n <= 31 ? 8.0 : (n <= 90 ? 4.0 : 2.5));
    final labelEvery = n <= 10 ? 1 : (n <= 31 ? 5 : (n <= 90 ? 14 : 30));
    final interval = top <= 5 ? 1.0 : (top / 4).ceilToDouble();
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: top,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: true, border: const Border(bottom: BorderSide(color: EE.lineHi))),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => const FlLine(color: EE.line, strokeWidth: 1, dashArray: [3, 4]),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: interval,
                getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(v.toInt().toString(), style: _axisStyle)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= n || (i % labelEvery != 0 && i != n - 1)) return const SizedBox.shrink();
                  return SideTitleWidget(meta: meta, child: Text(DateFormat('d MMM').format(points[i].date), style: _axisStyle));
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => EE.surfaceTop,
              tooltipBorder: const BorderSide(color: EE.lineHi),
              tooltipBorderRadius: BorderRadius.circular(EE.r1),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, gi, rod, ri) {
                final p = points[group.x];
                return BarTooltipItem(
                  '${DateFormat('EEE d MMM').format(p.date)}\n',
                  const TextStyle(fontFamily: EE.fontBody, fontSize: 11.5, color: EE.text, fontWeight: FontWeight.w600),
                  children: [
                    TextSpan(text: '${p.runs} run${p.runs == 1 ? '' : 's'}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.cyan)),
                    if (p.failed > 0) TextSpan(text: ' · ${p.failed} failed', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.fail)),
                    if (p.other > 0) TextSpan(text: ' · ${p.other} other', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textMuted)),
                  ],
                );
              },
            ),
            touchCallback: (event, resp) {
              if (event is FlTapUpEvent && resp?.spot != null && onSelectDay != null) {
                onSelectDay!(points[resp!.spot!.touchedBarGroupIndex]);
              }
            },
          ),
          barGroups: [
            for (var i = 0; i < n; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: points[i].runs.toDouble(),
                  width: barW,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                  color: EE.cyan,
                  rodStackItems: [
                    BarChartRodStackItem(0, points[i].completed.toDouble(), _sel(EE.cyan, i)),
                    BarChartRodStackItem(points[i].completed.toDouble(), (points[i].completed + points[i].failed).toDouble(), _sel(EE.fail, i)),
                    BarChartRodStackItem((points[i].completed + points[i].failed).toDouble(), points[i].runs.toDouble(), _sel(EE.textDim, i)),
                  ],
                  backDrawRodData: BackgroundBarChartRodData(
                    show: points[i].key == selectedKey,
                    toY: top,
                    color: EE.cyan.withValues(alpha: 0.10),
                  ),
                ),
              ]),
          ],
        ),
        duration: _dur(context),
        curve: EE.curve,
      ),
    );
  }

  Color _sel(Color c, int i) => selectedKey == null || points[i].key == selectedKey ? c : c.withValues(alpha: 0.35);
}

// ---------------------------------------------------------------------------
// Horizontal bars
// ---------------------------------------------------------------------------

class BarItem {
  const BarItem(this.label, this.value, {this.color = EE.cyan, this.sub, this.mono = false, this.trailing});
  final String label;
  final num value;
  final Color color;
  final String? sub;
  final bool mono;
  final String? trailing;
}

/// Horizontal bar list with labels left and values right. Bars scale to the largest value.
class HBarList extends StatelessWidget {
  const HBarList({super.key, required this.items, this.labelWidth = 130, this.onTap, this.maxValue, this.valueFormat});
  final List<BarItem> items;
  final double labelWidth;
  final ValueChanged<BarItem>? onTap;
  final num? maxValue;
  final String Function(num v)? valueFormat;

  @override
  Widget build(BuildContext context) {
    final maxV = maxValue ?? items.fold<num>(0, (m, e) => math.max(m, e.value));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final it in items)
        InkWell(
          onTap: onTap == null ? null : () => onTap!(it),
          borderRadius: BorderRadius.circular(EE.r1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(
                width: labelWidth,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(it.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: it.mono ? EE.fontMono : EE.fontBody, fontSize: it.mono ? 11.5 : 12, color: EE.text)),
                  if (it.sub != null) Text(it.sub!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: EE.textDim)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(child: _AnimatedBar(fraction: maxV <= 0 ? 0 : (it.value / maxV).toDouble(), color: it.color)),
              const SizedBox(width: 10),
              SizedBox(
                width: 54,
                child: Text(it.trailing ?? (valueFormat?.call(it.value) ?? '${it.value}'),
                    textAlign: TextAlign.right, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, fontWeight: FontWeight.w600, color: EE.text)),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _AnimatedBar extends StatelessWidget {
  const _AnimatedBar({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
      duration: _dur(context),
      curve: EE.curve,
      builder: (context, f, _) => LayoutBuilder(builder: (context, c) {
        return Container(
          height: 8,
          decoration: BoxDecoration(color: EE.titanium.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2)),
          alignment: Alignment.centerLeft,
          child: Container(
            width: c.maxWidth * f,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.55), color]),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 6)],
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Stacked verdict bars per category
// ---------------------------------------------------------------------------

class StackRow {
  const StackRow(this.label, this.counts, {this.sub});
  final String label;
  final Map<String, int> counts;
  final String? sub;
  int get total => counts.values.fold(0, (a, b) => a + b);
}

/// Horizontal stacked bars (PASS/FAIL/UNCERTAIN/WAIVED) normalised to the largest row total.
class StackedVerdictBars extends StatelessWidget {
  const StackedVerdictBars({super.key, required this.rows, this.labelWidth = 150});
  final List<StackRow> rows;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final maxT = rows.fold<int>(0, (m, r) => math.max(m, r.total));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(
              width: labelWidth,
              child: Text(r.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: EE.text)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: maxT == 0 ? 0 : r.total / maxT),
                duration: _dur(context),
                curve: EE.curve,
                builder: (context, f, _) => LayoutBuilder(builder: (context, c) {
                  final w = c.maxWidth * f;
                  return Container(
                    height: 10,
                    decoration: BoxDecoration(color: EE.titanium.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        width: w,
                        child: Row(children: [
                          for (final k in verdictOrder)
                            if ((r.counts[k] ?? 0) > 0)
                              Expanded(
                                flex: r.counts[k]!,
                                child: Tooltip(
                                  message: '$k: ${r.counts[k]}',
                                  child: Container(margin: const EdgeInsets.only(right: 1), color: EE.verdict(k)),
                                ),
                              ),
                        ]),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 96,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                for (final k in const ['PASS', 'FAIL', 'UNCERTAIN'])
                  SizedBox(
                    width: 30,
                    child: Text('${r.counts[k] ?? 0}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: EE.fontMono,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: (r.counts[k] ?? 0) == 0 ? EE.textDim : EE.verdict(k),
                        )),
                  ),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Histogram
// ---------------------------------------------------------------------------

class HistBin {
  const HistBin(this.label, this.count);
  final String label;
  final int count;
}

class Histogram extends StatelessWidget {
  const Histogram({super.key, required this.bins, this.height = 200, this.color = EE.cyan, this.unit = 'runs'});
  final List<HistBin> bins;
  final double height;
  final Color color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final maxY = bins.fold<int>(0, (m, b) => math.max(m, b.count));
    final top = maxY <= 4 ? 4.0 : (maxY * 1.2).ceilToDouble();
    final interval = top <= 5 ? 1.0 : (top / 4).ceilToDouble();
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: top,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: true, border: const Border(bottom: BorderSide(color: EE.lineHi))),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => const FlLine(color: EE.line, strokeWidth: 1, dashArray: [3, 4]),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: interval,
                getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(v.toInt().toString(), style: _axisStyle)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= bins.length) return const SizedBox.shrink();
                  return SideTitleWidget(meta: meta, angle: bins.length > 8 ? -0.5 : 0, child: Text(bins[i].label, style: _axisStyle.copyWith(fontSize: 9)));
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => EE.surfaceTop,
              tooltipBorder: const BorderSide(color: EE.lineHi),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                '${bins[g.x].label}\n',
                const TextStyle(fontSize: 11.5, color: EE.text, fontWeight: FontWeight.w600),
                children: [TextSpan(text: '${bins[g.x].count} $unit', style: TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: color))],
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < bins.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: bins[i].count.toDouble(),
                  width: bins.length > 8 ? 14 : 22,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [color.withValues(alpha: 0.45), color]),
                ),
              ]),
          ],
        ),
        duration: _dur(context),
        curve: EE.curve,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ratio gauge
// ---------------------------------------------------------------------------

/// Arc gauge for a 0..1 ratio. `null` renders an explicit "no data" state.
class RatioGauge extends StatelessWidget {
  const RatioGauge({super.key, required this.value, required this.label, this.sub, this.color = EE.cyan, this.size = 132, this.invert = false});
  final double? value;
  final String label;
  final String? sub;
  final Color color;
  final double size;

  /// When true the gauge reads "lower is better" (only affects the caption).
  final bool invert;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: size,
        height: size * 0.72,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: (value ?? 0).clamp(0.0, 1.0)),
          duration: _dur(context),
          curve: EE.curve,
          builder: (context, v, _) => CustomPaint(
            painter: _GaugePainter(value == null ? null : v, color),
            child: Align(
              alignment: const Alignment(0, 0.35),
              child: Text(
                value == null ? '—' : '${(value! * 100).toStringAsFixed(value! < 0.1 && value! > 0 ? 1 : 0)}%',
                style: TextStyle(fontFamily: EE.fontDisplay, fontSize: size * 0.2, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: value == null ? EE.textDim : EE.text),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(label.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 9.5, letterSpacing: 1.2, color: EE.textMuted)),
      if (sub != null) ...[
        const SizedBox(height: 3),
        Text(sub!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: EE.textDim)),
      ],
    ]);
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.v, this.color);
  final double? v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width / 2, size.height / 0.86) - 8;
    final c = Offset(size.width / 2, r + 8);
    const start = math.pi * 0.83;
    const sweep = math.pi * 1.34;
    final rect = Rect.fromCircle(center: c, radius: r);
    final track = Paint()
      ..color = EE.titanium
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, track);
    // tick marks
    final tick = Paint()
      ..color = EE.lineHi
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final a = start + sweep * i / 10;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * (r - 9);
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (r - (i % 5 == 0 ? 15 : 12));
      canvas.drawLine(p1, p2, tick);
    }
    if (v != null && v! > 0) {
      final arc = Paint()
        ..shader = SweepGradient(startAngle: start, endAngle: start + sweep, colors: [color.withValues(alpha: 0.5), color], transform: const GradientRotation(0)).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep * v!, false, arc);
      final glow = Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawArc(rect, start, sweep * v!, false, glow);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.v != v || old.color != color;
}

// ---------------------------------------------------------------------------
// Segmented selector (dataset / range toggles)
// ---------------------------------------------------------------------------

class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged, this.tooltips});
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Map<T, String>? tooltips;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final e in options.entries)
          Tooltip(
            message: tooltips?[e.key] ?? '',
            child: InkWell(
              borderRadius: BorderRadius.circular(EE.r1 + 2),
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: EE.fast,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: e.key == value ? EE.cyan.withValues(alpha: 0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(EE.r1 + 2),
                  border: Border.all(color: e.key == value ? EE.cyan.withValues(alpha: 0.45) : Colors.transparent),
                ),
                child: Text(e.value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: e.key == value ? EE.cyan : EE.textMuted,
                    )),
              ),
            ),
          ),
      ]),
    );
  }
}
