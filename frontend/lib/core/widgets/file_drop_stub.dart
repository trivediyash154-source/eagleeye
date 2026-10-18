import 'dart:typed_data';
import 'dart:ui';

/// Non-web builds: drag-and-drop is unavailable; zones fall back to the file picker.
bool get dropSupported => false;

void registerDropZone(
  Object id, {
  required Rect? Function() rect,
  required void Function(bool hovering) onHover,
  required void Function(String name, Uint8List bytes) onFile,
}) {}

void unregisterDropZone(Object id) {}
