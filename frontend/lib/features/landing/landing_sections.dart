import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';

bool _reduced(BuildContext c) => MediaQuery.maybeDisableAnimationsOf(c) ?? false;

class _Section extends StatelessWidget {
  const _Section({required this.index, required this.eyebrow, required this.title, this.lead, required this.child});
  final String index;
  final String eyebrow;
  final String title;
  final String? lead;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w >= 1100 ? 96.0 : (w >= 700 ? 40.0 : 20.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, w >= 700 ? 110 : 64, pad, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(index, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.cyan, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Container(width: 36, height: 1, color: EE.cyan.withValues(alpha: 0.6)),
              const SizedBox(width: 12),
              Text(eyebrow.toUpperCase(), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, letterSpacing: 2.2, color: EE.textMuted)),
            ]),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Text(title, style: TextStyle(fontFamily: EE.fontDisplay, fontSize: w >= 900 ? 42 : 30, height: 1.12, fontWeight: FontWeight.w600, letterSpacing: -1, color: EE.text)),
            ),
            if (lead != null) ...[
              const SizedBox(height: 16),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: Text(lead!, style: const TextStyle(fontSize: 16.5, height: 1.6, color: EE.textMuted))),
            ],
            const SizedBox(height: 44),
            child,
          ]),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.label, this.padding = EdgeInsets.zero});
  final Widget child;
  final String? label;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: EE.surface.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(EE.r3),
          border: Border.all(color: EE.lineHi),
          boxShadow: [BoxShadow(color: EE.cyan.withValues(alpha: 0.05), blurRadius: 40, spreadRadius: 2)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (label != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: EE.line))),
              child: Text(label!, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, letterSpacing: 1.4, color: EE.textMuted)),
            ),
          Padding(padding: padding, child: child),
        ]),
      );
}

// --- A. Problem ---------------------------------------------------------------------------

class ProblemSection extends StatelessWidget {
  const ProblemSection({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    const pains = [
      (Icons.compare_arrows_rounded, 'Drawing versus cabinet, by eye', 'Inspectors compare a General Arrangement drawing with the physical cabinet manually, one part and one label at a time.'),
      (Icons.grid_view_rounded, 'Hundreds of small details', 'Breakers, contactors, device labels, ferrules, terminals and wire colours — each one a chance for a missed discrepancy.'),
      (Icons.psychology_alt_outlined, 'Hard to reproduce', 'Two inspectors can reach different conclusions on the same cabinet; fatigue makes late checks less reliable than early ones.'),
      (Icons.history_toggle_off_rounded, 'No audit trail', 'A ticked checklist does not show what was actually seen. Faults found at commissioning are hard to trace back.'),
    ];
    final list = Column(children: [
      for (final (icon, t, d) in pains)
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(border: Border.all(color: EE.lineHi), borderRadius: BorderRadius.circular(EE.r2), color: EE.surfaceHi),
              child: Icon(icon, size: 18, color: EE.ice),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(d, style: const TextStyle(fontSize: 13.5, height: 1.55, color: EE.textMuted)),
              ]),
            ),
          ]),
        ),
    ]);
    final visual = _Frame(
      label: 'GA DRAWING  ⟷  CABINET PHOTOGRAPH   ·   ILLUSTRATIVE (SYNTHETIC FIXTURE)',
      child: AspectRatio(
        aspectRatio: 1.45,
        child: LayoutBuilder(builder: (context, c) {
          return Stack(children: [
            Positioned(left: 0, top: 0, width: c.maxWidth * 0.62, height: c.maxHeight * 0.66, child: Image.asset('assets/landing/ga_full.png', fit: BoxFit.cover)),
            Positioned(
              right: 0,
              bottom: 0,
              width: c.maxWidth * 0.6,
              height: c.maxHeight * 0.62,
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: EE.lineHi, width: 2)),
                child: Image.asset('assets/landing/photo_full.jpg', fit: BoxFit.cover),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: _QuestionLinks())),
          ]);
        }),
      ),
    );
    return _Section(
      index: '01',
      eyebrow: 'The problem',
      title: 'Manual cabinet inspection is slow, hard to reproduce and hard to audit.',
      lead: 'Panel builders and QA teams verify every cabinet against its engineering drawing and wire list. Today that comparison happens in the inspector’s head.',
      child: wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: list), const SizedBox(width: 56), Expanded(flex: 6, child: visual)]) : Column(children: [list, const SizedBox(height: 16), visual]),
    );
  }
}

class _QuestionLinks extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = EE.uncertain.withValues(alpha: 0.85)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final pairs = [
      (Offset(s.width * 0.18, s.height * 0.16), Offset(s.width * 0.5, s.height * 0.5)),
      (Offset(s.width * 0.36, s.height * 0.42), Offset(s.width * 0.72, s.height * 0.68)),
      (Offset(s.width * 0.2, s.height * 0.56), Offset(s.width * 0.55, s.height * 0.88)),
    ];
    for (final (a, b) in pairs) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo((a.dx + b.dx) / 2 + 30, (a.dy + b.dy) / 2 - 30, b.dx, b.dy);
      for (final m in path.computeMetrics()) {
        for (double d = 0; d < m.length; d += 9) {
          canvas.drawPath(m.extractPath(d, d + 5), p);
        }
      }
      canvas.drawCircle(a, 4, Paint()..color = EE.uncertain);
      canvas.drawCircle(b, 4, Paint()..color = EE.uncertain);
      final mid = Offset((a.dx + b.dx) / 2 + 16, (a.dy + b.dy) / 2 - 16);
      canvas.drawCircle(mid, 11, Paint()..color = EE.bg0);
      canvas.drawCircle(mid, 11, p);
      final tp = TextPainter(text: const TextSpan(text: '?', style: TextStyle(color: EE.uncertain, fontWeight: FontWeight.w700, fontSize: 13)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- B. Pipeline ----------------------------------------------------------------------------

const _steps = [
  ('Ingest', 'Validate files, correct EXIF orientation, assess sharpness and exposure, apply CLAHE contrast enhancement.', Icons.input_rounded),
  ('Interpret Drawing', 'Extract text, vectors and zone frames from the GA PDF with PyMuPDF; OCR for raster sheets.', Icons.architecture_rounded),
  ('Align Geometry', 'SIFT/ORB + RANSAC homography, refined with identifier anchors shared by drawing and photo; manual fallback.', Icons.control_camera_rounded),
  ('Detect Components', 'YOLOv8 with overlapping tiles for small parts; boxes mapped back to original pixels.', Icons.center_focus_weak_rounded),
  ('Read Labels', 'OCR on full image and targeted crops; raw text preserved, normalisation steps recorded.', Icons.text_fields_rounded),
  ('Verify Specifications', 'Deterministic rules compare observations with the expected list: PASS, FAIL or UNCERTAIN.', Icons.rule_rounded),
  ('Generate Evidence', 'Crops, annotated overlays and a PDF report link every verdict back to real pixels.', Icons.photo_library_outlined),
  ('Review & Reinspect', 'Inspectors resolve uncertain items; reinspections create new versions and compare outcomes.', Icons.published_with_changes_rounded),
];

class PipelineSection extends StatefulWidget {
  const PipelineSection({super.key});
  @override
  State<PipelineSection> createState() => _PipelineSectionState();
}

class _PipelineSectionState extends State<PipelineSection> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduced(context)) {
      _c.stop();
      _c.value = 0.35;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      index: '02',
      eyebrow: 'The intelligence pipeline',
      title: 'Eight stages, each recorded and independently verifiable.',
      lead: 'Every stage persists its state, duration and diagnostics. The console shows the real backend state of each stage — never a simulated progress bar.',
      child: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 1050 ? 4 : (c.maxWidth >= 620 ? 2 : 1);
        const gap = 18.0;
        const h = 196.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        final rows = (_steps.length / cols).ceil();
        final rects = <Rect>[
          for (var i = 0; i < _steps.length; i++) Rect.fromLTWH((i % cols) * (w + gap), (i ~/ cols) * (h + gap * 2), w, h),
        ];
        return SizedBox(
          height: rows * h + (rows - 1) * gap * 2,
          child: Stack(children: [
            Positioned.fill(child: AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(painter: _FlowPainter(rects, _c.value)))),
            for (var i = 0; i < _steps.length; i++)
              Positioned.fromRect(
                rect: rects[i],
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) {
                    final active = ((_c.value * _steps.length).floor() % _steps.length) == i;
                    return _StepCard(index: i, active: active && !_reduced(context));
                  },
                ),
              ),
          ]),
        );
      }),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.index, required this.active});
  final int index;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final (t, d, icon) = _steps[index];
    return AnimatedContainer(
      duration: EE.med,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: active ? EE.surfaceHi : EE.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(EE.r3),
        border: Border.all(color: active ? EE.cyan.withValues(alpha: 0.7) : EE.line),
        boxShadow: active ? [BoxShadow(color: EE.cyan.withValues(alpha: 0.14), blurRadius: 30)] : const [],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text((index + 1).toString().padLeft(2, '0'), style: TextStyle(fontFamily: EE.fontMono, fontSize: 12, fontWeight: FontWeight.w600, color: active ? EE.cyan : EE.textDim)),
          const Spacer(),
          Icon(icon, size: 20, color: active ? EE.cyan : EE.textMuted),
        ]),
        const SizedBox(height: 16),
        Text(t, style: const TextStyle(fontFamily: EE.fontDisplay, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Expanded(child: Text(d, style: const TextStyle(fontSize: 12.8, height: 1.5, color: EE.textMuted), overflow: TextOverflow.fade)),
      ]),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.rects, this.t);
  final List<Rect> rects;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      if (i == 0) {
        path.moveTo(r.center.dx, r.center.dy);
      } else {
        final prev = rects[i - 1];
        if ((prev.top - r.top).abs() < 1) {
          path.lineTo(r.center.dx, r.center.dy);
        } else {
          final midY = (prev.bottom + r.top) / 2;
          path.lineTo(prev.center.dx, midY);
          path.lineTo(r.center.dx, midY);
          path.lineTo(r.center.dx, r.center.dy);
        }
      }
    }
    canvas.drawPath(path, Paint()
      ..color = EE.lineHi
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    for (final m in path.computeMetrics()) {
      for (var k = 0; k < 14; k++) {
        final d = ((t + k / 14) % 1.0) * m.length;
        final tan = m.getTangentForOffset(d);
        if (tan == null) continue;
        final a = 0.35 + 0.65 * math.sin(((t + k / 14) % 1.0) * math.pi);
        canvas.drawCircle(tan.position, 2.6, Paint()..color = (k % 5 == 0 ? EE.violet : EE.cyan).withValues(alpha: a));
        canvas.drawCircle(tan.position, 7, Paint()
          ..color = EE.cyan.withValues(alpha: 0.12 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) => old.t != t || old.rects != rects;
}

// --- C. Drawing-aware ---------------------------------------------------------------------

class DrawingAwareSection extends StatelessWidget {
  const DrawingAwareSection({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final rows = const [
      ('X12:3', 'X12-3A', 'X12-3A', 'PASS'),
      ('X12:4', 'X12-4B', 'X12-8B', 'FAIL'),
      ('X12:6', 'X12-6B', 'X12-68', 'UNCERTAIN'),
      ('X12:7', 'X12-7C', 'X12-7C', 'PASS'),
    ];
    final table = _Frame(
      label: 'ZONE Z4 · EXPECTED (WIRE LIST) vs OBSERVED (OCR)',
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        for (final (term, exp, obs, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              SizedBox(width: 70, child: Text(term, style: const TextStyle(fontFamily: EE.fontMono, color: EE.textMuted, fontSize: 12.5))),
              Expanded(child: MonoValue(exp, color: EE.ice)),
              const Icon(Icons.east_rounded, size: 14, color: EE.textDim),
              const SizedBox(width: 12),
              Expanded(child: MonoValue(obs, color: v == 'PASS' ? EE.text : EE.verdict(v))),
              VerdictBadge(v, dense: true),
            ]),
          ),
      ]),
    );
    final images = Row(children: [
      Expanded(child: _Frame(label: 'GA DRAWING · ZONE Z4', child: AspectRatio(aspectRatio: 2.15, child: Image.asset('assets/landing/ga_zone_z4.png', fit: BoxFit.cover)))),
      const SizedBox(width: 14),
      Expanded(child: _Frame(label: 'PHOTO REGION (REGISTERED)', child: AspectRatio(aspectRatio: 2.15, child: Image.asset('assets/landing/photo_zone_z4.jpg', fit: BoxFit.cover)))),
    ]);
    final note = const Text('Illustrative example from the bundled synthetic fixture. The values shown are what the live pipeline reported on that sample.',
        style: TextStyle(fontSize: 12, color: EE.textDim));
    return _Section(
      index: '03',
      eyebrow: 'Drawing-aware intelligence',
      title: 'It compares the cabinet with its specification — not just objects with a model.',
      lead: 'Zones and identifiers are read from the GA drawing, joined with the wire and label lists, projected onto the photograph, and then checked against what is actually there.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        images,
        const SizedBox(height: 14),
        if (wide) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: table), const SizedBox(width: 14), const Expanded(child: _RuleCard())]) else ...[table, const SizedBox(height: 14), const _RuleCard()],
        const SizedBox(height: 10),
        note,
      ]),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard();
  @override
  Widget build(BuildContext context) => _Frame(
        label: 'VERIFICATION POLICY · CONFUSION-AWARE',
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          _Rule('PASS', 'exact normalised match, adequate OCR confidence, reliable position'),
          _Rule('UNCERTAIN', 'differs only by OCR-confusable characters (8/B, 0/O, 1/I) — or text unreadable, partial or ambiguously placed'),
          _Rule('FAIL', 'a reliable reading that differs from the specification by a non-confusable edit'),
          SizedBox(height: 8),
          Text('Unreadable text never becomes a FAIL. A one-character difference can be decisive for an electrical identifier.', style: TextStyle(fontSize: 12.5, color: EE.textMuted, height: 1.5)),
        ]),
      );
}

class _Rule extends StatelessWidget {
  const _Rule(this.v, this.text);
  final String v;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 108, child: Align(alignment: Alignment.centerLeft, child: VerdictBadge(v, dense: true))),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.45))),
        ]),
      );
}

// --- D. Evidence ------------------------------------------------------------------------------

class EvidenceSection extends StatelessWidget {
  const EvidenceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final crop = _Frame(
      label: 'ZOOMED CROP · ORIGINAL PIXELS',
      child: AspectRatio(aspectRatio: 1.37, child: Image.asset('assets/landing/ferrule_x12_4.png', fit: BoxFit.cover)),
    );
    Widget kv(String k, String v, {Color? c, bool mono = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 150, child: Text(k, style: const TextStyle(fontSize: 12.5, color: EE.textDim))),
            Expanded(child: Text(v, style: TextStyle(fontFamily: mono ? EE.fontMono : EE.fontBody, fontSize: 13, color: c ?? EE.text))),
          ]),
        );
    final card = _Frame(
      label: 'FINDING #43 · FERRULE LABEL · ZONE Z4 · TERMINAL X12:4',
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Text('X12:4', style: TextStyle(fontFamily: EE.fontDisplay, fontSize: 26, fontWeight: FontWeight.w600)),
          SizedBox(width: 14),
          VerdictBadge('FAIL'),
        ]),
        const SizedBox(height: 10),
        kv('Expected value', 'X12-4B', c: EE.ice),
        kv('Observed value', 'X12-8B', c: EE.fail),
        kv('Bounding box', '[830, 2236, 922, 2261] px'),
        kv('Difference', "Levenshtein d = 1 · '4'→'8' (not an OCR-confusable pair)"),
        kv('OCR confidence', '0.99 (engine-reported, not a calibrated probability)'),
        kv('Registration', 'aligned · text anchors · 15 inliers · 0.23 px median error'),
        kv('Rule', 'identifier_mismatch'),
        kv('Combined score', 'not computed — sources reported separately', c: EE.textMuted),
        const SizedBox(height: 8),
        const Text('Recorded from a live pipeline run on the bundled synthetic fixture (CAB-07, version 1).', style: TextStyle(fontSize: 12, color: EE.textDim)),
      ]),
    );
    return _Section(
      index: '04',
      eyebrow: 'Proof, not just predictions',
      title: 'Every verdict carries its evidence.',
      lead: 'Expected value, observed value, the exact pixels, the rule that decided it, and every confidence source on its own — so a reviewer can agree or disagree in seconds.',
      child: wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: crop), const SizedBox(width: 18), Expanded(flex: 6, child: card)]) : Column(children: [crop, const SizedBox(height: 14), card]),
    );
  }
}

// --- E. Reinspection loop --------------------------------------------------------------------

class ReinspectionSection extends StatefulWidget {
  const ReinspectionSection({super.key});
  @override
  State<ReinspectionSection> createState() => _ReinspectionSectionState();
}

class _ReinspectionSectionState extends State<ReinspectionSection> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 10));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
      _Point('Original preserved', 'Each run is an immutable version. Reviews are stored as separate records; machine findings are never edited.'),
      _Point('Resolved means verified', 'A discrepancy closes only when the new run verifies it as PASS. An uncertain re-check keeps it open.'),
      _Point('Full history', 'Version-to-version comparison shows resolved, persistent, new and still-uncertain items, with the audit trail of who reviewed what.'),
    ]);
    final loop = AspectRatio(aspectRatio: 1, child: AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(painter: _LoopPainter(_c.value))));
    return _Section(
      index: '05',
      eyebrow: 'Reinspection loop',
      title: 'Inspect → Review → Correct → Reinspect → Compare.',
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: text), const SizedBox(width: 48), SizedBox(width: 420, child: loop)])
          : Column(children: [SizedBox(width: 340, child: loop), const SizedBox(height: 20), text]),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.t, this.d);
  final String t;
  final String d;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(margin: const EdgeInsets.only(top: 6), width: 8, height: 8, decoration: const BoxDecoration(color: EE.cyan, shape: BoxShape.circle)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(d, style: const TextStyle(fontSize: 13.5, height: 1.55, color: EE.textMuted)),
            ]),
          ),
        ]),
      );
}

class _LoopPainter extends CustomPainter {
  _LoopPainter(this.t);
  final double t;
  static const labels = ['Inspect', 'Review', 'Correct', 'Reinspect', 'Compare\nversions'];

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width * 0.36;
    canvas.drawCircle(c, r, Paint()
      ..color = EE.lineHi
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    final start = -math.pi / 2 + t * 2 * math.pi;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start - 1.1, 1.1, false, Paint()
      ..shader = SweepGradient(colors: [Colors.transparent, EE.cyan], startAngle: start - 1.1, endAngle: start, transform: GradientRotation(0)).createShader(Rect.fromCircle(center: c, radius: r))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
    final head = c + Offset(math.cos(start), math.sin(start)) * r;
    canvas.drawCircle(head, 5, Paint()..color = EE.cyan);
    canvas.drawCircle(head, 14, Paint()
      ..color = EE.cyan.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    for (var i = 0; i < labels.length; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / labels.length;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      var diff = (start - a) % (2 * math.pi);
      if (diff < 0) diff += 2 * math.pi;
      final lit = diff < 0.9;
      canvas.drawCircle(p, 22, Paint()..color = EE.bg1);
      canvas.drawCircle(p, 22, Paint()
        ..color = lit ? EE.cyan : EE.lineHi
        ..style = PaintingStyle.stroke
        ..strokeWidth = lit ? 2 : 1.2);
      final num = TextPainter(text: TextSpan(text: '${i + 1}', style: TextStyle(fontFamily: EE.fontMono, fontSize: 12, fontWeight: FontWeight.w700, color: lit ? EE.cyan : EE.textMuted)), textDirection: TextDirection.ltr)..layout();
      num.paint(canvas, p - Offset(num.width / 2, num.height / 2));
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: lit ? EE.text : EE.textMuted, height: 1.2)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120);
      final out = c + Offset(math.cos(a), math.sin(a)) * (r + 52);
      tp.paint(canvas, out - Offset(tp.width / 2, tp.height / 2));
    }
    final ctp = TextPainter(
      text: const TextSpan(children: [
        TextSpan(text: 'v1 → v2 → v3\n', style: TextStyle(fontFamily: EE.fontMono, fontSize: 13, color: EE.ice, fontWeight: FontWeight.w600)),
        TextSpan(text: 'every version kept', style: TextStyle(fontSize: 11.5, color: EE.textDim)),
      ]),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    ctp.paint(canvas, c - Offset(ctp.width / 2, ctp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _LoopPainter old) => old.t != t;
}

// --- F. CTA + footer -------------------------------------------------------------------------

class FinalCta extends StatelessWidget {
  const FinalCta({super.key});
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.fromLTRB(w >= 700 ? 40 : 20, 120, w >= 700 ? 40 : 20, 80),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1100),
          padding: EdgeInsets.symmetric(horizontal: w >= 700 ? 56 : 24, vertical: 56),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(EE.r3 + 4),
            border: Border.all(color: EE.cyan.withValues(alpha: 0.35)),
            gradient: const LinearGradient(colors: [Color(0xFF0C1A2B), Color(0xFF0A0F1C), Color(0xFF130F2A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: EE.cyan.withValues(alpha: 0.08), blurRadius: 60, spreadRadius: 4)],
          ),
          child: Column(children: [
            const BrandMark(size: 40),
            const SizedBox(height: 22),
            Text('Bring your engineering specifications.\nLeave with evidence.',
                textAlign: TextAlign.center, style: TextStyle(fontFamily: EE.fontDisplay, fontSize: w >= 900 ? 44 : 30, height: 1.12, fontWeight: FontWeight.w600, letterSpacing: -1)),
            const SizedBox(height: 18),
            const Text('Upload a cabinet photo, its GA drawing and the wire list — or run the bundled sample inspection.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15.5, color: EE.textMuted)),
            const SizedBox(height: 30),
            FilledButton.icon(
              onPressed: () => context.go('/console'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Open EAGLE EYE Console'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20)),
            ),
          ]),
        ),
      ),
    );
  }
}

class LandingFooter extends StatelessWidget {
  const LandingFooter({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: EE.line))),
        child: Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 12, spacing: 24, children: const [
          BrandLockup(subtitle: 'Team OpHackers · Track 3 PS 1'),
          Text('Vraj Shah · Vedaant Uttarkar · Yash Trivedi · Veer Jain', style: TextStyle(fontSize: 12.5, color: EE.textMuted)),
          Text('Prototype — supports inspection and human review; not a certification tool.', style: TextStyle(fontSize: 12, color: EE.textDim)),
        ]),
      );
}
