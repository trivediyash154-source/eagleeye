import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/router.dart';
import 'core/api/api_client.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  usePathUrlStrategy(); // /console/workspace?i=… instead of /#/console/…; the backend serves index.html for deep links
  await AppConfig.detectOrigin();
  runApp(const ProviderScope(retry: _retry, child: EagleEyeApp()));
}

/// Client errors (404, 409, 422 …) are answers, not glitches: show them at once instead of retrying.
/// Network failures and server errors are retried a few times with backoff.
Duration? _retry(int count, Object error) {
  if (error is ApiException && error.status != null && error.status! < 500) return null;
  if (count >= 4) return null;
  return ProviderContainer.defaultRetry(count, error);
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
