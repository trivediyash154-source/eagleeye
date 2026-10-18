import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/image_viewer.dart';
import '../../core/widgets/inspection_scope.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/states.dart';
import '../detection/analysis_common.dart';
import 'alignment_tool.dart';
import 'zone_editor.dart';

Color zoneColor(String source) => switch (source) {
      'manual' => EE.uncertain,
      'derived_from_components' => EE.violet,
      _ => EE.cyan,
    };

String zoneSourceLabel(String source) => switch (source) {
      'manual' => 'Manual (inspector)',
      'derived_from_components' => 'Derived from components',
      'drawing_frame' => 'Drawing frame',
      _ => source,
    };

const _identColor = Color(0xFFF2F5FA);

class DrawingPage extends StatelessWidget {
  const DrawingPage({super.key, this.inspectionId, this.versionNo});
  final String? inspectionId;
  final int? versionNo;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PageHeader(
        eyebrow: 'Analyze · GA drawing',
        title: 'Drawing Intelligence',
        description: 'What was extracted from the GA drawing — zones, located identifiers and text — and how it maps onto the cabinet photograph. '
            'Zone definitions can be corrected, and a manual anchor alignment can replace a failed automatic registration.',
      ),
      Expanded(
        child: InspectionScope(
          inspectionId: inspectionId,
          versionNo: versionNo,
          onSelect: (i, v) => context.go(i.isEmpty ? '/console/drawing' : scopedLink('/console/drawing', i, version: v)),
          pickerTitle: 'Select an inspection to analyse its GA drawing',
          requireCompleted: false,
          builder: (ctx, insp, ver) => _DrawingWorkbench(key: ValueKey(ver.id), inspection: insp, version: ver),
        ),
      ),
    ]);
  }
}

class _DrawingWorkbench extends ConsumerStatefulWidget {
  const _DrawingWorkbench({super.key, required this.inspection, required this.version});
  final Inspection inspection;
  final Version version;
  @override
  ConsumerState<_DrawingWorkbench> createState() => _DrawingWorkbenchState();
}

class _DrawingWorkbenchState extends ConsumerState<_DrawingWorkbench> {
  String _view = 'drawing';
  String _tab = 'registration';
  String? _selected;
  final Set<String> _layers = {'zones', 'components', 'identifiers'};
  bool _aligning = false;
  final List<Offset> _zonePick = [];
  bool _pickingZone = false;
  final _spanQuery = TextEditingController();

  Version get v => widget.version;

  @override
  void dispose() {
    _spanQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    final drawing = ref.watch(drawingProvider(v.id));
    final media = ref.watch(mediaProvider(v.id));
    if (drawing.hasError) return ErrorView(drawing.error!, onRetry: () => ref.invalidate(drawingProvider(v.id)));
    if (!drawing.hasValue) return const LoadingView(label: 'Loading drawing analysis');
    final d = drawing.requireValue;
    if (!d.boolean('parsed')) return _UnparsedDrawing(data: d, version: v);
    final mediaJson = media.value ?? const <String, dynamic>{};
    final dr = d.obj('drawing');
    final scale = dr.dbl('render_scale') ?? 1.0;
    final renderEv = mediaImage(api, mediaJson, 'drawing_page');
    final renderUrl = api.url(dr.str('render_url'));
    final renderSize = renderEv?.size ?? Size((dr.dbl('width') ?? 1) * scale, (dr.dbl('height') ?? 1) * scale);
    final photo = mediaImage(api, mediaJson, 'original_photo');
    final reg = d.obj('registration');
    final usable = reg.boolean('usable');

    if (_aligning) {
      return AlignmentTool(
        version: v,
        drawingUrl: renderUrl,
        drawingSize: renderSize,
        renderScale: scale,
        photo: photo,
        registration: reg,
        onCancel: () => setState(() => _aligning = false),
      );
    }

    final zones = d.objs('zones');
    final comps = d.objs('components');
    final idents = d.objs('identifiers');
    final spans = dr.objs('text_spans');

    List<double>? sc(List<double>? b) => b?.map((x) => x * scale).toList();

    final drawingOverlays = <ImgOverlay>[
      if (_layers.contains('zones'))
        for (final z in zones)
          ImgOverlay(id: 'zone:${z.str('id')}', box: sc(z.box('bbox')), color: zoneColor(z.str('source')), label: '${z.str('code')} ${z.strN('name') ?? ''}'.trim(), dashed: true, fillAlpha: 0.03),
      if (_layers.contains('components'))
        for (final c in comps)
          if (c.box('drawing_bbox') != null) ImgOverlay(id: 'comp:${c.str('id')}', box: sc(c.box('drawing_bbox')), color: EE.ice, label: c.str('tag')),
      if (_layers.contains('identifiers'))
        for (final i in idents)
          if (i.box('drawing_bbox') != null) ImgOverlay(id: 'ident:${i.str('id')}', box: sc(i.box('drawing_bbox')), color: _identColor, label: i.strN('value') ?? i.str('terminal_ref')),
      if (_selected != null && _selected!.startsWith('span:'))
        () {
          final idx = int.tryParse(_selected!.substring(5)) ?? -1;
          final b = idx >= 0 && idx < spans.length ? spans[idx].box('bbox') : null;
          return ImgOverlay(id: _selected!, box: sc(b), color: EE.ultraviolet, label: idx >= 0 && idx < spans.length ? spans[idx].str('text') : null);
        }(),
    ];
    final photoOverlays = !usable
        ? const <ImgOverlay>[]
        : <ImgOverlay>[
            if (_layers.contains('zones'))
              for (final z in zones)
                if (quadOf(z, 'projected_quad') != null)
                  ImgOverlay(id: 'zone:${z.str('id')}', quad: quadOf(z, 'projected_quad'), color: zoneColor(z.str('source')), label: z.str('code'), dashed: true, fillAlpha: 0.04),
            if (_layers.contains('components'))
              for (final c in comps)
                if (quadOf(c, 'projected_quad') != null) ImgOverlay(id: 'comp:${c.str('id')}', quad: quadOf(c, 'projected_quad'), color: EE.ice, label: c.str('tag')),
            if (_layers.contains('identifiers'))
              for (final i in idents)
                if (quadOf(i, 'projected_quad') != null)
                  ImgOverlay(id: 'ident:${i.str('id')}', quad: quadOf(i, 'projected_quad'), color: _identColor, label: i.strN('value') ?? i.str('terminal_ref')),
          ];

    final drawingViewer = OverlayImageViewer(
      key: const ValueKey('drawing-viewer'),
      url: renderUrl,
      imageSize: renderSize,
      overlays: drawingOverlays,
      selectedId: _selected,
      onSelect: _pickingZone ? null : (id) => setState(() => _selected = id),
      onImageTap: _pickingZone ? (p) => _onZonePick(p, scale, zones) : null,
      markers: [for (var k = 0; k < _zonePick.length; k++) ImgMarker(_zonePick[k], 'corner ${k + 1}', color: EE.uncertain)],
      background: const Color(0xFFF7F8FA),
      caption: 'GA drawing · page ${dr.integer('page_index') + 1}/${dr.integer('page_count', 1)} · ${dr.str('kind')} · ${scale.toStringAsFixed(2)} px/pt',
    );
    Widget photoViewer() {
      if (photo == null) return const EmptyState(title: 'No photo evidence for this version', icon: Icons.image_not_supported_outlined);
      return Stack(children: [
        Positioned.fill(
          child: OverlayImageViewer(
            key: const ValueKey('photo-viewer'),
            url: photo.url,
            imageSize: photo.size,
            overlays: photoOverlays,
            selectedId: _selected,
            onSelect: (id) => setState(() => _selected = id),
            caption: usable ? 'Photo · drawing geometry projected with ${reg.str('method')}' : 'Photo · no validated registration',
          ),
        ),
        if (!usable)
          Positioned(
            left: 12,
            right: 60,
            top: 12,
            child: NoticeBanner(
              title: 'Cross-view mapping unavailable',
              lines: ['Registration status "${reg.strN('status') ?? 'not run'}": drawing zones cannot be placed on the photo.', ...reg.strs('reasons').take(2)],
              color: EE.uncertain,
              trailing: TextButton(onPressed: () => setState(() => _aligning = true), child: const Text('Align manually')),
            ),
          ),
      ]);
    }

    final visual = Panel(
      eyebrow: 'Drawing ↔ photo',
      title: _pickingZone ? 'Click two opposite corners of the new zone on the drawing' : (_view == 'drawing' ? 'GA drawing' : (_view == 'photo' ? 'Cabinet photograph' : 'Split view')),
      expand: true,
      padding: const EdgeInsets.all(EE.s3),
      accent: _pickingZone ? EE.uncertain : null,
      actions: [
        if (_pickingZone) TextButton(onPressed: () => setState(() {
              _pickingZone = false;
              _zonePick.clear();
            }), child: const Text('Cancel')),
        SegToggle<String>(values: const {'drawing': 'Drawing', 'split': 'Split', 'photo': 'Photo'}, value: _view, dense: true, onChanged: (x) => setState(() => _view = x)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final l in const [('zones', 'Zones'), ('components', 'Components'), ('identifiers', 'Ferrules')])
            FilterChip(
              label: Text(l.$2),
              selected: _layers.contains(l.$1),
              visualDensity: VisualDensity.compact,
              onSelected: (on) => setState(() => on ? _layers.add(l.$1) : _layers.remove(l.$1)),
            ),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            if (_view == 'drawing') return drawingViewer;
            if (_view == 'photo') return photoViewer();
            final horizontal = c.maxWidth >= 700;
            final children = [Expanded(child: drawingViewer), SizedBox(width: horizontal ? 8 : 0, height: horizontal ? 0 : 8), Expanded(child: photoViewer())];
            return horizontal ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
          }),
        ),
      ]),
    );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final sideChildren = <Widget>[
        if (_selected != null) ...[_selectionCard(zones, comps, idents, spans, reg), const SizedBox(height: EE.s3)],
        _tabs(),
        const SizedBox(height: EE.s3),
        switch (_tab) {
          'registration' => _RegistrationCard(reg: reg, onAlign: () => setState(() => _aligning = true)),
          'zones' => _zonesPanel(zones, dr),
          'components' => _componentsPanel(comps),
          'identifiers' => _identifiersPanel(idents),
          'text' => _textPanel(spans),
          _ => _warningsPanel(dr),
        },
      ];
      final side = wide ? ListView(padding: EdgeInsets.zero, children: sideChildren) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sideChildren);
      return AnalysisLayout(visual: visual, side: side, sideWidth: 400, narrowVisualHeight: 480);
    });
  }

  // --- zone picking -----------------------------------------------------------------
  Future<void> _onZonePick(Offset p, double scale, List<Json> zones) async {
    setState(() => _zonePick.add(p));
    if (_zonePick.length < 2) return;
    final a = _zonePick[0], b = _zonePick[1];
    final bbox = [a.dx / scale, a.dy / scale, b.dx / scale, b.dy / scale];
    setState(() {
      _pickingZone = false;
      _zonePick.clear();
    });
    await _openEditor(zones, newBbox: bbox);
  }

  Future<void> _openEditor(List<Json> zones, {List<double>? newBbox}) async {
    final msg = await showDialog<String>(
      context: context,
      builder: (_) => ZoneEditorDialog(versionId: v.id, zones: zones, versionStatus: v.status, newBbox: newBbox),
    );
    if (msg != null && mounted) {
      showSnack(context, msg);
      ref.invalidate(drawingProvider(v.id));
    }
  }

  // --- side panel parts -------------------------------------------------------------
  Widget _tabs() {
    const tabs = {'registration': 'Registration', 'zones': 'Zones', 'components': 'Components', 'identifiers': 'Ferrules', 'text': 'Text', 'warnings': 'Parse info'};
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final t in tabs.entries)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(EE.r1),
              onTap: () => setState(() => _tab = t.key),
              child: AnimatedContainer(
                duration: EE.fast,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: _tab == t.key ? EE.cyan : Colors.transparent, width: 2)),
                ),
                child: Text(t.value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _tab == t.key ? EE.text : EE.textMuted)),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _selectionCard(List<Json> zones, List<Json> comps, List<Json> idents, List<Json> spans, Json reg) {
    final id = _selected!;
    final usable = reg.boolean('usable');
    String title = id, eyebrow = 'Selection';
    final rows = <Widget>[];
    List<List<double>>? quad;
    if (id.startsWith('zone:')) {
      final z = zones.where((x) => 'zone:${x.str('id')}' == id).firstOrNull;
      if (z != null) {
        eyebrow = 'Zone';
        title = '${z.str('code')} ${z.strN('name') ?? ''}'.trim();
        quad = quadOf(z, 'projected_quad');
        rows.addAll([
          KV('Source', zoneSourceLabel(z.str('source')), keyWidth: 110),
          KV('BBox (pt)', fmtBox(z.box('bbox'), digits: 1), mono: true, keyWidth: 110),
          if (z.strN('notes') != null) KV('Notes', z.str('notes'), keyWidth: 110),
          KV('Components', comps.where((c) => c.strN('zone_code') == z.str('code')).map((c) => c.str('tag')).join(', '), keyWidth: 110),
        ]);
      }
    } else if (id.startsWith('comp:')) {
      final c = comps.where((x) => 'comp:${x.str('id')}' == id).firstOrNull;
      if (c != null) {
        eyebrow = 'Expected component';
        title = c.str('tag');
        quad = quadOf(c, 'projected_quad');
        rows.addAll([
          KV('Type', c.strN('component_type'), keyWidth: 110),
          KV('Detector class', c.strN('canonical_class') == null ? 'not mapped' : titleCase(c.str('canonical_class')), keyWidth: 110),
          KV('Expected label', c.strN('expected_label'), mono: true, keyWidth: 110),
          KV('Zone', c.strN('zone_code'), keyWidth: 110),
          KV('Body (pt)', fmtBox(c.box('drawing_bbox'), digits: 1), mono: true, keyWidth: 110),
          KV('Label (pt)', fmtBox(c.box('drawing_label_bbox'), digits: 1), mono: true, keyWidth: 110),
          KV('Located by', c.strN('drawing_match'), mono: true, keyWidth: 110),
          KV('Source', c.strN('source'), keyWidth: 110),
        ]);
      }
    } else if (id.startsWith('ident:')) {
      final i = idents.where((x) => 'ident:${x.str('id')}' == id).firstOrNull;
      if (i != null) {
        eyebrow = 'Expected ferrule';
        title = i.strN('value') ?? i.str('terminal_ref');
        quad = quadOf(i, 'projected_quad');
        rows.addAll([
          KV('Terminal', i.strN('terminal_ref'), mono: true, keyWidth: 110),
          KV('Wire colour', i.strN('wire_color'), keyWidth: 110),
          KV('From device', i.strN('component_tag'), keyWidth: 110),
          KV('Marker (pt)', fmtBox(i.box('drawing_bbox'), digits: 1), mono: true, keyWidth: 110),
          KV('Terminal (pt)', fmtBox(i.box('drawing_terminal_bbox'), digits: 1), mono: true, keyWidth: 110),
          KV('Located by', i.strN('drawing_match'), mono: true, keyWidth: 110),
        ]);
      }
    } else if (id.startsWith('span:')) {
      final idx = int.tryParse(id.substring(5)) ?? -1;
      if (idx >= 0 && idx < spans.length) {
        eyebrow = 'Text span';
        title = spans[idx].str('text');
        rows.addAll([KV('BBox (pt)', fmtBox(spans[idx].box('bbox'), digits: 2), mono: true, keyWidth: 110), KV('Source', spans[idx].str('source'), keyWidth: 110)]);
      }
    }
    final projectable = !id.startsWith('span:');
    return Panel(
      eyebrow: eyebrow,
      title: title,
      accent: EE.cyan,
      actions: [IconButton(tooltip: 'Clear selection', onPressed: () => setState(() => _selected = null), icon: const Icon(Icons.close_rounded, size: 16))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...rows,
        if (projectable) ...[
          const SizedBox(height: 6),
          if (usable && quad != null)
            Row(children: [
              const Icon(Icons.check_circle_outline_rounded, size: 15, color: EE.pass),
              const SizedBox(width: 6),
              const Expanded(child: Text('Projected onto the photo with the validated registration.', style: TextStyle(fontSize: 12, color: EE.textMuted))),
              if (_view == 'drawing') TextButton(onPressed: () => setState(() => _view = 'split'), child: const Text('Show on photo')),
            ])
          else if (!usable)
            const Text('Not shown on the photo: no validated photo-to-drawing registration exists for this version.', style: TextStyle(fontSize: 12, color: EE.uncertain))
          else
            const Text('Not located in the drawing, so it has no projected position.', style: TextStyle(fontSize: 12, color: EE.uncertain)),
        ],
      ]),
    );
  }

  Widget _zonesPanel(List<Json> zones, Json dr) {
    return Panel(
      eyebrow: 'Zones',
      title: '${zones.length} zone${zones.length == 1 ? '' : 's'}',
      actions: [
        TextButton.icon(
          onPressed: () => setState(() {
            _pickingZone = true;
            _zonePick.clear();
            _view = 'drawing';
          }),
          icon: const Icon(Icons.highlight_alt_rounded, size: 16),
          label: const Text('Draw'),
        ),
        TextButton.icon(onPressed: () => _openEditor(zones), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (zones.isEmpty)
          const NoticeBanner(
            title: 'No zones defined',
            lines: ['No zone frames were found in the drawing and none could be derived from component positions. Define zones manually (Draw or Edit).'],
          ),
        for (final z in zones)
          _ListRow(
            selected: _selected == 'zone:${z.str('id')}',
            onTap: () => setState(() => _selected = 'zone:${z.str('id')}'),
            leading: Container(width: 3, height: 26, color: zoneColor(z.str('source'))),
            title: '${z.str('code')}  ${z.strN('name') ?? ''}',
            subtitle: '${zoneSourceLabel(z.str('source'))} · ${fmtBox(z.box('bbox'))} pt',
            trailing: quadOf(z, 'projected_quad') != null ? const Tooltip(message: 'Projected onto photo', child: Icon(Icons.photo_outlined, size: 14, color: EE.pass)) : null,
          ),
        const SizedBox(height: 8),
        Text(
          v.editable
              ? 'Zone edits for this ${v.status} version are used when it runs.'
              : 'This version is ${v.status}: corrections are saved on the drawing record and applied by the next reinspection. Existing findings are not changed.',
          style: const TextStyle(fontSize: 11, color: EE.textDim, height: 1.4),
        ),
      ]),
    );
  }

  Widget _componentsPanel(List<Json> comps) {
    final missing = comps.where((c) => c.strN('drawing_match') == 'not_found').length;
    return Panel(
      eyebrow: 'Expected components',
      title: '${comps.length} from the specification',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (missing > 0) ...[
          NoticeBanner(title: '$missing component(s) not located in the drawing', lines: const ['Their position-based checks cannot use a drawing location and will be UNCERTAIN.']),
          const SizedBox(height: 8),
        ],
        for (final c in comps)
          _ListRow(
            selected: _selected == 'comp:${c.str('id')}',
            onTap: c.box('drawing_bbox') == null ? null : () => setState(() => _selected = 'comp:${c.str('id')}'),
            leading: Container(width: 3, height: 26, color: c.strN('canonical_class') == null ? EE.textDim : EE.detClass(c.str('canonical_class'))),
            title: '${c.str('tag')}${c.integer('quantity', 1) > 1 ? ' ×${c.integer('quantity')}' : ''}',
            subtitle: '${c.strN('zone_code') ?? '—'} · ${c.strN('component_type') ?? 'no type'} · label ${c.strN('expected_label') ?? '—'}',
            trailing: c.strN('drawing_match') == 'not_found'
                ? const Tag('not found', color: EE.uncertain)
                : Tag(c.strN('drawing_match') ?? '—', color: EE.textMuted, mono: true),
          ),
      ]),
    );
  }

  Widget _identifiersPanel(List<Json> idents) {
    final missing = idents.where((c) => c.strN('drawing_match') == 'not_found').length;
    return Panel(
      eyebrow: 'Expected ferrules / terminals',
      title: '${idents.length} wire-list records',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (missing > 0) ...[
          NoticeBanner(title: '$missing record(s) not located in the drawing', lines: const ['Ferrule checks for them have no expected position and stay UNCERTAIN.']),
          const SizedBox(height: 8),
        ],
        if (idents.isEmpty) const Text('No wire-list records for this version.', style: TextStyle(fontSize: 12, color: EE.textDim)),
        for (final i in idents)
          _ListRow(
            selected: _selected == 'ident:${i.str('id')}',
            onTap: i.box('drawing_bbox') == null ? null : () => setState(() => _selected = 'ident:${i.str('id')}'),
            leading: Container(width: 3, height: 26, color: _identColor.withValues(alpha: 0.7)),
            title: i.strN('value') ?? '(no ferrule text)',
            subtitle: '${i.strN('terminal_ref') ?? '—'} · ${i.strN('wire_color') ?? 'no colour'} · ${i.strN('zone_code') ?? '—'}',
            mono: true,
            trailing: i.strN('drawing_match') == 'not_found' ? const Tag('not found', color: EE.uncertain) : Tag(i.strN('drawing_match') ?? '—', color: EE.textMuted, mono: true),
          ),
      ]),
    );
  }

  Widget _textPanel(List<Json> spans) {
    final q = _spanQuery.text.trim().toUpperCase();
    final idx = <int>[for (var k = 0; k < spans.length; k++) if (q.isEmpty || spans[k].str('text').toUpperCase().contains(q)) k];
    return Panel(
      eyebrow: 'Extracted text',
      title: '${spans.length} words',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _spanQuery,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12.5),
          decoration: const InputDecoration(hintText: 'Search drawing text', prefixIcon: Icon(Icons.search_rounded, size: 18)),
        ),
        const SizedBox(height: 6),
        const Text('Coordinates in PDF points, origin top-left, y downward.', style: TextStyle(fontSize: 11, color: EE.textDim)),
        const SizedBox(height: 6),
        for (final k in idx.take(300))
          _ListRow(
            selected: _selected == 'span:$k',
            onTap: () => setState(() {
              _selected = 'span:$k';
              _view = _view == 'photo' ? 'drawing' : _view;
            }),
            title: spans[k].str('text'),
            subtitle: '${fmtBox(spans[k].box('bbox'), digits: 1)} · ${spans[k].str('source')}',
            mono: true,
          ),
        if (idx.length > 300) Padding(padding: const EdgeInsets.all(6), child: Text('Showing 300 of ${idx.length} matches — refine the search.', style: const TextStyle(fontSize: 11, color: EE.textDim))),
      ]),
    );
  }

  Widget _warningsPanel(Json dr) {
    final stats = dr.obj('stats');
    final warnings = dr.objs('warnings');
    return Panel(
      eyebrow: 'Parse information',
      title: '${dr.str('kind')} page',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KV('Page', '${dr.integer('page_index') + 1} of ${dr.integer('page_count', 1)}', keyWidth: 130),
        KV('Page size', '${(dr.dbl('width') ?? 0).toStringAsFixed(1)} × ${(dr.dbl('height') ?? 0).toStringAsFixed(1)} pt', mono: true, keyWidth: 130),
        KV('Coordinates', dr.strN('coordinate_convention'), keyWidth: 130),
        KV('Render scale', '${(dr.dbl('render_scale') ?? 0).toStringAsFixed(2)} px per pt', mono: true, keyWidth: 130),
        for (final e in stats.entries) KV(titleCase(e.key), '${e.value}', mono: true, keyWidth: 130),
        const SubHead('Warnings'),
        if (warnings.isEmpty)
          const Text('No parse warnings.', style: TextStyle(fontSize: 12, color: EE.textDim))
        else
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, size: 15, color: EE.uncertain),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(w.str('message'), style: const TextStyle(fontSize: 12, height: 1.4)),
                    Text(w.str('code'), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.textDim)),
                  ]),
                ),
              ]),
            ),
        const SizedBox(height: 8),
        const Text('Arbitrary engineering drawings are not guaranteed to be interpreted automatically; zone and identifier extraction is heuristic and '
            'should be checked here before relying on position-based findings.', style: TextStyle(fontSize: 11, color: EE.textDim, height: 1.4)),
      ]),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.title, this.subtitle, this.leading, this.trailing, this.onTap, this.selected = false, this.mono = false});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool mono;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(EE.r1),
        child: AnimatedContainer(
          duration: EE.fast,
          margin: const EdgeInsets.symmetric(vertical: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? EE.cyan.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(EE.r1),
            border: Border.all(color: selected ? EE.cyan.withValues(alpha: 0.4) : Colors.transparent),
          ),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: mono ? EE.fontMono : EE.fontBody)),
                if (subtitle != null) Text(subtitle!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: EE.textDim)),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ]),
        ),
      );
}

class _RegistrationCard extends StatelessWidget {
  const _RegistrationCard({required this.reg, required this.onAlign});
  final Json reg;
  final VoidCallback onAlign;

  @override
  Widget build(BuildContext context) {
    final status = reg.strN('status') ?? 'not_run';
    final usable = reg.boolean('usable');
    final metrics = reg.obj('metrics');
    final checks = reg.objs('checks');
    final attempts = reg.objs('attempts');
    final reasons = reg.strs('reasons');
    return Panel(
      eyebrow: 'Photo-to-drawing registration',
      title: usable ? 'Validated homography' : 'No usable registration',
      accent: usable ? EE.pass : EE.uncertain,
      actions: [StatePill(status)],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KV('Method', switch (reg.strN('method')) {
          'text_anchors' => 'Text anchors (shared identifiers) + RANSAC',
          'manual_anchors' => 'Manual anchor points (inspector)',
          final m? when m.startsWith('features') => 'Keypoint features ($m) + RANSAC',
          _ => '—',
        }, keyWidth: 120),
        if (!usable) ...[
          const SizedBox(height: 6),
          NoticeBanner(
            title: 'Why the cross-view relationship is unavailable',
            lines: [
              if (status == 'unavailable' || status == 'not_run') 'No registration was computed for this version (no GA drawing, or the registration stage did not run).',
              if (status == 'insufficient') 'A transform was estimated but failed the quality checks below, so it is not trusted.',
              if (status == 'failed') 'No transform could be estimated from the available correspondences.',
              ...reasons,
              'Position-based checks (presence, ferrules, zones) of this version are therefore UNCERTAIN — never FAIL.',
            ],
          ),
        ],
        if (metrics.isNotEmpty) ...[
          const SubHead('Metrics'),
          for (final k in const ['correspondences', 'inliers', 'inlier_ratio', 'reprojection_error_median_px', 'reprojection_error_p90_px', 'coverage_cells_3x3', 'inlier_hull_area_fraction', 'projected_page_area_ratio', 'opposite_side_ratio_max'])
            if (metrics.containsKey(k)) KV(titleCase(k), '${metrics[k]}', mono: true, keyWidth: 190),
        ],
        if (checks.isNotEmpty) ...[
          const SubHead('Plausibility checks'),
          for (final c in checks) _CheckRow(c),
        ],
        if (attempts.isNotEmpty) ...[
          const SubHead('Attempts'),
          for (final a in attempts) _AttemptTile(a),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
              usable ? 'Correct the alignment by placing your own anchor points if projections look off.' : 'Place ≥ 4 corresponding points on the drawing and the photo.',
              style: const TextStyle(fontSize: 11.5, color: EE.textMuted),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: onAlign, icon: const Icon(Icons.control_point_duplicate_rounded, size: 16), label: const Text('Manual alignment')),
        ]),
        const SizedBox(height: 6),
        Text(reg.strN('convention') ?? 'H maps drawing PDF points to original photo pixels', style: const TextStyle(fontSize: 10.5, color: EE.textDim, fontFamily: EE.fontMono)),
      ]),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.c);
  final Json c;
  @override
  Widget build(BuildContext context) {
    final passed = c.boolean('passed');
    final value = c['value'];
    final thr = c['threshold'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(passed ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 15, color: passed ? EE.pass : EE.fail),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titleCase(c.str('name')), style: const TextStyle(fontSize: 12.5)),
            if (value != null || thr != null)
              Text('value ${value ?? '—'}${thr != null ? ' · threshold $thr' : ''}${c.strN('unit') != null ? ' ${c.str('unit')}' : ''}',
                  style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, color: EE.textDim)),
            if (c.strN('detail') != null) Text(c.str('detail'), style: const TextStyle(fontSize: 10.5, color: EE.textDim)),
          ]),
        ),
      ]),
    );
  }
}

class _AttemptTile extends StatelessWidget {
  const _AttemptTile(this.a);
  final Json a;
  @override
  Widget build(BuildContext context) {
    final accepted = a.boolean('accepted');
    final failed = a.objs('checks').where((c) => !c.boolean('passed')).map((c) => titleCase(c.str('name'))).toList();
    final m = a.obj('metrics');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: EE.bg1, borderRadius: BorderRadius.circular(EE.r1), border: Border.all(color: (accepted ? EE.pass : EE.line).withValues(alpha: 0.6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(a.str('method'), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 12, fontWeight: FontWeight.w600))),
          Tag(accepted ? 'accepted' : 'rejected', color: accepted ? EE.pass : EE.fail),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            if (a['keypoints_drawing'] != null) 'keypoints ${a['keypoints_drawing']} / ${a['keypoints_photo']}',
            if (a['ratio_test_matches'] != null) '${a['ratio_test_matches']} ratio-test matches',
            if (a['candidate_pairs'] != null) '${a['candidate_pairs']} candidate text pairs',
            if (m['inliers'] != null) '${m['inliers']} inliers',
          ].join(' · '),
          style: const TextStyle(fontSize: 11, color: EE.textMuted),
        ),
        if (a.strN('error') != null) Text(a.str('error'), style: const TextStyle(fontSize: 11, color: EE.uncertain)),
        if (!accepted && failed.isNotEmpty) Text('Failed: ${failed.join(', ')}', style: const TextStyle(fontSize: 11, color: EE.fail)),
      ]),
    );
  }
}

class _UnparsedDrawing extends ConsumerStatefulWidget {
  const _UnparsedDrawing({required this.data, required this.version});
  final Json data;
  final Version version;
  @override
  ConsumerState<_UnparsedDrawing> createState() => _UnparsedDrawingState();
}

class _UnparsedDrawingState extends ConsumerState<_UnparsedDrawing> {
  int? _page;

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    final asset = widget.data.objN('asset');
    if (asset == null) {
      return EmptyState(
        title: 'No GA drawing for this version',
        message: '${widget.data.str('message')} Registration, zones and position-based checks are unavailable without a drawing.',
        icon: Icons.architecture_rounded,
      );
    }
    final an = asset.obj('analysis');
    final pages = an.objs('pages');
    final configured = widget.version.config.integer('drawing_page');
    final page = (_page ?? configured).clamp(0, (an.integer('page_count', 1) - 1).clamp(0, 1 << 20));
    final info = page < pages.length ? pages[page] : const <String, dynamic>{};
    return AnalysisLayout(
      visual: Panel(
        eyebrow: 'PDF page preview',
        title: asset.str('original_filename'),
        expand: true,
        padding: const EdgeInsets.all(EE.s3),
        actions: [
          if (an.integer('page_count', 1) > 1)
            DropdownButton<int>(
              value: page,
              dropdownColor: EE.surfaceHi,
              underline: const SizedBox(),
              items: [for (var k = 0; k < an.integer('page_count', 1); k++) DropdownMenuItem(value: k, child: Text('Page ${k + 1}${k == configured ? ' (selected for run)' : ''}'))],
              onChanged: (x) => setState(() => _page = x),
            ),
        ],
        child: OverlayImageViewer(url: api.pdfPreviewUrl(asset.str('id'), page, zoom: 1.4), background: const Color(0xFFF7F8FA), caption: 'Rendered preview · not yet parsed'),
      ),
      side: Panel(
        eyebrow: 'Drawing status',
        title: 'Not parsed yet',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.data.str('message'), style: const TextStyle(fontSize: 12.5, color: EE.textMuted, height: 1.5)),
          const SizedBox(height: 10),
          KV('Pages', '${an.integer('page_count', 1)}', keyWidth: 120),
          KV('Page for run', '${configured + 1}', keyWidth: 120),
          KV('Page content', info.strN('kind'), keyWidth: 120),
          KV('Text words', '${info['words'] ?? '—'}', mono: true, keyWidth: 120),
          KV('Vector paths', '${info['vector_paths'] ?? '—'}', mono: true, keyWidth: 120),
          KV('Images', '${info['images'] ?? '—'}', mono: true, keyWidth: 120),
          for (final w in an.objs('warnings')) Padding(padding: const EdgeInsets.only(top: 6), child: NoticeBanner(title: w.str('message'))),
          const SizedBox(height: 10),
          const Text('Zones, identifier positions and text are extracted when the inspection runs; the result appears here afterwards.', style: TextStyle(fontSize: 11.5, color: EE.textDim, height: 1.4)),
        ]),
      ),
    );
  }
}
