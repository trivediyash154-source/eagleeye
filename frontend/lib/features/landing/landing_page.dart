import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/grid_background.dart';
import 'cabinet_scene.dart';
import 'landing_sections.dart';

class LandingPage extends ConsumerStatefulWidget {
  const LandingPage({super.key});
  @override
  ConsumerState<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends ConsumerState<LandingPage> {
  final _scroll = ScrollController();
  final _keys = {for (final k in ['problem', 'pipeline', 'drawing', 'evidence', 'loop']) k: GlobalKey()};

  void _to(String k) {
    final ctx = _keys[k]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 1000;
    return Scaffold(
      backgroundColor: EE.bg0,
      body: Stack(children: [
        const Positioned.fill(child: _Atmosphere()),
        SingleChildScrollView(
          controller: _scroll,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Hero(wide: wide, onExplore: () => _to('pipeline'), onNav: _to),
            ProblemSection(key: _keys['problem']),
            PipelineSection(key: _keys['pipeline']),
            DrawingAwareSection(key: _keys['drawing']),
            EvidenceSection(key: _keys['evidence']),
            ReinspectionSection(key: _keys['loop']),
            const FinalCta(),
            const LandingFooter(),
          ]),
        ),
      ]),
    );
  }
}

class _Atmosphere extends StatelessWidget {
  const _Atmosphere();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(center: Alignment(0.55, -0.55), radius: 1.25, colors: [Color(0xFF0B1A2C), Color(0xFF060B14), EE.bg0], stops: [0, 0.45, 1]),
        ),
        child: GridBackground(opacity: 0.55),
      );
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.wide, required this.onExplore, required this.onNav});
  final bool wide;
  final VoidCallback onExplore;
  final void Function(String) onNav;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final h = wide ? (size.height.clamp(720.0, 980.0)) : null;
    final text = _HeroText(onExplore: onExplore);
    final scene = Stack(children: [
      const Positioned.fill(child: CabinetScene()),
      Positioned(
        right: 18,
        bottom: 14,
        child: Text('ILLUSTRATIVE 3D VISUALISATION · NOT LIVE INSPECTION DATA',
            style: TextStyle(fontFamily: EE.fontMono, fontSize: 9.5, letterSpacing: 1.4, color: EE.textDim.withValues(alpha: 0.9))),
      ),
    ]);
    return SizedBox(
      height: h,
      child: Column(children: [
        _NavBar(onNav: onNav),
        if (wide)
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 44, child: Padding(padding: const EdgeInsets.fromLTRB(64, 0, 24, 40), child: Center(child: text))),
              Expanded(flex: 56, child: scene),
            ]),
          )
        else ...[
          SizedBox(height: 380, child: scene),
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 48), child: text),
        ],
      ]),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.onNav});
  final void Function(String) onNav;
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    Widget link(String label, String k) => TextButton(
          onPressed: () => onNav(k),
          child: Text(label, style: const TextStyle(color: EE.textMuted, fontWeight: FontWeight.w500, fontSize: 13)),
        );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: wide ? 48 : 18, vertical: 18),
      child: Row(children: [
        const BrandLockup(subtitle: 'by OpHackers'),
        const Spacer(),
        if (wide) ...[link('Problem', 'problem'), link('Pipeline', 'pipeline'), link('Drawing-aware', 'drawing'), link('Evidence', 'evidence'), link('Reinspection', 'loop'), const SizedBox(width: 12)],
        OutlinedButton(onPressed: () => context.go('/console'), child: const Text('Open console')),
      ]),
    );
  }
}

class _HeroText extends ConsumerWidget {
  const _HeroText({required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = MediaQuery.sizeOf(context).width;
    final big = w >= 1300 ? 66.0 : (w >= 1000 ? 54.0 : (w >= 600 ? 46.0 : 36.0));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('INTELLIGENT INDUSTRIAL QUALITY ASSURANCE', style: TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, letterSpacing: 2.6, fontWeight: FontWeight.w600, color: EE.cyan)),
        const SizedBox(height: 22),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [EE.text, EE.text, EE.ice], stops: [0, 0.55, 1]).createShader(r),
          child: Text('Every Component.\nEvery Connection.\nVerified.',
              style: TextStyle(fontFamily: EE.fontDisplay, fontSize: big, height: 1.02, fontWeight: FontWeight.w600, letterSpacing: -big * 0.03, color: Colors.white)),
        ),
        const SizedBox(height: 24),
        const Text(
          'Drawing-aware AI inspection that transforms cabinet imagery and engineering specifications into traceable quality decisions.',
          style: TextStyle(fontSize: 17, height: 1.55, color: EE.textMuted),
        ),
        const SizedBox(height: 32),
        Wrap(spacing: 12, runSpacing: 12, children: [
          FilledButton.icon(
            onPressed: () => context.go('/console'),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Launch Inspection Console'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18)),
          ),
          OutlinedButton.icon(
            onPressed: onExplore,
            icon: const Icon(Icons.hub_outlined, size: 18),
            label: const Text('Explore the Intelligence Engine'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18)),
          ),
        ]),
        const SizedBox(height: 34),
        const _LiveStatus(),
      ]),
    );
  }
}

class _LiveStatus extends ConsumerWidget {
  const _LiveStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(systemStatusProvider);
    Widget row(String label, String state, String msg) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            StatusDot(color: EE.state(state), size: 6, pulse: state == 'loading'),
            SizedBox(width: 92, child: Text(label, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textMuted, letterSpacing: 0.6))),
            Expanded(child: Text(msg, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: EE.textDim))),
          ]),
        );
    final children = <Widget>[];
    if (s.hasError) {
      children.add(row('API', 'error', 'Backend not reachable — start the API to run inspections'));
    } else if (!s.hasValue) {
      children.add(row('API', 'loading', 'Checking backend…'));
    } else {
      final st = s.requireValue;
      SystemComponent? c(String k) => st.byKey(k);
      children.add(row('API', 'ok', 'Connected'));
      for (final k in ['detector', 'ocr', 'database']) {
        final x = c(k);
        if (x != null) children.add(row(x.key == 'detector' ? 'YOLOv8' : x.key.toUpperCase(), x.state, x.message));
      }
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(color: EE.surface.withValues(alpha: 0.7), border: Border.all(color: EE.line), borderRadius: BorderRadius.circular(EE.r2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('LIVE SYSTEM STATUS', style: TextStyle(fontFamily: EE.fontMono, fontSize: 9.5, letterSpacing: 1.8, color: EE.textDim)),
        const SizedBox(height: 6),
        ...children,
      ]),
    );
  }
}
