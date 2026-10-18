import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme/tokens.dart';

/// Numeric zone editor. Coordinates are PDF points (origin top-left, y downward).
/// Pops with the server's confirmation message on save.
class ZoneEditorDialog extends ConsumerStatefulWidget {
  const ZoneEditorDialog({super.key, required this.versionId, required this.zones, required this.versionStatus, this.newBbox});
  final String versionId;
  final List<Json> zones;
  final String versionStatus;
  final List<double>? newBbox;

  @override
  ConsumerState<ZoneEditorDialog> createState() => _ZoneEditorDialogState();
}

class _ZoneRow {
  _ZoneRow(String code, String name, List<double> b)
      : code = TextEditingController(text: code),
        name = TextEditingController(text: name),
        coords = [for (final v in b) TextEditingController(text: v.toStringAsFixed(1))];
  final TextEditingController code;
  final TextEditingController name;
  final List<TextEditingController> coords;

  void dispose() {
    code.dispose();
    name.dispose();
    for (final c in coords) {
      c.dispose();
    }
  }
}

class _ZoneEditorDialogState extends ConsumerState<ZoneEditorDialog> {
  late final List<_ZoneRow> _rows = [
    for (final z in widget.zones) _ZoneRow(z.str('code'), z.strN('name') ?? '', z.box('bbox') ?? const [0, 0, 100, 100]),
    if (widget.newBbox != null) _ZoneRow(_nextCode(), '', widget.newBbox!),
  ];
  String? _error;
  bool _busy = false;

  String _nextCode() {
    final nums = widget.zones.map((z) => int.tryParse(z.str('code').replaceAll(RegExp(r'[^0-9]'), '')) ?? 0);
    final n = (nums.isEmpty ? 0 : nums.reduce((a, b) => a > b ? a : b)) + 1;
    return 'Z$n';
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final out = <Json>[];
    final codes = <String>{};
    for (final r in _rows) {
      final code = r.code.text.trim().toUpperCase();
      if (code.isEmpty) return setState(() => _error = 'Every zone needs a code.');
      if (!codes.add(code)) return setState(() => _error = 'Zone code $code is used twice.');
      final b = r.coords.map((c) => double.tryParse(c.text.trim())).toList();
      if (b.any((x) => x == null)) return setState(() => _error = 'Zone $code has a non-numeric coordinate.');
      final x0 = b[0]!, y0 = b[1]!, x1 = b[2]!, y1 = b[3]!;
      if ((x1 - x0).abs() < 2 || (y1 - y0).abs() < 2) return setState(() => _error = 'Zone $code is too small (min 2 pt).');
      out.add({'code': code, 'name': r.name.text.trim().isEmpty ? null : r.name.text.trim(), 'bbox': [x0, y0, x1, y1]});
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiProvider).saveZones(widget.versionId, out);
      if (mounted) Navigator.pop(context, res.str('message', 'Zones saved.'));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final immutable = !const {'draft', 'failed', 'cancelled'}.contains(widget.versionStatus);
    InputDecoration dec(String label) => InputDecoration(labelText: label, isDense: true);
    return AlertDialog(
      title: const Text('Zone definitions'),
      content: SizedBox(
        width: 760,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            immutable
                ? 'This version is ${widget.versionStatus}. Corrections are saved on the drawing record (with an audit entry) and applied by the next reinspection; '
                    'the existing findings stay unchanged.'
                : 'These zones replace the automatically extracted ones when this version runs.',
            style: const TextStyle(fontSize: 12, color: EE.textMuted, height: 1.45),
          ),
          const SizedBox(height: 4),
          const Text('Coordinates: PDF points, origin top-left, y downward (x0, y0 = top-left corner).', style: TextStyle(fontSize: 11, color: EE.textDim)),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(children: [
                for (var i = 0; i < _rows.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      SizedBox(width: 70, child: TextField(controller: _rows[i].code, decoration: dec('Code'), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5))),
                      SizedBox(width: 170, child: TextField(controller: _rows[i].name, decoration: dec('Name'), style: const TextStyle(fontSize: 12.5))),
                      for (final (k, label) in const [(0, 'x0'), (1, 'y0'), (2, 'x1'), (3, 'y1')])
                        SizedBox(
                          width: 84,
                          child: TextField(
                            controller: _rows[i].coords[k],
                            decoration: dec(label),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Delete zone',
                        onPressed: () => setState(() => _rows.removeAt(i).dispose()),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: EE.fail),
                      ),
                    ]),
                  ),
                if (_rows.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No zones. Add one below.', style: TextStyle(fontSize: 12, color: EE.textDim))),
              ]),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _rows.add(_ZoneRow(_nextCodeFromRows(), '', const [50, 50, 250, 200]))),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add zone'),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(color: EE.fail, fontSize: 12.5))),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save zones')),
      ],
    );
  }

  String _nextCodeFromRows() {
    final nums = _rows.map((r) => int.tryParse(r.code.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0);
    final n = (nums.isEmpty ? 0 : nums.reduce((a, b) => a > b ? a : b)) + 1;
    return 'Z$n';
  }
}
