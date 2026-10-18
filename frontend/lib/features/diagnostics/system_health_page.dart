import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/config/app_config.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import 'diagnostics_widgets.dart';

final _checksProvider = FutureProvider<List<Json>>((ref) => ref.watch(apiProvider).checks());

const _componentOrder = ['api', 'database', 'storage', 'detector', 'ocr', 'pdf_parser', 'registration', 'report_generator'];

IconData _icon(String key) => switch (key) {
      'api' => Icons.api_rounded,
      'database' => Icons.storage_rounded,
      'storage' => Icons.folder_outlined,
      'detector' => Icons.center_focus_weak_rounded,
      'ocr' => Icons.text_fields_rounded,
      'pdf_parser' => Icons.picture_as_pdf_outlined,
      'registration' => Icons.architecture_rounded,
      'report_generator' => Icons.description_outlined,
      _ => Icons.settings_input_component_outlined,
    };

const _defaultLabels = {
  'api': 'API',
  'database': 'Database',
  'storage': 'File storage',
  'detector': 'YOLOv8 detector',
  'ocr': 'OCR engine',
  'pdf_parser': 'PDF parser',
  'registration': 'Drawing registration',
  'report_generator': 'Report generator',
};

/// System Health — readiness of every subsystem from real backend checks.
class SystemHealthPage extends ConsumerStatefulWidget {
  const SystemHealthPage({super.key});
  @override
  ConsumerState<SystemHealthPage> createState() => _SystemHealthPageState();
}

class _SystemHealthPageState extends ConsumerState<SystemHealthPage> {
  DateTime? _lastRefresh;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(systemStatusProvider).hasValue) _lastRefresh = DateTime.now();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    ref.invalidate(_checksProvider);
    await ref.read(systemStatusProvider.notifier).refresh();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(systemStatusProvider, (prev, next) {
      if (next.hasValue || next.hasError) setState(() => _lastRefresh = DateTime.now());
    });
    final status = ref.watch(systemStatusProvider);
    final cfg = ref.watch(appConfigProvider);
    final jobs = ref.watch(activeJobsProvider);
    final checks = ref.watch(_checksProvider);
    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      PageHeader(
        eyebrow: 'System · Health',
        title: 'System Health',
        description: 'Readiness of every EAGLE EYE subsystem, distinguishing a functioning component from one that is degraded, not yet loaded, '
            'unavailable or unsupported. Polled every 10 seconds from live backend checks.',
        actions: [
          OutlinedButton.icon(
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 1.8)) : const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Refresh now'),
          ),
        ],
      ),
      _OverallBanner(status: status, lastRefresh: _lastRefresh),
      const SizedBox(height: EE.s4),
      _StatusGrid(status: status),
      const SizedBox(height: EE.s4),
      ResponsiveRow(breakpoint: 1100, flex: const [3, 2], children: [
        const _LegendPanel(),
        _ConnectionPanel(config: cfg, status: status, lastRefresh: _lastRefresh),
      ]),
      const SizedBox(height: EE.s4),
      ResponsiveRow(breakpoint: 1100, flex: const [3, 2], children: [
        _ChecksPanel(checks: checks, onRetry: () => ref.invalidate(_checksProvider)),
        _JobsPanel(jobs: jobs),
      ]),
      const SizedBox(height: EE.s4),
      const _SecurityPanel(),
    ]);
  }
}

class _OverallBanner extends StatelessWidget {
  const _OverallBanner({required this.status, required this.lastRefresh});
  final AsyncValue<SystemStatus> status;
  final DateTime? lastRefresh;

  @override
  Widget build(BuildContext context) {
    final s = status.value;
    late final String state;
    late final String title;
    late final String detail;
    if (status.hasError && s == null) {
      state = 'error';
      title = 'Backend not reachable';
      detail = status.error.toString();
    } else if (s == null) {
      state = 'loading';
      title = 'Checking subsystems…';
      detail = 'Waiting for the first status response.';
    } else {
      final bad = s.components.where((c) => c.state != 'ok').toList();
      state = s.status == 'ok' ? 'ok' : (s.status == 'error' ? 'error' : 'degraded');
      title = switch (state) {
        'ok' => 'All subsystems functioning',
        'error' => 'Core subsystem failure',
        _ => 'Operational with ${bad.length} subsystem${bad.length == 1 ? '' : 's'} not fully available',
      };
      detail = bad.isEmpty ? 'Every check passed on the last poll.' : bad.map((c) => '${c.label}: ${stateLabels[c.state] ?? c.state}').join('  ·  ');
    }
    final c = stateColor(state);
    return Container(
      padding: const EdgeInsets.all(EE.s4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withValues(alpha: 0.12), EE.surface], begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(EE.r3),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        StatusDot(color: c, pulse: state != 'ok', size: 10),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(fontSize: 12.5, color: EE.textMuted)),
          ]),
        ),
        if (lastRefresh != null && MediaQuery.sizeOf(context).width > 600)
          Text('Last poll ${fmtTime(lastRefresh).substring(11)}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim)),
      ]),
    );
  }
}

class _StatusGrid extends StatelessWidget {
  const _StatusGrid({required this.status});
  final AsyncValue<SystemStatus> status;

  @override
  Widget build(BuildContext context) {
    final s = status.value;
    final unreachable = status.hasError && s == null;
    final tiles = <Widget>[];
    for (final key in _componentOrder) {
      final c = s?.byKey(key);
      final state = c?.state ?? (unreachable ? (key == 'api' ? 'error' : 'unknown') : 'loading');
      final msg = c?.message ?? (unreachable ? (key == 'api' ? status.error.toString() : 'Cannot be checked while the API is unreachable.') : 'Waiting for status…');
      tiles.add(_StatusTile(keyName: key, label: c?.label ?? _defaultLabels[key]!, state: state, message: msg));
    }
    return LayoutBuilder(builder: (context, box) {
      final cols = (box.maxWidth / 290).floor().clamp(1, 4);
      final w = (box.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.keyName, required this.label, required this.state, required this.message});
  final String keyName;
  final String label;
  final String state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = stateColor(state);
    return AnimatedContainer(
      duration: EE.med,
      height: 152,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: EE.panelGradient,
        borderRadius: BorderRadius.circular(EE.r3),
        border: Border.all(color: state == 'ok' ? EE.line : c.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: c.withValues(alpha: 0.35))),
            child: Icon(_icon(keyName), size: 16, color: c),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
          StatePill(state == 'unknown' ? 'pending' : state, label: stateLabels[state] ?? state, pulse: state == 'loading'),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: Tooltip(
            message: message,
            child: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.text, height: 1.4)),
          ),
        ),
        Text(stateMeaning[state] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: EE.textDim, height: 1.35)),
      ]),
    );
  }
}

class _LegendPanel extends StatelessWidget {
  const _LegendPanel();

  @override
  Widget build(BuildContext context) {
    const order = ['ok', 'degraded', 'loading', 'not_loaded', 'unavailable', 'unsupported', 'disabled', 'error'];
    return Panel(
      eyebrow: 'Legend',
      title: 'What each state means',
      child: Column(children: [
        for (final s in order)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 128, child: StatePill(s == 'unsupported' ? 'disabled' : s, label: stateLabels[s])),
              Expanded(child: Text(stateMeaning[s]!, style: const TextStyle(fontSize: 12.5, color: EE.textMuted, height: 1.4))),
            ]),
          ),
      ]),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({required this.config, required this.status, required this.lastRefresh});
  final AppConfig config;
  final AsyncValue<SystemStatus> status;
  final DateTime? lastRefresh;

  @override
  Widget build(BuildContext context) {
    final warm = status.value?.warmup;
    final sourceText = switch (config.source) {
      'dart-define' => 'build-time --dart-define=API_BASE_URL',
      'settings' => 'override saved in Settings (this browser)',
      'same-origin' => 'same origin as this page',
      _ => 'local development default',
    };
    return Panel(
      eyebrow: 'Connection',
      title: 'Client ↔ API',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KV('API base URL', config.apiBase, mono: true, keyWidth: 120),
        KV('Resolved from', sourceText, keyWidth: 120),
        KV('Polling interval', '10 s (status) · 4 s (active jobs)', keyWidth: 120),
        KV('Last poll', lastRefresh == null ? null : '${fmtTime(lastRefresh)} · ${ago(lastRefresh)}', keyWidth: 120),
        KV('Model warm-up', switch (warm) {
          'loading' => 'loading models in the background',
          'done' => 'finished (see detector/OCR state)',
          'idle' => 'not started (models load on first use)',
          null => null,
          _ => warm,
        }, keyWidth: 120),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => context.go('/console/models'), icon: const Icon(Icons.memory_rounded, size: 16), label: const Text('Open model diagnostics')),
        ),
      ]),
    );
  }
}

class _ChecksPanel extends StatelessWidget {
  const _ChecksPanel({required this.checks, required this.onRetry});
  final AsyncValue<List<Json>> checks;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Panel(
      eyebrow: 'Capability matrix',
      title: 'Inspection checks with the currently loaded models',
      child: AsyncView<List<Json>>(
        checks,
        onRetry: onRetry,
        data: (items) => Column(children: [
          for (final c in items) _checkRow(c),
        ]),
      ),
    );
  }

  Widget _checkRow(Json c) {
    final available = c.boolean('available');
    final note = c.strN('note');
    final notLoaded = !available && (note ?? '').contains('not loaded');
    final state = available ? 'ok' : (notLoaded ? 'not_loaded' : 'unsupported');
    final experimental = c.str('status') == 'experimental';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 5,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(c.str('title'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Tag(experimental ? 'EXPERIMENTAL' : 'IMPLEMENTED', color: experimental ? EE.uncertain : EE.textMuted, mono: true),
            ]),
            const SizedBox(height: 3),
            Text('Requires: ${c.str('requires')}', style: const TextStyle(fontSize: 11.5, color: EE.textDim)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            StatePill(state == 'unsupported' ? 'disabled' : state, label: available ? 'Available now' : stateLabels[state]),
            if (note != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(note, style: const TextStyle(fontSize: 11.5, color: EE.textMuted))),
          ]),
        ),
      ]),
    );
  }
}

class _JobsPanel extends StatelessWidget {
  const _JobsPanel({required this.jobs});
  final List<Job> jobs;

  @override
  Widget build(BuildContext context) {
    return Panel(
      eyebrow: 'Worker',
      title: 'Active processing jobs',
      child: jobs.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('No jobs are queued or running.', style: TextStyle(fontSize: 12.5, color: EE.textDim)),
            )
          : Column(children: [
              for (final j in jobs)
                InkWell(
                  onTap: () => context.go('/console/live?job=${j.id}'),
                  borderRadius: BorderRadius.circular(EE.r1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(children: [
                      Text(j.inspectionCode ?? j.id, style: const TextStyle(fontFamily: EE.fontMono, color: EE.cyan, fontSize: 12.5)),
                      if (j.versionNo != null) Text('  v${j.versionNo}', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(titleCase(j.currentStage ?? 'waiting in queue'), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                      StatePill(j.status),
                      const Icon(Icons.chevron_right_rounded, color: EE.textDim),
                    ]),
                  ),
                ),
            ]),
    );
  }
}

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel();

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, String, String, bool)>[
      (Icons.no_accounts_outlined, 'No authentication in this prototype',
          'Review decisions are attributed to the clearly labelled local-demo-reviewer identity. The API is structured so access control can be added; until then, run it only on a trusted network.', true),
      (Icons.rule_folder_outlined, 'Upload validation',
          'Files are checked by extension, file signature (magic bytes) and size limit, then decoded/parsed server-side before they are accepted.', false),
      (Icons.key_outlined, 'Generated storage keys',
          'Stored files use server-generated keys; user file names are kept only as metadata. Path-traversal attempts are rejected and downloads are restricted to the storage root.', false),
      (Icons.fingerprint_rounded, 'Integrity hashes',
          'A SHA-256 hash is recorded for every input file, evidence image and generated report so files can be verified later.', false),
      (Icons.public_off_outlined, 'Restricted CORS & secrets',
          'Browser origins are limited by EAGLEEYE_CORS_ORIGINS. Credentials and connection strings come from environment variables, are excluded from source control and are redacted from logs.', false),
      (Icons.lock_outline_rounded, 'Transport encryption (TLS)',
          'TLS is required in deployment. The local development server does NOT provide HTTPS — terminate TLS at a reverse proxy before exposing the service on an untrusted network.', true),
      (Icons.memory_outlined, 'Not end-to-end encrypted',
          'Server-side YOLOv8 and OCR must read image pixels, so the backend processes decrypted inspection images. Protect the host and its storage accordingly.', true),
      (Icons.storage_outlined, 'Encryption at rest',
          'Use disk/volume or database storage encryption for the data directory and PostgreSQL. The application does not encrypt files itself.', true),
    ];
    return Panel(
      eyebrow: 'Security & data handling',
      title: 'What is protected — and what is not',
      child: LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 900 ? 2 : 1;
        final w = (box.maxWidth - (cols - 1) * 14) / cols;
        return Wrap(spacing: 14, runSpacing: 14, children: [
          for (final (icon, title, body, caution) in items)
            SizedBox(
              width: w,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 18, color: caution ? EE.uncertain : EE.cyan),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: caution ? EE.uncertain : EE.text)),
                    const SizedBox(height: 3),
                    Text(body, style: const TextStyle(fontSize: 12, color: EE.textMuted, height: 1.45)),
                  ]),
                ),
              ]),
            ),
        ]);
      }),
    );
  }
}
