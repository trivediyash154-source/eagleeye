import 'package:web/web.dart' as web;

String? read(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void write(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}

void delete(String key) {
  try {
    web.window.localStorage.removeItem(key);
  } catch (_) {}
}
