import 'package:intl/intl.dart';

String fmtBytes(int? b) {
  if (b == null) return '—';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

String fmtMs(int? ms) {
  if (ms == null) return '—';
  if (ms < 1000) return '$ms ms';
  final s = ms / 1000;
  if (s < 90) return '${s.toStringAsFixed(1)} s';
  return '${(s / 60).floor()}m ${(s % 60).round()}s';
}

String fmtTime(DateTime? t) => t == null ? '—' : DateFormat('yyyy-MM-dd HH:mm').format(t);
String fmtDate(DateTime? t) => t == null ? '—' : DateFormat('d MMM yyyy').format(t);

String ago(DateTime? t) {
  if (t == null) return '—';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

String pct(num? v, {int digits = 0}) => v == null ? '—' : '${(v * 100).toStringAsFixed(digits)}%';

String fmtConf(Object? v) => v is num ? v.toStringAsFixed(2) : (v?.toString() ?? '—');

String titleCase(String s) => s.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

/// Short display name of a pipeline stage key (e.g. `ocr` → `OCR`).
String stageName(String s) => s == 'ocr' ? 'OCR' : titleCase(s);
