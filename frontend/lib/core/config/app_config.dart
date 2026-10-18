import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../util/local_store.dart';

/// API base URL resolution (first match wins):
///  1. `--dart-define=API_BASE_URL=https://host` at build time
///  2. a value saved in Settings (browser local storage)
///  3. same origin when served by the backend; `http://<host>:8000` when served by a
///     local dev server on another port.
class AppConfig {
  const AppConfig({required this.apiBase, required this.source});

  final String apiBase;
  final String source; // dart-define | settings | same-origin | dev-default

  static const _defined = String.fromEnvironment('API_BASE_URL');
  static const storageKey = 'eagleeye.apiBase';

  static AppConfig resolve() {
    if (_defined.isNotEmpty) return AppConfig(apiBase: _strip(_defined), source: 'dart-define');
    final saved = LocalStore.get(storageKey);
    if (saved != null && saved.isNotEmpty) return AppConfig(apiBase: _strip(saved), source: 'settings');
    final base = Uri.base;
    if (base.scheme.startsWith('http')) {
      final local = base.host == 'localhost' || base.host == '127.0.0.1';
      if (local && base.port != 8000) return AppConfig(apiBase: '${base.scheme}://${base.host}:8000', source: 'dev-default');
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
