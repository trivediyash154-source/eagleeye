import 'package:flutter/material.dart';

import 'cabinet_scene_fallback.dart';
import 'cabinet_scene_stub.dart' if (dart.library.js_interop) 'cabinet_scene_web.dart' as impl;

/// The landing-page 3D cabinet. On Flutter Web it embeds the Three.js scene
/// (web/three/eagle_scene.js); elsewhere, or when WebGL is unavailable, it shows a
/// static technical composition painted in Flutter.
class CabinetScene extends StatelessWidget {
  const CabinetScene({super.key});

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return impl.buildScene(reducedMotion: reduced, fallback: const CabinetSceneFallback());
  }
}
