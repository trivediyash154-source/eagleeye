import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui';

import 'package:web/web.dart' as web;

/// Browser drag-and-drop bridge. Flutter widgets cannot receive HTML drop events directly,
/// so window-level listeners hit-test the drop position (CSS px == Flutter logical px for a
/// full-page app) against the global rects of registered drop zones.
bool get dropSupported => true;

class _Zone {
  _Zone(this.rect, this.onHover, this.onFile);
  final Rect? Function() rect;
  final void Function(bool hovering) onHover;
  final void Function(String name, Uint8List bytes) onFile;
  bool hovering = false;
}

final _zones = <Object, _Zone>{};
bool _installed = false;

void registerDropZone(
  Object id, {
  required Rect? Function() rect,
  required void Function(bool hovering) onHover,
  required void Function(String name, Uint8List bytes) onFile,
}) {
  _zones[id] = _Zone(rect, onHover, onFile);
  _install();
}

void unregisterDropZone(Object id) => _zones.remove(id);

_Zone? _hit(double x, double y) {
  for (final z in _zones.values) {
    final r = z.rect();
    if (r != null && r.contains(Offset(x, y))) return z;
  }
  return null;
}

void _setHover(_Zone? target) {
  for (final z in _zones.values) {
    final h = identical(z, target);
    if (z.hovering != h) {
      z.hovering = h;
      z.onHover(h);
    }
  }
}

bool _hasFiles(web.DragEvent e) {
  final types = e.dataTransfer?.types;
  if (types == null) return false;
  for (var i = 0; i < types.length; i++) {
    if (types[i].toDart == 'Files') return true;
  }
  return false;
}

void _install() {
  if (_installed) return;
  _installed = true;
  web.window.addEventListener(
    'dragover',
    (web.Event ev) {
      final e = ev as web.DragEvent;
      if (!_hasFiles(e)) return;
      e.preventDefault(); // required for the drop event to fire
      final z = _hit(e.clientX.toDouble(), e.clientY.toDouble());
      e.dataTransfer?.dropEffect = z == null ? 'none' : 'copy';
      _setHover(z);
    }.toJS,
  );
  web.window.addEventListener(
    'dragleave',
    (web.Event ev) {
      final e = ev as web.DragEvent;
      // leaving the browser window entirely
      if (e.clientX <= 0 || e.clientY <= 0 || e.clientX >= web.window.innerWidth || e.clientY >= web.window.innerHeight) _setHover(null);
    }.toJS,
  );
  web.window.addEventListener(
    'drop',
    (web.Event ev) {
      final e = ev as web.DragEvent;
      if (!_hasFiles(e)) return;
      e.preventDefault(); // never let the browser navigate to the dropped file
      final z = _hit(e.clientX.toDouble(), e.clientY.toDouble());
      _setHover(null);
      final files = e.dataTransfer?.files;
      if (z == null || files == null || files.length == 0) return;
      final f = files.item(0);
      if (f == null) return;
      final name = f.name;
      f.arrayBuffer().toDart.then((buf) => z.onFile(name, buf.toDart.asUint8List()));
    }.toJS,
  );
}
