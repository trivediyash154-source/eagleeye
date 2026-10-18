// Typed API models mirroring backend/app/schemas/api.py (API v1).

typedef Json = Map<String, dynamic>;

extension JsonX on Json {
  String str(String k, [String d = '']) => (this[k] as String?) ?? d;
  String? strN(String k) => this[k] as String?;
  int integer(String k, [int d = 0]) => (this[k] as num?)?.toInt() ?? d;
  int? intN(String k) => (this[k] as num?)?.toInt();
  double? dbl(String k) => (this[k] as num?)?.toDouble();
  bool boolean(String k, [bool d = false]) => (this[k] as bool?) ?? d;
  Json obj(String k) => (this[k] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  Json? objN(String k) => (this[k] as Map?)?.cast<String, dynamic>();
  List<Json> objs(String k) => ((this[k] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  List<String> strs(String k) => ((this[k] as List?) ?? const []).map((e) => e.toString()).toList();
  List<double>? box(String k) => (this[k] as List?)?.map((e) => (e as num).toDouble()).toList();
  DateTime? time(String k) => this[k] == null ? null : DateTime.tryParse(this[k] as String)?.toLocal();
}

class SystemComponent {
  SystemComponent(this.key, this.label, this.state, this.message);
  factory SystemComponent.fromJson(Json j) => SystemComponent(j.str('key'), j.str('label'), j.str('state'), j.str('message'));
  final String key, label, state, message;
}

class SystemStatus {
  SystemStatus({required this.status, required this.components, required this.warmup});
  factory SystemStatus.fromJson(Json j) =>
      SystemStatus(status: j.str('status'), components: j.objs('components').map(SystemComponent.fromJson).toList(), warmup: j.str('model_warmup'));
  final String status;
  final List<SystemComponent> components;
  final String warmup;
  SystemComponent? byKey(String k) => components.where((c) => c.key == k).firstOrNull;
}

class Asset {
  Asset(this.j);
  final Json j;
  String get id => j.str('id');
  String get kind => j.str('kind');
  String get filename => j.str('original_filename');
  String get contentType => j.str('content_type');
  int get sizeBytes => j.integer('size_bytes');
  String get sha256 => j.str('sha256');
  Json get analysis => j.obj('analysis');
  bool get inherited => j.boolean('inherited');
  String get downloadUrl => j.str('download_url');
}

class Summary {
  Summary(this.j);
  final Json j;
  int get total => j.integer('total');
  int get pass => j.integer('pass');
  int get fail => j.integer('fail');
  int get uncertain => j.integer('uncertain');
  String? get registration => j.strN('registration');
  String? get detectorKind => j.strN('detector_kind');
  Json get byCheck => j.obj('by_check');
}

class Version {
  Version(this.j);
  final Json j;
  String get id => j.str('id');
  String get inspectionId => j.str('inspection_id');
  int get no => j.integer('version_no');
  String get label => j.str('label');
  String? get parentVersionId => j.strN('parent_version_id');
  String get status => j.str('status');
  Json get config => j.obj('config');
  Summary get summary => Summary(j.obj('summary'));
  Map<String, int> get effective => j.obj('effective_summary').map((k, v) => MapEntry(k, (v as num).toInt()));
  Json get registration => j.obj('registration');
  Json get preprocessing => j.obj('preprocessing');
  String? get error => j.strN('error');
  DateTime? get createdAt => j.time('created_at');
  DateTime? get completedAt => j.time('completed_at');
  int? get durationMs => j.intN('duration_ms');
  List<Asset> get assets => j.objs('assets').map(Asset.new).toList();
  Asset? asset(String kind) => assets.where((a) => a.kind == kind).firstOrNull;
  String? get latestJobId => j.strN('latest_job_id');
  int get reviewedCount => j.integer('reviewed_count');
  int get findingCount => j.integer('finding_count');
  bool get editable => const {'draft', 'failed', 'cancelled'}.contains(status);
  bool get isActive => status == 'queued' || status == 'running';
}

class Inspection {
  Inspection(this.j);
  final Json j;
  String get id => j.str('id');
  String get code => j.str('code');
  String get title => j.str('title');
  String get cabinetId => j.str('cabinet_id');
  String? get site => j.strN('site');
  String? get reference => j.strN('reference');
  String? get inspector => j.strN('inspector');
  String? get projectRef => j.strN('project_ref');
  String? get notes => j.strN('notes');
  bool get isDemo => j.boolean('is_demo');
  DateTime? get createdAt => j.time('created_at');
  int get versionCount => j.integer('version_count');
  Version? get latest => j.objN('latest_version') == null ? null : Version(j.obj('latest_version'));
  List<Version> get versions => j.objs('versions').map(Version.new).toList();
  Version? versionNo(int? n) => n == null ? (versions.isEmpty ? latest : versions.last) : versions.where((v) => v.no == n).firstOrNull;
}

class Page<T> {
  Page(this.items, this.total, this.page, this.pageSize);
  final List<T> items;
  final int total, page, pageSize;
}

class Stage {
  Stage(this.j);
  final Json j;
  String get name => j.str('name');
  String get title => j.str('title');
  String get status => j.str('status');
  String? get message => j.strN('message');
  Json get details => j.obj('details');
  int? get durationMs => j.intN('duration_ms');
  DateTime? get startedAt => j.time('started_at');
}

class Job {
  Job(this.j);
  final Json j;
  String get id => j.str('id');
  String get inspectionId => j.str('inspection_id');
  String get versionId => j.str('version_id');
  String get status => j.str('status');
  bool get cancelRequested => j.boolean('cancel_requested');
  String? get currentStage => j.strN('current_stage');
  String? get error => j.strN('error');
  DateTime? get createdAt => j.time('created_at');
  DateTime? get startedAt => j.time('started_at');
  DateTime? get finishedAt => j.time('finished_at');
  List<Stage> get stages => j.objs('stages').map(Stage.new).toList();
  bool get isTerminal => const {'completed', 'failed', 'cancelled'}.contains(status);
  String? get inspectionCode => j.strN('inspection_code');
  String? get cabinetId => j.strN('cabinet_id');
  int? get versionNo => j.intN('version_no');
}

class Review {
  Review(this.j);
  final Json j;
  String get action => j.str('action');
  String? get resultingVerdict => j.strN('resulting_verdict');
  String? get correctedValue => j.strN('corrected_value');
  String? get reason => j.strN('reason');
  String? get notes => j.strN('notes');
  String get reviewer => j.str('reviewer');
  String get reviewerKind => j.str('reviewer_kind');
  DateTime? get createdAt => j.time('created_at');
  Json get details => j.obj('details');
}

class Evidence {
  Evidence(this.j);
  final Json j;
  String get id => j.str('id');
  String get kind => j.str('kind');
  String get title => j.str('title');
  String? get url => j.strN('url');
  String? get thumbUrl => j.strN('thumbnail_url');
  int? get width => j.intN('width');
  int? get height => j.intN('height');
  String? get error => j.strN('error');
  String get operation => j.str('operation');
  String? get algorithm => j.strN('algorithm');
  String? get sha256 => j.strN('sha256');
  List<double>? get bbox => j.box('bbox');
  String? get findingId => j.strN('finding_id');
  String get versionId => j.str('version_id');
  String get inspectionId => j.str('inspection_id');
  DateTime? get createdAt => j.time('created_at');
  String? get inspectionCode => j.strN('inspection_code');
  int? get versionNo => j.intN('version_no');
  bool get isDemo => j.boolean('is_demo');
  Json? get finding => j.objN('finding');
}

class Finding {
  Finding(this.j);
  final Json j;
  String get id => j.str('id');
  String get versionId => j.str('version_id');
  String get inspectionId => j.str('inspection_id');
  int? get versionNo => j.intN('version_no');
  int get seq => j.integer('seq');
  String get key => j.str('finding_key');
  String get checkType => j.str('check_type');
  String? get zone => j.strN('zone_code');
  String get subject => j.str('subject');
  String? get expected => j.strN('expected_value');
  String? get observed => j.strN('observed_value');
  String? get observedRaw => j.strN('observed_raw');
  String get verdict => j.str('verdict');
  String get effectiveVerdict => j.str('effective_verdict');
  String get reviewStatus => j.str('review_status');
  String get rule => j.str('rule');
  String get explanation => j.str('explanation');
  Json get confidences => j.obj('confidences');
  List<String> get reasons => j.strs('review_reasons');
  List<double>? get bbox => j.box('bbox');
  List<double>? get expectedBbox => j.box('expected_bbox');
  List<double>? get drawingBbox => j.box('drawing_bbox');
  int get reviewCount => j.integer('review_count');
  // detail-only
  Json get details => j.obj('details');
  List<Review> get reviews => j.objs('reviews').map(Review.new).toList();
  List<Evidence> get evidence => j.objs('evidence').map(Evidence.new).toList();
  Json? get detection => j.objN('detection');
  Json? get ocr => j.objN('ocr_observation');
  List<Json> get history => j.objs('history');
  String get checkLabel => checkLabels[checkType] ?? checkType.replaceAll('_', ' ');
}

const checkLabels = {
  'component_presence': 'Component presence',
  'component_type': 'Component type',
  'device_label': 'Device label',
  'ferrule_label': 'Ferrule label',
  'wire_color': 'Wire colour',
  'zone_correspondence': 'Zone correspondence',
  'drawing_alignment': 'Drawing alignment',
};

const reasonLabels = {
  'registration_unavailable': 'Registration unavailable',
  'unsupported_class': 'Detector lacks class',
  'detector_unavailable': 'Detector unavailable',
  'ocr_unavailable': 'OCR unavailable',
  'weak_detection': 'Low-confidence detection',
  'no_readable_text': 'Unreadable / no text',
  'low_ocr_confidence': 'Low OCR confidence',
  'confusable_characters': 'Confusable characters',
  'ambiguous_association': 'Ambiguous association',
  'possible_partial_read': 'Possible partial read',
  'near_match': 'Near match',
  'region_outside_image': 'Region outside photo',
  'poor_image_quality': 'Poor image quality',
  'zone_not_found': 'Zone not in drawing',
  'not_located_in_drawing': 'Not located in drawing',
  'experimental_check': 'Experimental check',
  'unreviewed_fail': 'Unreviewed FAIL',
  'incomplete_evidence': 'Incomplete evidence',
  'no_confident_detection': 'No confident detection',
  'low_detector_confidence': 'Low detector confidence',
  'uncertain': 'Uncertain',
};

class Readiness {
  Readiness(this.j);
  final Json j;
  bool get ready => j.boolean('ready');
  List<Json> get items => j.objs('items');
}
