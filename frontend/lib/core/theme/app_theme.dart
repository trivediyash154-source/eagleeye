import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: EE.cyan,
    onPrimary: Color(0xFF021018),
    secondary: EE.violet,
    onSecondary: Colors.white,
    tertiary: EE.ice,
    onTertiary: Color(0xFF021018),
    error: EE.fail,
    onError: Colors.white,
    surface: EE.surface,
    onSurface: EE.text,
    surfaceContainerLowest: EE.bg0,
    surfaceContainerLow: EE.bg1,
    surfaceContainer: EE.surface,
    surfaceContainerHigh: EE.surfaceHi,
    surfaceContainerHighest: EE.surfaceTop,
    outline: EE.lineHi,
    outlineVariant: EE.line,
    onSurfaceVariant: EE.textMuted,
  );

  TextStyle t(double size, FontWeight w, {double h = 1.3, double ls = 0, String f = EE.fontBody, Color c = EE.text}) =>
      TextStyle(fontFamily: f, fontSize: size, fontWeight: w, height: h, letterSpacing: ls, color: c);

  final text = TextTheme(
    displayLarge: t(64, FontWeight.w600, h: 1.02, ls: -1.8, f: EE.fontDisplay),
    displayMedium: t(48, FontWeight.w600, h: 1.05, ls: -1.2, f: EE.fontDisplay),
    displaySmall: t(36, FontWeight.w600, h: 1.1, ls: -0.8, f: EE.fontDisplay),
    headlineLarge: t(30, FontWeight.w600, h: 1.15, ls: -0.6, f: EE.fontDisplay),
    headlineMedium: t(24, FontWeight.w600, h: 1.2, ls: -0.4, f: EE.fontDisplay),
    headlineSmall: t(20, FontWeight.w600, h: 1.25, ls: -0.2, f: EE.fontDisplay),
    titleLarge: t(17, FontWeight.w600, h: 1.3),
    titleMedium: t(14.5, FontWeight.w600, h: 1.3),
    titleSmall: t(13, FontWeight.w600, h: 1.3),
    bodyLarge: t(15, FontWeight.w400, h: 1.55, c: EE.textMuted),
    bodyMedium: t(13.5, FontWeight.w400, h: 1.5),
    bodySmall: t(12, FontWeight.w400, h: 1.45, c: EE.textMuted),
    labelLarge: t(13, FontWeight.w600, h: 1.2, ls: 0.1),
    labelMedium: t(11.5, FontWeight.w600, h: 1.2, ls: 0.4),
    labelSmall: t(10.5, FontWeight.w600, h: 1.2, ls: 1.1, c: EE.textMuted),
  );

  OutlinedBorder shape([double r = EE.r2]) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: EE.bg0,
    fontFamily: EE.fontBody,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: const DividerThemeData(color: EE.line, thickness: 1, space: 1),
    iconTheme: const IconThemeData(color: EE.textMuted, size: 18),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: EE.surfaceTop, border: Border.all(color: EE.lineHi), borderRadius: BorderRadius.circular(EE.r1)),
      textStyle: const TextStyle(fontFamily: EE.fontBody, fontSize: 12, color: EE.text),
      waitDuration: const Duration(milliseconds: 350),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: EE.cyan,
        foregroundColor: const Color(0xFF021018),
        disabledBackgroundColor: EE.titanium,
        disabledForegroundColor: EE.textDim,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontFamily: EE.fontBody, fontWeight: FontWeight.w600, fontSize: 13.5, letterSpacing: 0.1),
        shape: shape(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: EE.text,
        side: const BorderSide(color: EE.lineHi),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: const TextStyle(fontFamily: EE.fontBody, fontWeight: FontWeight.w600, fontSize: 13.5),
        shape: shape(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: EE.cyan, textStyle: const TextStyle(fontFamily: EE.fontBody, fontWeight: FontWeight.w600, fontSize: 13), shape: shape()),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: EE.bg1,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      labelStyle: const TextStyle(color: EE.textMuted, fontSize: 13),
      hintStyle: const TextStyle(color: EE.textDim, fontSize: 13),
      helperStyle: const TextStyle(color: EE.textDim, fontSize: 11.5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(EE.r2), borderSide: const BorderSide(color: EE.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(EE.r2), borderSide: const BorderSide(color: EE.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(EE.r2), borderSide: const BorderSide(color: EE.cyan, width: 1.2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(EE.r2), borderSide: const BorderSide(color: EE.fail)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: EE.surfaceHi,
      selectedColor: EE.cyan.withValues(alpha: 0.16),
      side: const BorderSide(color: EE.line),
      labelStyle: const TextStyle(fontFamily: EE.fontBody, fontSize: 12, color: EE.text, fontWeight: FontWeight.w500),
      shape: shape(EE.r1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: EE.surfaceTop,
      contentTextStyle: const TextStyle(fontFamily: EE.fontBody, color: EE.text, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EE.r2), side: const BorderSide(color: EE.lineHi)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: EE.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EE.r3), side: const BorderSide(color: EE.lineHi)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? EE.cyan : Colors.transparent),
      side: const BorderSide(color: EE.lineHi, width: 1.4),
      checkColor: WidgetStateProperty.all(const Color(0xFF021018)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? EE.cyan : EE.textDim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? EE.cyan.withValues(alpha: 0.3) : EE.titanium),
      trackOutlineColor: WidgetStateProperty.all(EE.line),
    ),
    sliderTheme: const SliderThemeData(activeTrackColor: EE.cyan, inactiveTrackColor: EE.titanium, thumbColor: EE.cyan, overlayColor: Color(0x2222D3EE), trackHeight: 2.5),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: EE.cyan, linearTrackColor: EE.titanium),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(EE.lineHi),
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
