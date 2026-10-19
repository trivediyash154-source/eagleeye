import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../util/local_store.dart';

/// API base URL resolution (first match wins):
///  1. `--dart-define=API_BASE_URL=https://host` at build time
///  2. a value saved in Settings (browser local storage)
///  3. same origin when the page is served by the backend (any port); `http://<host>:8000`
///     when served by a local Flutter dev server, which has no API of its own.
class AppConfig {
  const AppConfig({required this.apiBase, required this.source});

  final String apiBase;
  final String source; // dart-define | settings | same-origin | dev-default

  static const _defined = String.fromEnvironment('API_BASE_URL');
  static const storageKey = 'eagleeye.apiBase';

  static bool _originServesApi = false;

  /// Called once before the app starts. On localhost with a port other than 8000 the page may come
  /// from the backend (e.g. `PORT=8100 ./scripts/run_local.sh`) or from `flutter run`; ask the origin.
  static Future<void> detectOrigin() async {
    final base = Uri.base;
    if (!base.scheme.startsWith('http') || !_isLocal(base) || base.port == 8000) return;
    try {
      final r = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 2), receiveTimeout: const Duration(seconds: 2)))
          .get<Object?>('${base.origin}/api/v1/health');
      final d = r.data;
      _originServesApi = d is Map && d['service'] == 'eagleeye-api';
    } catch (_) {
      _originServesApi = false;
    }
  }

  static bool _isLocal(Uri u) => u.host == 'localhost' || u.host == '127.0.0.1';

  static AppConfig resolve() {
    if (_defined.isNotEmpty) return AppConfig(apiBase: _strip(_defined), source: 'dart-define');
    final saved = LocalStore.get(storageKey);
    if (saved != null && saved.isNotEmpty) return AppConfig(apiBase: _strip(saved), source: 'settings');
    final base = Uri.base;
    if (base.scheme.startsWith('http')) {
      if (_isLocal(base) && base.port != 8000 && !_originServesApi) return AppConfig(apiBase: '${base.scheme}://${base.host}:8000', source: 'dev-default');
      return AppConfig(apiBase: base.origin, source: 'same-origin');
    }
    return const AppConfig(apiBase: 'http://localhost:8000', source: 'dev-default');
  }

  static String _strip(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}

class AppConfigNotifier extends Notifier<AppConfig> {
  @override
  AppConfig build() => AppConfig.resolve();

  void setApiBase(String? value) {
    if (value == null || value.trim().isEmpty) {
      LocalStore.remove(AppConfig.storageKey);
    } else {
      LocalStore.set(AppConfig.storageKey, value.trim());
    }
    state = AppConfig.resolve();
  }
}

final appConfigProvider = NotifierProvider<AppConfigNotifier, AppConfig>(AppConfigNotifier.new);
