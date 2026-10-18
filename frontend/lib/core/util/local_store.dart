import 'local_store_stub.dart' if (dart.library.js_interop) 'local_store_web.dart' as impl;

/// Small key/value store for per-browser conveniences (API base URL, dataset filter).
/// Never used for inspection data — that lives in the backend database.
abstract final class LocalStore {
  static String? get(String key) => impl.read(key);
  static void set(String key, String value) => impl.write(key, value);
  static void remove(String key) => impl.delete(key);
}
