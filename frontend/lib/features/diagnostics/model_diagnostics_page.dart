import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import 'diagnostics_tests.dart';
import 'diagnostics_widgets.dart';
import 'logs_panel.dart';

final _diagnosticsProvider = FutureProvider<Json>((ref) => ref.watch(apiProvider).diagnostics());

/// Model Diagnostics — real detector/OCR/pipeline state, live test operations and logs.
class ModelDiagnosticsPage extends ConsumerStatefulWidget {
  const ModelDiagnosticsPage({super.key});
  @override
  ConsumerState<ModelDiagnosticsPage> createState() => _ModelDiagnosticsPageState();
}

class _ModelDiagnosticsPageState extends ConsumerState<ModelDiagnosticsPage> {
  bool _loadingModels = false;

  void _refresh() {
    ref.invalidate(_diagnosticsProvider);
    ref.read(systemStatusProvider.notifier).refresh();
  }

  Future<void> _loadModels() async {
    setState(() => _loadingModels = true);
    try {
      final r = await ref.read(apiProvider).loadModels();
      if (!mounted) return;
      final det = r['detector_loaded'] == true;
      final ocr = r['ocr_loaded'] == true;
      showSnack(context, 'Detector ${det ? 'loaded' : 'NOT loaded'} · OCR ${ocr ? 'loaded' : 'NOT loaded'}', error: !(det && ocr));
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loadingModels = false);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final diag = ref.watch(_diagnosticsProvider);
    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      PageHeader(
        eyebrow: 'System · Models',
        title: 'Model Diagnostics',
        description: 'Live state of the YOLOv8 detector, the OCR engine and the pipeline libraries as reported by the running backend. '
            'States come from actual load attempts and inference — never from configuration flags alone.',
        actions: [
          OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, size: 17), label: const Text('Refresh')),
          FilledButton.icon(
            onPressed: _loadingModels ? null : _loadModels,
            icon: _loadingModels
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: EE.bg0))
                : const Icon(Icons.download_for_offline_outlined, size: 17),
            label: Text(_loadingModels ? 'Loading models…' : 'Load models now'),
          ),
        ],
      ),
      AsyncView<Json>(
        diag,
        onRetry: _refresh,
        loadingLabel: 'Querying diagnostics',
        data: (d) => _DiagnosticsBody(d),
      ),
      const SizedBox(height: EE.s4),
      const Padding(
        padding: EdgeInsets.only(bottom: 10, top: 6),
        child: Eyebrow('Test operations'),
      ),
      ResponsiveRow(breakpoint: 1180, children: [
        ModelTestCard(kind: 'detector', onCompleted: _refresh),
        ModelTestCard(kind: 'ocr', onCompleted: _refresh),
      ]),
      const SizedBox(height: EE.s4),
      const LogsPanel(),
    ]);
  }
}

class _DiagnosticsBody extends StatelessWidget {
  const _DiagnosticsBody(this.d);
  final Json d;

  @override
  Widget build(BuildContext context) {
    final det = d.obj('detector');
    final ocr = d.obj('ocr');
    final pipe = d.obj('pipeline');
    final limitations = det.strs('limitations');
    final metrics = det.objN('training_metrics');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ResponsiveRow(breakpoint: 1180, children: [_DetectorPanel(det), _OcrPanel(ocr)]),
      if (limitations.isNotEmpty) ...[
        const SizedBox(height: EE.s4),
        Callout(
          title: 'Detector limitations (reported by the backend)',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final l in limitations) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('•  $l')),
          ]),
        ),
      ],
      if (metrics != null) ...[const SizedBox(height: EE.s4), _MetricsPanel(metrics)],
      const SizedBox(height: EE.s4),
      _PipelinePanel(pipe),
    ]);
  }
}

String _kindLabel(String k) => switch (k) {
      'custom' => 'CUSTOM CABINET WEIGHTS',
      'generic_coco' => 'GENERIC COCO — NO CABINET CLASSES',
      _ => 'NO MODEL LOADED',
    };

Color _kindColor(String k) => switch (k) {
      'custom' => EE.cyan,
      'generic_coco' => EE.uncertain,
      _ => EE.textDim,
    };

class _DetectorPanel extends StatelessWidget {
  const _DetectorPanel(this.det);
  final Json det;

  @override
  Widget build(BuildContext context) {
    final state = det.str('state', 'unknown');
    final kind = det.str('kind', 'none');
    final classes = det.strs('classes');
    final supported = det.strs('supported_cabinet_classes').toSet();
    final tiling = det.obj('tiling');
    final err = det.strN('last_error');
    final shown = classes.length > 30 ? classes.sublist(0, 30) : classes;
    return Panel(
      eyebrow: 'Object detection',
      title: 'YOLOv8 detector',
      actions: [StatePill(state, label: stateLabels[state == 'loaded' ? 'ok' : state] ?? state)],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerLeft, child: Tag(_kindLabel(kind), color: _kindColor(kind), filled: true, mono: true)),
        const SizedBox(height: 10),
        KV('Model', det.strN('model_name'), mono: true),
        KV('Loaded weights', det.strN('weights_path'), mono: true),
        KV('Configured weights', '${dv(det['configured_weights'])}  ·  ${det.boolean('configured_weights_exists') ? 'file present' : 'file missing'}',
            mono: true, valueColor: det.boolean('configured_weights_exists') ? EE.text : EE.uncertain),
        KV('Fallback weights', '${dv(det['fallback_weights'])}  ·  ${det.boolean('fallback_weights_exists') ? 'file present' : 'file missing'}',
            mono: true, valueColor: det.boolean('fallback_weights_exists') ? EE.text : EE.uncertain),
        KV('Device', det.strN('device'), mono: true),
        const Hairline(vertical: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          MiniStat('Conf threshold', dv(det['conf_threshold'])),
          MiniStat('IoU (NMS)', dv(det['iou_threshold'])),
          MiniStat('Stored ≥', dv(det['min_store_conf'])),
          MiniStat('Input size', '${dv(det['imgsz'])} px'),
          MiniStat('Tiling', tiling.boolean('enabled') ? '${dv(tiling['tile_size'])} px · ${pct(tiling.dbl('overlap'))}' : 'off'),
        ]),
        const SizedBox(height: 8),
        KV('Load time', fmtMs(det.intN('load_ms'))),
        KV('Loaded at', fmtTime(det.time('loaded_at'))),
        KV('Last inference', det.intN('last_inference_ms') == null ? null : '${fmtMs(det.intN('last_inference_ms'))} · ${ago(det.time('last_inference_at'))}'),
        KV('Last error', err, valueColor: err == null ? null : EE.fail),
        const Hairline(vertical: 6),
        Row(children: [
          Text('MODEL CLASSES (${classes.length})', style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10, letterSpacing: 1.1, color: EE.textMuted)),
          const Spacer(),
          if (classes.isNotEmpty)
            Text('${supported.length} cabinet classes supported', style: TextStyle(fontSize: 11.5, color: supported.isEmpty ? EE.uncertain : EE.pass)),
        ]),
        const SizedBox(height: 8),
        if (classes.isEmpty)
          const Text('No model loaded — classes are listed once the detector loads.', style: TextStyle(fontSize: 12.5, color: EE.textDim))
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in shown)
              Tag(c, mono: true, color: supported.contains(c) ? EE.detClass(c) : EE.textDim, filled: supported.contains(c)),
            if (classes.length > shown.length) Tag('+${classes.length - shown.length} more', color: EE.textDim),
          ]),
      ]),
    );
  }
}

class _OcrPanel extends StatelessWidget {
  const _OcrPanel(this.ocr);
  final Json ocr;

  @override
  Widget build(BuildContext context) {
    final state = ocr.str('state', 'unknown');
    final errors = ocr.obj('engine_errors');
    final err = ocr.strN('last_error');
    final engine = ocr.strN('engine');
    return Panel(
      eyebrow: 'Text recognition',
      title: 'OCR engine',
      actions: [StatePill(state, label: stateLabels[state == 'loaded' ? 'ok' : state] ?? state)],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          Tag(engine == null ? 'NO ENGINE ACTIVE' : '${engine.toUpperCase()} ${ocr.str('engine_version')}', mono: true, filled: true, color: engine == null ? EE.textDim : EE.cyan),
          Tag('preference: ${ocr.str('preference', 'auto')}', mono: true),
        ]),
        const SizedBox(height: 10),
        KV('Languages', ocr.strs('languages').join(', ')),
        KV('GPU', ocr.boolean('gpu') ? 'enabled' : 'disabled (CPU)'),
        KV('Model directory', ocr.strN('model_dir'), mono: true),
        KV('Allowlist', ocr.strN('allowlist'), mono: true),
        KV('Exclude I / O', ocr.boolean('exclude_io') ? 'yes' : 'no'),
        if (ocr.boolean('exclude_io'))
          const Padding(
            padding: EdgeInsets.only(left: 150, bottom: 4),
            child: Text(
              'IEC 81346 reference designations avoid the letters I and O because they are easily confused with 1 and 0, so they are removed '
              'from the recognition allowlist. Disable with EAGLEEYE_OCR_EXCLUDE_IO=false if your identifiers use them.',
              style: TextStyle(fontSize: 11.5, color: EE.textDim, height: 1.45),
            ),
          ),
        const Hairline(vertical: 6),
        KV('Load time', fmtMs(ocr.intN('load_ms'))),
        KV('Loaded at', fmtTime(ocr.time('loaded_at'))),
        KV('Last success', ocr.time('last_success_at') == null ? null : '${fmtTime(ocr.time('last_success_at'))} · ${ago(ocr.time('last_success_at'))}'),
        KV('Last duration', fmtMs(ocr.intN('last_duration_ms'))),
        KV('Last error', err, valueColor: err == null ? null : EE.fail),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 8),
          Callout(
            title: 'Engines that could not be used',
            icon: Icons.info_outline_rounded,
            color: errors.length > 1 || engine == null ? EE.fail : EE.uncertain,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in errors.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${e.key}: ', style: const TextStyle(fontFamily: EE.fontMono, fontWeight: FontWeight.w600)),
                    TextSpan(text: '${e.value}'),
                  ])),
                ),
              if (engine != null) Text('The pipeline uses $engine instead; results record which engine produced each observation.', style: const TextStyle(color: EE.textMuted)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel(this.m);
  final Json m;

  @override
  Widget build(BuildContext context) {
    final perClass = m.obj('per_class');
    String f(Object? v) => v is num ? v.toStringAsFixed(3) : '—';
    return Panel(
      eyebrow: 'Training run · synthetic validation',
      title: 'Detector training metrics',
      accent: EE.uncertain,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Callout(
          title: 'Measured on synthetic renders; not validated on real cabinet photographs',
          child: Text(
            'These figures come from a held-out split of procedurally generated cabinet images. They show the training run converged; they are '
            'NOT an accuracy figure for real inspections and must not be presented as one.${m.strN('caveat') != null ? '\nBackend caveat: ${m.str('caveat')}' : ''}',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          MiniStat('mAP@50 (synthetic val)', f(m['mAP50'])),
          MiniStat('mAP@50-95 (synthetic val)', f(m['mAP50_95'])),
          MiniStat('Precision (synthetic val)', f(m['precision'])),
          MiniStat('Recall (synthetic val)', f(m['recall'])),
        ]),
        const SizedBox(height: 10),
        KV('Dataset', m.strN('dataset')),
        KV('Validation split', m.strN('validation_split')),
        KV('Base weights', m.strN('base_weights'), mono: true),
        KV('Epochs · input size', '${dv(m['epochs_requested'])} · ${dv(m['imgsz'])} px'),
        KV('Training time', m.dbl('training_seconds') == null ? null : fmtMs(((m.dbl('training_seconds') ?? 0) * 1000).round())),
        if (perClass.isNotEmpty) ...[
          const SizedBox(height: 10),
          DenseTable(
            columns: const ['Class', 'mAP@50', 'mAP@50-95'],
            flex: const [4, 2, 2],
            maxHeight: 280,
            rows: [
              for (final e in perClass.entries)
                [
                  Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: EE.detClass(e.key), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Flexible(child: Text(e.key, style: monoCell, overflow: TextOverflow.ellipsis)),
                  ]),
                  Text(f((e.value as Map)['mAP50']), style: monoCell),
                  Text(f((e.value as Map)['mAP50_95']), style: monoCell),
                ],
            ],
          ),
        ],
      ]),
    );
  }
}

class _PipelinePanel extends StatelessWidget {
  const _PipelinePanel(this.p);
  final Json p;

  @override
  Widget build(BuildContext context) {
    final limits = p.obj('limits_mb');
    return Panel(
      eyebrow: 'Pipeline',
      title: 'Processing libraries & limits',
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        MiniStat('OpenCV', dv(p['opencv'])),
        MiniStat('Keypoints', p.boolean('sift_available') ? 'SIFT + ORB' : 'ORB only', color: p.boolean('sift_available') ? EE.pass : EE.uncertain),
        MiniStat('Max processing side', '${dv(p['max_processing_side'])} px'),
        MiniStat('Job workers', dv(p['job_workers'])),
        MiniStat('Photo limit', '${dv(limits['photo'])} MB'),
        MiniStat('Drawing limit', '${dv(limits['drawing'])} MB'),
        MiniStat('List limit', '${dv(limits['expected_list'])} MB'),
        MiniStat('Database', dv(p['database_dialect'])),
        MiniStat('Environment', dv(p['environment'])),
      ]),
    );
  }
}
