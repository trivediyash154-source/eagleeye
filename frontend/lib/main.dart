import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/router.dart';
import 'core/theme/app_theme.dart';

void main() {
  usePathUrlStrategy(); // /console/workspace?i=… instead of /#/console/…; the backend serves index.html for deep links
  runApp(const ProviderScope(child: EagleEyeApp()));
}

class EagleEyeApp extends StatefulWidget {
  const EagleEyeApp({super.key});
  @override
  State<EagleEyeApp> createState() => _EagleEyeAppState();
}

class _EagleEyeAppState extends State<EagleEyeApp> {
  final _router = buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'EAGLE EYE — Intelligent Cabinet Inspection',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        darkTheme: buildTheme(),
        themeMode: ThemeMode.dark,
        routerConfig: _router,
      );
}
