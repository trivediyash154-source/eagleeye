import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/widgets/file_drop.dart';

enum WizardStep { caseInfo, photo, drawing, expectedList, configure, validate, run }

extension WizardStepX on WizardStep {
  String get title =>
      const ['Case information', 'Cabinet photograph', 'GA drawing', 'Expected lists', 'Configure checks', 'Validate inputs', 'Run inspection'][index];
  String get short => const ['Case', 'Photo', 'Drawing', 'Lists', 'Checks', 'Validate', 'Run'][index];
}

/// Per-sheet mapping state for the expected-list step.
class SheetCfg {
  SheetCfg({
    required this.name,
    required this.include,
    required this.headerRow,
    required this.detectedHeaderRow,
    required this.columns,
    required this.mapping,
    required this.scores,
    required this.preview,
    required this.role,
    required this.rowCount,
  });

  factory SheetCfg.fromAnalysis(Json s, Json? saved) {
    final mapping = s.obj('mapping').map((k, v) => MapEntry(k, v as String?));
    final cfg = SheetCfg(
      name: s.str('name'),
      include: s.str('role') != 'unknown',
      headerRow: s.integer('header_row'),
      detectedHeaderRow: s.integer('header_row'),
      columns: s.strs('columns'),
      mapping: mapping,
      scores: s.obj('mapping_scores').map((k, v) => MapEntry(k, (v as num).toInt())),
      preview: s.objs('preview'),
      role: s.str('role'),
      rowCount: s.integer('row_count'),
    );
    if (saved != null) {
      cfg.include = saved['include'] as bool? ?? cfg.include;
      final hr = (saved['header_row'] as num?)?.toInt();
      final m = (saved['mapping'] as Map?)?.cast<String, dynamic>();
      if (hr == null || hr == cfg.headerRow) {
        if (m != null) {
          for (final c in cfg.columns) {
            if (m.containsKey(c)) cfg.mapping[c] = m[c] as String?;
          }
        }
      } else {
        cfg.headerRow = hr;
        if (m != null) {
          cfg.columns = m.keys.toList();
          cfg.mapping = m.map((k, v) => MapEntry(k, v as String?));
          cfg.preview = const [];
          cfg.scores = {};
        }
      }
    }
    return cfg;
  }

  final String name;
  bool include;
  int headerRow;
  final int detectedHeaderRow;
  List<String> columns;
  Map<String, String?> mapping;
  Map<String, int> scores;
  List<Json> preview;
  String role;
  final int rowCount;
  bool remapping = false;
  String? remapError;

  bool get previewMatchesHeader => headerRow == detectedHeaderRow && preview.isNotEmpty;

  String get derivedRole {
    final f = mapping.values.whereType<String>().toSet();
    if (f.contains('ferrule') || f.contains('terminal')) return 'wires';
    if (f.contains('component_id')) return 'components';
    return 'unknown';
  }

  List<String> get duplicateFields {
    final seen = <String>{}, dup = <String>{};
    for (final f in mapping.values.whereType<String>()) {
      if (!seen.add(f)) dup.add(f);
    }
    return dup.toList();
  }

  Json toConfig() => {'name': name, 'include': include, 'header_row': headerRow, 'mapping': mapping};
}

class WizardController extends ChangeNotifier {
  WizardController(this.api);

  ApiClient api;
  bool _disposed = false;
  Inspection? inspection;
  Version? version;
  WizardStep step = WizardStep.caseInfo;
  final Set<WizardStep> visited = {WizardStep.caseInfo};

  /// Local bytes of the uploaded photo for instant preview (server copy used otherwise).
  Uint8List? photoBytes;
  final Map<String, double?> uploadProgress = {};
  final Map<String, String?> uploadError = {};

  // expected-list mapping
  String? sheetsAssetId;
  List<SheetCfg> sheets = [];
  bool sheetsDirty = false;
  Json? listPreview;
  String? listPreviewError;

  // configure
  bool configSaved = false;

  Readiness? readiness;
  Object? readinessError;
  bool readinessLoading = false;

  bool get isDemo => inspection?.isDemo ?? false;
  bool get hasCase => inspection != null && version != null;
  Asset? asset(String kind) => version?.asset(kind);
  bool get editable => version?.editable ?? true;

  bool isComplete(WizardStep s) => switch (s) {
    WizardStep.caseInfo => hasCase,
    WizardStep.photo => asset('photo') != null,
    WizardStep.drawing => asset('drawing') != null,
    WizardStep.expectedList => asset('expected_list') != null && !sheetsDirty,
    WizardStep.configure => configSaved,
    WizardStep.validate => readiness?.ready ?? false,
    WizardStep.run => false,
  };

  bool canEnter(WizardStep s) => s == WizardStep.caseInfo || hasCase;

  void goTo(WizardStep s) {
    if (!canEnter(s)) return;
    step = s;
    visited.add(s);
    notifyListeners();
  }

  void next() {
    if (step.index < WizardStep.values.length - 1) goTo(WizardStep.values[step.index + 1]);
  }

  void back() {
    if (step.index > 0) goTo(WizardStep.values[step.index - 1]);
  }

  void touch() => notifyListeners();

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // --- case ------------------------------------------------------------------
  Future<void> saveCase(Json body) async {
    if (inspection == null) {
      final i = await api.createInspection(body);
      inspection = i;
      version = i.versions.isNotEmpty ? i.versions.first : i.latest;
    } else {
      final update = Map<String, dynamic>.from(body)..remove('cabinet_id');
      final i = await api.updateInspection(inspection!.id, update);
      inspection = i;
      version = i.versions.where((v) => v.id == version?.id).firstOrNull ?? i.versions.firstOrNull;
    }
    notifyListeners();
  }

  /// Loads an existing inspection (e.g. the bundled demo fixture case) into the wizard.
  void load(Inspection i) {
    inspection = i;
    version = i.versions.firstOrNull ?? i.latest;
    photoBytes = null;
    sheets = [];
    sheetsAssetId = null;
    sheetsDirty = false;
    listPreview = null;
    configSaved = false;
    readiness = null;
    uploadError.clear();
    visited.addAll(WizardStep.values.take(5));
    _syncSheets();
    notifyListeners();
  }

  Future<void> reloadVersion() async {
    if (version == null) return;
    version = await api.version(version!.id);
    _syncSheets();
    notifyListeners();
  }

  // --- uploads -----------------------------------------------------------------
  Future<bool> upload(String kind, PickedFile f) async {
    if (version == null) return false;
    uploadError[kind] = null;
    uploadProgress[kind] = 0;
    if (kind == 'photo') photoBytes = f.bytes;
    notifyListeners();
    try {
      await api.uploadAsset(
        version!.id,
        kind,
        f.bytes,
        f.name,
        onProgress: (p) {
          uploadProgress[kind] = p;
          notifyListeners();
        },
      );
      if (kind == 'expected_list') sheetsAssetId = null;
      readiness = null;
      await reloadVersion();
      return true;
    } on ApiException catch (e) {
      uploadError[kind] = e.message;
      if (kind == 'photo' && asset('photo') == null) photoBytes = null;
      return false;
    } finally {
      uploadProgress.remove(kind);
      notifyListeners();
    }
  }

  Future<void> removeAsset(String kind) async {
    final a = asset(kind);
    if (a == null || version == null) return;
    await api.deleteAsset(version!.id, a.id);
    if (kind == 'photo') photoBytes = null;
    if (kind == 'expected_list') {
      sheets = [];
      sheetsAssetId = null;
      listPreview = null;
    }
    readiness = null;
    await reloadVersion();
  }

  // --- drawing -------------------------------------------------------------------
  int get drawingPage => (version?.config['drawing_page'] as num?)?.toInt() ?? 0;

  Future<void> setDrawingPage(int page) async {
    version = await api.updateConfig(version!.id, {'drawing_page': page});
    readiness = null;
    notifyListeners();
  }

  // --- expected list -------------------------------------------------------------------
  void _syncSheets() {
    final a = asset('expected_list');
    if (a == null) {
      sheets = [];
      sheetsAssetId = null;
      return;
    }
    if (sheetsAssetId == a.id) return;
    sheetsAssetId = a.id;
    final savedList = (version?.config['sheets'] as List?)?.map((e) => (e as Map).cast<String, dynamic>()).toList();
    sheets = a.analysis.objs('sheets').map((s) {
      final saved = savedList?.where((x) => x['name'] == s['name']).firstOrNull;
      return SheetCfg.fromAnalysis(s, saved);
    }).toList();
    sheetsDirty = false;
    listPreview = null;
    listPreviewError = null;
  }

  Map<String, String> get fieldLabels => (asset('expected_list')?.analysis.obj('fields') ?? const {}).map((k, v) => MapEntry(k, v.toString()));

  void markSheetsDirty() {
    sheetsDirty = true;
    listPreview = null;
    readiness = null;
    notifyListeners();
  }

  /// Header row changed: ask the server to re-detect columns and mapping for that row.
  Future<void> changeHeaderRow(SheetCfg s, int row) async {
    final a = asset('expected_list');
    if (a == null) return;
    s.headerRow = row;
    s.remapping = true;
    s.remapError = null;
    markSheetsDirty();
    try {
      final res = await api.spreadsheetPreview(a.id, [
        {'name': s.name, 'include': true, 'header_row': row},
      ]);
      final used = res.objs('sheets').where((x) => x['name'] == s.name).firstOrNull;
      if (used == null) {
        s.columns = [];
        s.mapping = {};
        s.remapError = 'No recognisable header columns on row ${row + 1}; choose another header row.';
      } else {
        final m = used.obj('mapping').map((k, v) => MapEntry(k, v as String?));
        s.columns = m.keys.toList();
        s.mapping = m;
        s.role = used.str('role');
      }
      s.scores = {};
      if (row != s.detectedHeaderRow) s.preview = const [];
    } on ApiException catch (e) {
      s.remapError = e.message;
    } finally {
      s.remapping = false;
      notifyListeners();
    }
  }

  List<Json> get sheetConfigs => sheets.map((s) => s.toConfig()).toList();

  Future<void> validateMapping() async {
    final a = asset('expected_list');
    if (a == null) return;
    listPreviewError = null;
    notifyListeners();
    try {
      listPreview = await api.spreadsheetPreview(a.id, sheetConfigs);
    } on ApiException catch (e) {
      listPreviewError = e.message;
      listPreview = null;
    }
    notifyListeners();
  }

  Future<void> saveMapping() async {
    version = await api.updateConfig(version!.id, {'sheets': sheetConfigs});
    sheetsDirty = false;
    readiness = null;
    notifyListeners();
  }

  // --- configure -----------------------------------------------------------------------
  Future<void> saveConfig(Json body) async {
    version = await api.updateConfig(version!.id, body);
    configSaved = true;
    readiness = null;
    notifyListeners();
  }

  // --- readiness -----------------------------------------------------------------------
  Future<void> loadReadiness() async {
    if (version == null) return;
    readinessLoading = true;
    readinessError = null;
    notifyListeners();
    try {
      readiness = await api.readiness(version!.id);
    } catch (e) {
      readinessError = e;
    } finally {
      readinessLoading = false;
      notifyListeners();
    }
  }
}
