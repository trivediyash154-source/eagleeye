import 'package:eagle_eye/core/theme/app_theme.dart';
import 'package:eagle_eye/core/theme/tokens.dart';
import 'package:eagle_eye/core/widgets/badges.dart';
import 'package:eagle_eye/core/widgets/states.dart';
import 'package:eagle_eye/features/landing/cabinet_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget w) => MaterialApp(theme: buildTheme(), home: Scaffold(body: Center(child: w)));

void main() {
  testWidgets('VerdictBadge shows verdict with verdict colour', (t) async {
    await t.pumpWidget(_wrap(const VerdictBadge('UNCERTAIN')));
    final text = t.widget<Text>(find.text('UNCERTAIN'));
    expect(text.style!.color, EE.uncertain);
  });

  testWidgets('ErrorView offers retry', (t) async {
    var retried = false;
    await t.pumpWidget(_wrap(ErrorView(Exception('boom'), onRetry: () => retried = true)));
    await t.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('Cabinet scene falls back to the static painter off the web', (t) async {
    await t.pumpWidget(_wrap(const SizedBox(width: 600, height: 400, child: CabinetScene())));
    expect(find.byType(CustomPaint), findsWidgets);
  });

  test('state colours distinguish unavailable from not loaded', () {
    expect(EE.state('unavailable'), EE.fail);
    expect(EE.state('not_loaded'), EE.textDim);
    expect(EE.state('ok'), EE.pass);
  });
}
