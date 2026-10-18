import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/download.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';

/// Settings — client connection, dataset default, display notes, identity and configuration reference.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _url = TextEditingController(text: ref.read(appConfigProvider).apiBase);
  bool _testing = false;
  String? _testMsg;
  bool _testOk = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  String? _validate(String v) {
    final u = Uri.tryParse(v.trim());
    if (v.trim().isEmpty) return 'Enter a URL such as http://localhost:8000';
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) return 'Use an absolute http(s) URL, e.g. https://eagleeye.example.com';
    return null;
  }

  Future<void> _test() async {
    final err = _validate(_url.text);
    if (err != null) {
      setState(() {
        _testOk = false;
        _testMsg = err;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testMsg = null;
    });
    final sw = Stopwatch()..start();
    var base = _url.text.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    try {
      final r = await ApiClient(base).health();
      sw.stop();
      setState(() {
        _testOk = r['status'] == 'ok';
        _testMsg = 'Connected · ${r['service'] ?? 'API'} ${r['api_version'] ?? ''} · ${sw.elapsedMilliseconds} ms round trip';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testMsg = e.toString();
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _save() {
    final err = _validate(_url.text);
    if (err != null) {
      showSnack(context, err, error: true);
      return;
    }
    ref.read(appConfigProvider.notifier).setApiBase(_url.text.trim());
    showSnack(context, 'API base URL saved for this browser');
  }

  void _reset() {
    ref.read(appConfigProvider.notifier).setApiBase(null);
    setState(() {
      _url.text = ref.read(appConfigProvider).apiBase;
      _testMsg = null;
    });
    showSnack(context, 'Reverted to the default API base URL');
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(appConfigProvider);
    final dataset = ref.watch(datasetProvider);
    final api = ref.watch(apiProvider);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      const PageHeader(
        eyebrow: 'System · Settings',
        title: 'Settings',
        description: 'Client-side preferences for this browser and a reference of the server configuration. '
            'Server settings are changed through EAGLEEYE_* environment variables, not from the UI.',
      ),
      ResponsiveRow(breakpoint: 1150, flex: const [3, 2], children: [
        Panel(
          eyebrow: 'Connection',
          title: 'API base URL',
          subtitle: 'Where this console sends requests. Stored in this browser only.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _url,
              style: const TextStyle(fontFamily: EE.fontMono, fontSize: 13),
              decoration: const InputDecoration(labelText: 'API base URL', hintText: 'http://localhost:8000'),
              onSubmitted: (_) => _test(),
            ),
            const SizedBox(height: 8),
            KV('Currently in use', cfg.apiBase, mono: true, keyWidth: 130),
            KV('Resolved from', switch (cfg.source) {
              'dart-define' => 'build-time --dart-define=API_BASE_URL',
              'settings' => 'saved override (this browser)',
              'same-origin' => 'same origin as this page',
              _ => 'local development default (port 8000)',
            }, keyWidth: 130),
            if (cfg.source == 'dart-define') ...[
              const SizedBox(height: 6),
              const Text(
                'This build was compiled with API_BASE_URL, which takes precedence over a saved override.',
                style: TextStyle(fontSize: 12, color: EE.uncertain),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 1.8)) : const Icon(Icons.network_check_rounded, size: 17),
                label: const Text('Test connection'),
              ),
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined, size: 17), label: const Text('Save')),
              TextButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt_rounded, size: 17), label: const Text('Reset to default')),
            ]),
            if (_testMsg != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(_testOk ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 16, color: _testOk ? EE.pass : EE.fail),
                const SizedBox(width: 8),
                Expanded(child: Text(_testMsg!, style: TextStyle(fontSize: 12.5, color: _testOk ? EE.pass : EE.fail))),
              ]),
            ],
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Panel(
            eyebrow: 'Data view',
            title: 'Default dataset',
            subtitle: 'Which inspections dashboards, analytics, history and queues show by default.',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All'), icon: Icon(Icons.layers_outlined, size: 16)),
                  ButtonSegment(value: 'real', label: Text('Real only'), icon: Icon(Icons.verified_outlined, size: 16)),
                  ButtonSegment(value: 'demo', label: Text('Demo only'), icon: Icon(Icons.science_outlined, size: 16)),
                ],
                selected: {dataset},
                showSelectedIcon: false,
                onSelectionChanged: (s) => ref.read(datasetProvider.notifier).set(s.first),
              ),
              const SizedBox(height: 8),
              const Text('Demonstration inspections use bundled SYNTHETIC inputs and are always labelled DEMO, whatever this filter is set to.',
                  style: TextStyle(fontSize: 11.5, color: EE.textDim)),
            ]),
          ),
          const SizedBox(height: EE.s4),
          Panel(
            eyebrow: 'Display',
            title: 'Motion & theme',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Text('Reduced motion', style: TextStyle(fontSize: 13)),
                const Spacer(),
                Tag(reduce ? 'ON (from OS / browser)' : 'OFF (from OS / browser)', color: reduce ? EE.cyan : EE.textMuted, mono: true),
              ]),
              const SizedBox(height: 6),
              const Text(
                'The console follows your operating-system “reduce motion” preference: when it is on, page transitions and image-viewer zoom are '
                'instant and the 3D landing scene shows a static composition.',
                style: TextStyle(fontSize: 12, color: EE.textMuted, height: 1.45),
              ),
              const Hairline(vertical: 8),
              const Text('A single dark industrial theme is used by design for control-room legibility and consistent verdict colours.',
                  style: TextStyle(fontSize: 12, color: EE.textMuted, height: 1.45)),
            ]),
          ),
        ]),
      ]),
      const SizedBox(height: EE.s4),
      ResponsiveRow(breakpoint: 1150, children: [
        const Panel(
          eyebrow: 'Identity',
          title: 'Reviewer identity',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KV('Reviewer', 'local-demo-reviewer', mono: true, keyWidth: 120),
            KV('Authentication', 'Not enabled in this prototype', keyWidth: 120),
            SizedBox(height: 6),
            Text(
              'Every review decision is stored as a separate record attributed to this local demo identity and labelled as such in reports and the audit '
              'trail. It does not prove who made the decision. The identity is set on the server with EAGLEEYE_REVIEWER_IDENTITY.',
              style: TextStyle(fontSize: 12, color: EE.textMuted, height: 1.45),
            ),
          ]),
        ),
        Panel(
          eyebrow: 'Documentation',
          title: 'API reference',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Interactive OpenAPI documentation and the machine-readable schema of the running backend.',
                style: TextStyle(fontSize: 12, color: EE.textMuted, height: 1.45)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: () => openUrl(api.url('/api/v1/docs')), icon: const Icon(Icons.menu_book_outlined, size: 17), label: const Text('API docs')),
              OutlinedButton.icon(onPressed: () => openUrl(api.url('/api/v1/openapi.json')), icon: const Icon(Icons.data_object_rounded, size: 17), label: const Text('OpenAPI JSON')),
            ]),
          ]),
        ),
      ]),
      const SizedBox(height: EE.s4),
      const _EnvReference(),
      const SizedBox(height: EE.s4),
      const Panel(
        eyebrow: 'Data lifecycle',
        title: 'Retention policy',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Bullet('Input files, evidence images and generated reports are kept in the data directory until an operator deletes them.'),
          _Bullet('Inspection versions are never purged or overwritten automatically — reinspection always creates a new version, preserving the audit trail.'),
          _Bullet('Evidence thumbnails are cached next to their source images and regenerated on demand if removed.'),
          _Bullet('Browser storage holds only conveniences (API URL override, dataset filter); no inspection data is stored client-side.'),
        ]),
      ),
    ]);
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 6, right: 10), child: Icon(Icons.circle, size: 5, color: EE.cyan)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: EE.textMuted, height: 1.45))),
        ]),
      );
}

class _EnvReference extends StatelessWidget {
  const _EnvReference();

  static const _vars = <(String, String, String)>[
    ('EAGLEEYE_DATABASE_URL', 'SQLite in DATA_DIR', 'SQLAlchemy URL; use postgresql+psycopg://… for the production configuration.'),
    ('EAGLEEYE_DATA_DIR', 'backend/var', 'Root for uploads, evidence, reports and the SQLite database.'),
    ('EAGLEEYE_AUTO_MIGRATE', 'true', 'Apply Alembic migrations on startup.'),
    ('EAGLEEYE_ENVIRONMENT', 'development', '“development” additionally allows any localhost origin for CORS.'),
    ('EAGLEEYE_CORS_ORIGINS', 'localhost:8080 / :5000', 'JSON list of browser origins allowed to call the API.'),
    ('EAGLEEYE_DETECTOR_WEIGHTS', 'models/eagleeye-synth-v1.pt', 'Cabinet-specific YOLOv8 weights (preferred).'),
    ('EAGLEEYE_DETECTOR_FALLBACK_WEIGHTS', 'models/cache/yolov8n.pt', 'Generic COCO weights used when custom weights are missing.'),
    ('EAGLEEYE_DETECTOR_DEVICE', 'auto', 'auto | cpu | cuda:0 | mps.'),
    ('EAGLEEYE_DETECTOR_CONF', '0.35', 'Confidence required for a positive detection.'),
    ('EAGLEEYE_DETECTOR_IOU', '0.5', 'IoU threshold for non-maximum suppression.'),
    ('EAGLEEYE_DETECTOR_IMGSZ', '640', 'Inference resolution per image/tile.'),
    ('EAGLEEYE_DETECTOR_TILING', 'true', 'Overlapping-tile inference for small objects (TILE_SIZE 1024, TILE_OVERLAP 0.2).'),
    ('EAGLEEYE_OCR_ENGINE', 'auto', 'auto (PaddleOCR, then EasyOCR) | paddle | easyocr | none.'),
    ('EAGLEEYE_OCR_LANGUAGES', '["en"]', 'OCR language list.'),
    ('EAGLEEYE_OCR_GPU', 'false', 'Use a GPU for OCR when available.'),
    ('EAGLEEYE_EASYOCR_MODEL_DIR', 'models/cache/easyocr', 'Directory with EasyOCR detection/recognition weights.'),
    ('EAGLEEYE_OCR_ALLOW_DOWNLOAD', 'false', 'Allow EasyOCR to download missing weights.'),
    ('EAGLEEYE_OCR_EXCLUDE_IO', 'true', 'Drop I and O from the allowlist (IEC 81346 convention).'),
    ('EAGLEEYE_MAX_IMAGE_MB', '25', 'Upload limit for photos (also MAX_PDF_MB 50, MAX_SHEET_MB 10).'),
    ('EAGLEEYE_MAX_PROCESSING_SIDE', '4000', 'Longest side used for processing; originals are preserved.'),
    ('EAGLEEYE_JOB_WORKERS', '1', 'Concurrent inspection jobs in the worker pool.'),
    ('EAGLEEYE_REVIEWER_IDENTITY', 'local-demo-reviewer', 'Identity recorded on review decisions (no authentication).'),
    ('EAGLEEYE_DEMO_DIR', 'data/demo', 'Location of the bundled synthetic demonstration fixtures.'),
    ('API_BASE_URL (Flutter)', 'same origin', 'Build-time --dart-define for the web client.'),
  ];

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return Panel(
      eyebrow: 'Server configuration',
      title: 'Environment variables reference',
      subtitle: 'Set these in .env or the container environment. Secrets (database passwords) must never be committed.',
      child: Column(children: [
        for (final (name, def, meaning) in _vars)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: EE.line))),
            child: narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SelectableText(name, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.ice)),
                    const SizedBox(height: 2),
                    Text('default: $def', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11, color: EE.textDim)),
                    const SizedBox(height: 2),
                    Text(meaning, style: const TextStyle(fontSize: 12, color: EE.textMuted)),
                  ])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 300, child: SelectableText(name, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, color: EE.ice))),
                    SizedBox(width: 200, child: Text(def, style: const TextStyle(fontFamily: EE.fontMono, fontSize: 11.5, color: EE.textDim))),
                    Expanded(child: Text(meaning, style: const TextStyle(fontSize: 12.5, color: EE.textMuted))),
                  ]),
          ),
      ]),
    );
  }
}
