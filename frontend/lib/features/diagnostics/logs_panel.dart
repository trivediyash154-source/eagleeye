import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import 'diagnostics_widgets.dart';

/// Structured operational events from the backend ring buffer (redacted server-side).
class LogsPanel extends ConsumerStatefulWidget {
  const LogsPanel({super.key});
  @override
  ConsumerState<LogsPanel> createState() => _LogsPanelState();
}

class _LogsPanelState extends ConsumerState<LogsPanel> {
  static const _levels = ['DEBUG', 'INFO', 'WARNING', 'ERROR'];
  String? _level;
  int _limit = 200;
  bool _auto = false;
  final _component = TextEditingController();
  Timer? _timer;
  List<Json> _items = const [];
  Object? _error;
  bool _loading = false;
  DateTime? _fetched;
  final _expanded = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _component.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await ref.read(apiProvider).logs(level: _level, component: _component.text.trim().isEmpty ? null : _component.text.trim(), limit: _limit);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
        _fetched = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setAuto(bool v) {
    _timer?.cancel();
    _timer = v ? Timer.periodic(const Duration(seconds: 5), (_) => _load()) : null;
    setState(() => _auto = v);
  }

  Color _levelColor(String l) => switch (l) {
        'DEBUG' => EE.textDim,
        'INFO' => EE.info,
        'WARNING' => EE.uncertain,
        'ERROR' || 'CRITICAL' => EE.fail,
        _ => EE.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return Panel(
      eyebrow: 'Operational events',
      title: 'Structured logs',
      subtitle: 'Most recent first. Sensitive values (credentials, tokens, connection strings) are redacted on the server; image contents are never logged.',
      actions: [
        if (_loading) const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6))),
        IconButton(tooltip: 'Refresh logs', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 18)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String?>(
              initialValue: _level,
              decoration: const InputDecoration(labelText: 'Minimum level'),
              dropdownColor: EE.surfaceHi,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All levels')),
                for (final l in _levels) DropdownMenuItem<String?>(value: l, child: Text(l, style: TextStyle(fontFamily: EE.fontMono, fontSize: 12.5, color: _levelColor(l)))),
              ],
              onChanged: (v) {
                setState(() => _level = v);
                _load();
              },
            ),
          ),
          SizedBox(
            width: 200,
            child: TextField(
              controller: _component,
              decoration: const InputDecoration(labelText: 'Component prefix', hintText: 'e.g. pipeline, cv.detector'),
              onSubmitted: (_) => _load(),
            ),
          ),
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<int>(
              initialValue: _limit,
              decoration: const InputDecoration(labelText: 'Limit'),
              dropdownColor: EE.surfaceHi,
              items: const [
                DropdownMenuItem(value: 100, child: Text('100')),
                DropdownMenuItem(value: 200, child: Text('200')),
                DropdownMenuItem(value: 500, child: Text('500')),
              ],
              onChanged: (v) {
                setState(() => _limit = v ?? 200);
                _load();
              },
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(value: _auto, onChanged: _setAuto),
            const SizedBox(width: 4),
            const Text('Auto-refresh (5 s)', style: TextStyle(fontSize: 12.5, color: EE.textMuted)),
          ]),
          if (_fetched != null)
            Text('Fetched ${DateFormat('HH:mm:ss').format(_fetched!)} · ${_items.length} events',
                style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim)),
        ]),
        const SizedBox(height: 12),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: ErrorView(_error!, compact: true, onRetry: _load)),
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(EE.r2), border: Border.all(color: EE.line), color: EE.bg1),
          clipBehavior: Clip.antiAlias,
          height: 420,
          child: _items.isEmpty
              ? Center(child: Text(_loading ? 'Loading events…' : 'No events match the filters.', style: const TextStyle(fontSize: 12.5, color: EE.textDim)))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (_, i) => _row(_items[i], i, narrow),
                ),
        ),
      ]),
    );
  }

  Widget _row(Json e, int i, bool narrow) {
    final ctx = e.obj('context');
    final ts = e.time('timestamp');
    final level = e.str('level');
    final c = _levelColor(level);
    final open = _expanded.contains(e.integer('seq', i));
    final head = narrow
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Tag(level, color: c, mono: true),
              const SizedBox(width: 8),
              Text(ts == null ? '—' : DateFormat('MM-dd HH:mm:ss').format(ts), style: monoCell.copyWith(color: EE.textMuted, fontSize: 11)),
              const SizedBox(width: 8),
              Flexible(child: Text(e.str('component'), overflow: TextOverflow.ellipsis, style: monoCell.copyWith(color: EE.ice, fontSize: 11))),
            ]),
            const SizedBox(height: 4),
            Text(e.str('message'), style: cell),
          ])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 128,
              child: Tooltip(
                message: ts?.toIso8601String() ?? '',
                child: Text(ts == null ? '—' : DateFormat('MM-dd HH:mm:ss').format(ts), style: monoCell.copyWith(color: EE.textMuted, fontSize: 11)),
              ),
            ),
            SizedBox(width: 86, child: Align(alignment: Alignment.centerLeft, child: Tag(level, color: c, mono: true))),
            SizedBox(width: 150, child: Text(e.str('component'), overflow: TextOverflow.ellipsis, style: monoCell.copyWith(color: EE.ice, fontSize: 11))),
            Expanded(child: Text(e.str('message'), style: cell)),
            if (ctx.isNotEmpty) Icon(open ? Icons.expand_less_rounded : Icons.data_object_rounded, size: 15, color: EE.textDim),
          ]);
    return InkWell(
      onTap: ctx.isEmpty
          ? null
          : () => setState(() {
                final k = e.integer('seq', i);
                open ? _expanded.remove(k) : _expanded.add(k);
              }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.withValues(alpha: level == 'INFO' || level == 'DEBUG' ? 0.0 : 0.8), width: 2), bottom: const BorderSide(color: EE.line)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          if (open && ctx.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: EE.bg0, borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: EE.line)),
              child: SelectableText(prettyJson(ctx), style: monoCell.copyWith(fontSize: 11, color: EE.textMuted)),
            ),
        ]),
      ),
    );
  }
}
