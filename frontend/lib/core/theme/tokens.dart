import 'package:flutter/material.dart';

/// EAGLE EYE design tokens — "premium industrial intelligence".
///
/// Deep midnight surfaces, titanium panels, electric-cyan intelligence accents,
/// restrained ultraviolet highlights and unambiguous verdict colours.
abstract final class EE {
  // Surfaces
  static const bg0 = Color(0xFF04070D);
  static const bg1 = Color(0xFF070C16);
  static const surface = Color(0xFF0B1321);
  static const surfaceHi = Color(0xFF101A2C);
  static const surfaceTop = Color(0xFF162238);
  static const titanium = Color(0xFF1C273B);
  static const line = Color(0xFF1D2A42);
  static const lineHi = Color(0xFF2A3A58);

  // Text
  static const text = Color(0xFFE7EEF8);
  static const textMuted = Color(0xFF94A3BA);
  static const textDim = Color(0xFF5D6B83);

  // Accents
  static const cyan = Color(0xFF22D3EE);
  static const ice = Color(0xFF8BD8FF);
  static const violet = Color(0xFF8B7CF6);
  static const ultraviolet = Color(0xFFB4A6FF);

  // Verdicts / states
  static const pass = Color(0xFF10B981);
  static const fail = Color(0xFFEF4444);
  static const uncertain = Color(0xFFF59E0B);
  static const waived = Color(0xFF8C97A8);
  static const info = Color(0xFF38BDF8);

  // Spacing scale
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s10 = 40.0;
  static const s12 = 48.0;

  // Radii (restrained — precise, not bubbly)
  static const r1 = 4.0;
  static const r2 = 8.0;
  static const r3 = 12.0;

  // Motion
  static const fast = Duration(milliseconds: 140);
  static const med = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 520);
  static const curve = Curves.easeOutCubic;

  static const fontBody = 'Inter';
  static const fontDisplay = 'InterDisplay';
  static const fontMono = 'JetBrainsMono';

  static Color verdict(String? v) => switch (v) {
        'PASS' => pass,
        'FAIL' => fail,
        'UNCERTAIN' => uncertain,
        'WAIVED' => waived,
        _ => textDim,
      };

  static Color state(String? s) => switch (s) {
        'ok' || 'completed' || 'loaded' || 'aligned' || 'manual' => pass,
        'degraded' || 'needs_review' || 'warning' || 'insufficient' || 'loading' || 'queued' => uncertain,
        'error' || 'failed' || 'unavailable' => fail,
        'running' => cyan,
        'skipped' || 'cancelled' || 'not_loaded' || 'disabled' || 'pending' => textDim,
        _ => textMuted,
      };

  static Color detClass(String c) => switch (c) {
        'circuit_breaker' => const Color(0xFF3CC8FF),
        'contactor' => const Color(0xFFC77DFF),
        'power_supply' => const Color(0xFFFFD25A),
        'terminal_block' => const Color(0xFF5AD8C6),
        'wire_marker' => const Color(0xFFF2F5FA),
        'device_label' => const Color(0xFFA0FFB4),
        'earth_bar' => const Color(0xFFFF9F43),
        _ => const Color(0xFF9AA6B8),
      };

  static const panelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E1728), Color(0xFF0A111E)],
  );

  static const mono = TextStyle(fontFamily: fontMono, fontSize: 12, height: 1.35, color: text);
}
