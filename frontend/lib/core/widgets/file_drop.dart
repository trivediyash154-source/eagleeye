import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../util/format.dart';
import 'file_drop_stub.dart' if (dart.library.js_interop) 'file_drop_web.dart' as impl;

/// A file chosen by the user (picker or drag-and-drop), fully read into memory.
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  int get size => bytes.length;
  String get extension {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }
}

/// Opens the platform file picker restricted to [extensions]. Returns null if cancelled.
Future<PickedFile?> pickFile(List<String> extensions) async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: extensions);
  if (files.isEmpty) return null;
  final f = files.first;
  return PickedFile(f.name, await f.readAsBytes());
}

/// Client-side pre-validation (the server validates again, including file signatures).
String? validatePicked(PickedFile f, List<String> extensions, int maxBytes) {
  if (!extensions.contains(f.extension)) {
    return '“${f.name}” is not an accepted file type (${extensions.map((e) => '.$e').join(', ')}).';
  }
  if (f.size == 0) return '“${f.name}” is empty.';
  if (f.size > maxBytes) return '“${f.name}” is ${fmtBytes(f.size)}; the limit is ${fmtBytes(maxBytes)}.';
  return null;
}

/// Drop target + picker. On the web, files can be dragged from the desktop onto the zone.
class FileDropZone extends StatefulWidget {
  const FileDropZone({
    super.key,
    required this.extensions,
    required this.maxBytes,
    required this.onFile,
    required this.title,
    this.hint,
    this.icon = Icons.upload_file_rounded,
    this.onRejected,
    this.enabled = true,
    this.busy = false,
    this.progress,
    this.compact = false,
  });

  final List<String> extensions;
  final int maxBytes;
  final ValueChanged<PickedFile> onFile;
  final ValueChanged<String>? onRejected;
  final String title;
  final String? hint;
  final IconData icon;
  final bool enabled;
  final bool busy;
  final double? progress;
  final bool compact;

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  final _key = GlobalKey();
  final _id = Object();
  bool _hover = false;
  bool _dragHover = false;

  @override
  void initState() {
    super.initState();
    impl.registerDropZone(
      _id,
      rect: _rect,
      onHover: (h) {
        if (mounted && h != _dragHover) setState(() => _dragHover = h);
      },
      onFile: (name, bytes) => _accept(PickedFile(name, bytes)),
    );
  }

  @override
  void dispose() {
    impl.unregisterDropZone(_id);
    super.dispose();
  }

  Rect? _rect() {
    if (!mounted || !widget.enabled || widget.busy) return null;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _accept(PickedFile f) {
    if (!mounted || !widget.enabled || widget.busy) return;
    final err = validatePicked(f, widget.extensions, widget.maxBytes);
    if (err != null) {
      widget.onRejected?.call(err);
      return;
    }
    widget.onFile(f);
  }

  Future<void> _pick() async {
    try {
      final f = await pickFile(widget.extensions);
      if (f != null) _accept(f);
    } catch (e) {
      widget.onRejected?.call('Could not read the selected file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _dragHover || _hover;
    final color = _dragHover ? EE.cyan : (_hover ? EE.lineHi : EE.line);
    final exts = widget.extensions.map((e) => e.toUpperCase()).join(' · ');
    final busy = widget.busy;
    return MouseRegion(
      cursor: widget.enabled && !busy ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.enabled && !busy ? _pick : null,
        child: AnimatedContainer(
          key: _key,
          duration: EE.fast,
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: widget.compact ? 14 : 28),
          decoration: BoxDecoration(
            color: _dragHover ? EE.cyan.withValues(alpha: 0.07) : (active ? EE.surfaceHi : EE.bg1),
            borderRadius: BorderRadius.circular(EE.r2),
            border: Border.all(color: color, width: _dragHover ? 1.5 : 1),
          ),
          child: CustomPaint(painter: _CornerTicks(_dragHover ? EE.cyan : EE.lineHi), child: widget.compact ? _compactBody(exts) : _body(exts)),
        ),
      ),
    );
  }

  Widget _body(String exts) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(EE.r2),
          border: Border.all(color: _dragHover ? EE.cyan : EE.lineHi),
          color: EE.surface,
        ),
        child: Icon(_dragHover ? Icons.file_download_outlined : widget.icon, color: _dragHover ? EE.cyan : EE.textMuted, size: 22),
      ),
      const SizedBox(height: 12),
      Text(
        _dragHover ? 'Release to upload' : widget.title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      const SizedBox(height: 4),
      Text(
        widget.hint ?? (impl.dropSupported ? 'Drag a file here or click to browse' : 'Click to browse'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: EE.textMuted),
      ),
      const SizedBox(height: 10),
      Text(
        '$exts  ·  max ${fmtBytes(widget.maxBytes)}',
        style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, letterSpacing: 0.8, color: EE.textDim),
      ),
      if (widget.busy) ...[
        const SizedBox(height: 14),
        SizedBox(width: 220, child: LinearProgressIndicator(value: widget.progress, minHeight: 3)),
        const SizedBox(height: 6),
        Text(
          widget.progress == null || widget.progress! >= 0.999 ? 'Validating on server…' : 'Uploading ${(widget.progress! * 100).round()}%',
          style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.cyan),
        ),
      ],
    ],
  );

  Widget _compactBody(String exts) => Row(
    children: [
      Icon(_dragHover ? Icons.file_download_outlined : widget.icon, color: _dragHover ? EE.cyan : EE.textMuted, size: 20),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_dragHover ? 'Release to upload' : widget.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            Text(
              '$exts · max ${fmtBytes(widget.maxBytes)}',
              style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.textDim),
            ),
            if (widget.busy) ...[const SizedBox(height: 6), LinearProgressIndicator(value: widget.progress, minHeight: 2)],
          ],
        ),
      ),
    ],
  );
}

class _CornerTicks extends CustomPainter {
  _CornerTicks(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    const l = 9.0, o = -10.0;
    final pts = [
      [Offset(o, o), Offset(o + l, o), Offset(o, o + l)],
      [Offset(s.width - o, o), Offset(s.width - o - l, o), Offset(s.width - o, o + l)],
      [Offset(o, s.height - o), Offset(o + l, s.height - o), Offset(o, s.height - o - l)],
      [Offset(s.width - o, s.height - o), Offset(s.width - o - l, s.height - o), Offset(s.width - o, s.height - o - l)],
    ];
    for (final c in pts) {
      canvas.drawLine(c[0], c[1], p);
      canvas.drawLine(c[0], c[2], p);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerTicks old) => old.color != color;
}
