import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.code = 'error', this.status, this.details});
  final String message;
  final String code;
  final int? status;
  final Object? details;

  bool get isNetwork => code == 'network';

  @override
  String toString() => message;
}

/// Single place for all HTTP calls. Screens never build URLs or parse errors themselves.
class ApiClient {
  ApiClient(this.base)
      : _dio = Dio(BaseOptions(
          baseUrl: '$base/api/v1',
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(minutes: 5),
          headers: {'Accept': 'application/json'},
        ));

  final String base;
  final Dio _dio;

  /// Absolute URL for a backend path such as `/api/v1/evidence/x/file`.
  String url(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$base$path';
  }

  Future<T> _wrap<T>(Future<Response<dynamic>> Function() call, T Function(dynamic data) parse) async {
    try {
      final r = await call();
      return parse(r.data);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] is Map) {
        final err = (data['error'] as Map).cast<String, dynamic>();
        throw ApiException(err['message']?.toString() ?? 'Request failed', code: err['code']?.toString() ?? 'error', status: e.response?.statusCode, details: err['details']);
      }
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout || e.response == null) {
        throw ApiException('Cannot reach the EAGLE EYE API at $base. Is the backend running?', code: 'network');
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        throw ApiException('The API did not respond in time.', code: 'timeout');
      }
      throw ApiException('HTTP ${e.response?.statusCode}: ${e.message}', status: e.response?.statusCode);
    }
  }

  Json _j(dynamic d) => (d as Map).cast<String, dynamic>();

  // --- system ---------------------------------------------------------------
  Future<Json> health() => _wrap(() => _dio.get('/health'), _j);
  Future<SystemStatus> systemStatus() => _wrap(() => _dio.get('/system/status'), (d) => SystemStatus.fromJson(_j(d)));
  Future<Json> diagnostics() => _wrap(() => _dio.get('/system/diagnostics'), _j);
  Future<Json> loadModels() => _wrap(() => _dio.post('/system/models/load'), _j);
  Future<List<Json>> logs({String? level, String? component, int limit = 200}) =>
      _wrap(() => _dio.get('/system/logs', queryParameters: {'level': ?level, 'component': ?component, 'limit': limit}), (d) => _j(d).objs('items'));
  Future<List<Json>> checks() => _wrap(() => _dio.get('/system/checks'), (d) => _j(d).objs('items'));
  Future<Json> detectorTest({Uint8List? bytes, String? filename}) => _wrap(
      () => _dio.post('/system/diagnostics/detector-test', data: bytes == null ? null : FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename ?? 'test.jpg')})),
      _j);
  Future<Json> ocrTest({Uint8List? bytes, String? filename}) => _wrap(
      () => _dio.post('/system/diagnostics/ocr-test', data: bytes == null ? null : FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename ?? 'test.jpg')})),
      _j);

  // --- inspections ------------------------------------------------------------
  Future<Page<Inspection>> inspections({String? q, String dataset = 'all', String? status, String? verdict, String sort = 'created_at', String order = 'desc', int page = 1, int pageSize = 20, String? dateFrom, String? dateTo}) =>
      _wrap(
          () => _dio.get('/inspections', queryParameters: {
                if (q != null && q.isNotEmpty) 'q': q,
                'dataset': dataset,
                'status': ?status,
                'verdict': ?verdict,
                'sort': sort,
                'order': order,
                'page': page,
                'page_size': pageSize,
                'date_from': ?dateFrom,
                'date_to': ?dateTo,
              }), (d) {
        final j = _j(d);
        return Page(j.objs('items').map(Inspection.new).toList(), j.integer('total'), j.integer('page'), j.integer('page_size'));
      });
  Future<Inspection> inspection(String id) => _wrap(() => _dio.get('/inspections/$id'), (d) => Inspection(_j(d)));
  Future<Inspection> createInspection(Json body) => _wrap(() => _dio.post('/inspections', data: body), (d) => Inspection(_j(d)));
  Future<Inspection> updateInspection(String id, Json body) => _wrap(() => _dio.patch('/inspections/$id', data: body), (d) => Inspection(_j(d)));
  Future<List<Json>> timeline(String id) => _wrap(() => _dio.get('/inspections/$id/timeline'), (d) => _j(d).objs('items'));
  Future<Version> reinspect(String id, {String? label, Uint8List? photo, String? photoName, bool reusePhoto = false, void Function(double)? onProgress}) => _wrap(
      () => _dio.post('/inspections/$id/reinspect',
          data: FormData.fromMap({
            'label': ?label,
            'reuse_photo': reusePhoto.toString(),
            if (photo != null) 'photo': MultipartFile.fromBytes(photo, filename: photoName ?? 'photo.jpg'),
          }),
          onSendProgress: (a, b) => onProgress?.call(b > 0 ? a / b : 0)),
      (d) => Version(_j(d)));
  Future<Json> compare(String id, {int? from, int? to}) =>
      _wrap(() => _dio.get('/inspections/$id/compare', queryParameters: {'from_version': ?from, 'to_version': ?to}), _j);

  // --- versions -----------------------------------------------------------------
  Future<Version> version(String id) => _wrap(() => _dio.get('/versions/$id'), (d) => Version(_j(d)));
  Future<Version> updateConfig(String id, Json body) => _wrap(() => _dio.patch('/versions/$id/config', data: body), (d) => Version(_j(d)));
  Future<Asset> uploadAsset(String versionId, String kind, Uint8List bytes, String filename, {void Function(double)? onProgress}) => _wrap(
      () => _dio.post('/versions/$versionId/assets',
          data: FormData.fromMap({'kind': kind, 'file': MultipartFile.fromBytes(bytes, filename: filename)}), onSendProgress: (a, b) => onProgress?.call(b > 0 ? a / b : 0)),
      (d) => Asset(_j(d)));
  Future<void> deleteAsset(String versionId, String assetId) => _wrap(() => _dio.delete('/versions/$versionId/assets/$assetId'), (_) {});
  Future<Readiness> readiness(String versionId) => _wrap(() => _dio.get('/versions/$versionId/readiness'), (d) => Readiness(_j(d)));
  Future<Job> run(String versionId) => _wrap(() => _dio.post('/versions/$versionId/run'), (d) => Job(_j(d)));
  Future<Json> media(String versionId) => _wrap(() => _dio.get('/versions/$versionId/media'), _j);
  Future<List<Json>> detections(String versionId, {bool includeLow = false}) =>
      _wrap(() => _dio.get('/versions/$versionId/detections', queryParameters: {'include_low': includeLow}), (d) => _j(d).objs('items'));
  Future<List<Json>> ocr(String versionId) => _wrap(() => _dio.get('/versions/$versionId/ocr'), (d) => _j(d).objs('items'));
  Future<Json> expected(String versionId) => _wrap(() => _dio.get('/versions/$versionId/expected'), _j);
  Future<Json> drawing(String versionId) => _wrap(() => _dio.get('/versions/$versionId/drawing'), _j);
  Future<Json> saveZones(String versionId, List<Json> zones) => _wrap(() => _dio.put('/versions/$versionId/zones', data: {'zones': zones}), _j);
  Future<Json> manualAlignment(String versionId, List<Json> anchors, {bool rerun = true}) =>
      _wrap(() => _dio.post('/versions/$versionId/alignment', data: {'anchors': anchors, 'rerun': rerun}), _j);
  Future<Json> spreadsheetPreview(String assetId, List<Json>? sheets) => _wrap(() => _dio.post('/assets/$assetId/spreadsheet/preview', data: {'sheets': sheets}), _j);
  String pdfPreviewUrl(String assetId, int page, {double zoom = 1.0}) => url('/api/v1/assets/$assetId/pdf/pages/$page/preview?zoom=$zoom');

  // --- jobs ------------------------------------------------------------------------
  Future<Job> job(String id) => _wrap(() => _dio.get('/jobs/$id'), (d) => Job(_j(d)));
  Future<List<Job>> jobs({bool active = false, int limit = 20}) => _wrap(() => _dio.get('/jobs', queryParameters: {'active': active, 'limit': limit}), (d) => _j(d).objs('items').map(Job.new).toList());
  Future<Job> cancelJob(String id) => _wrap(() => _dio.post('/jobs/$id/cancel'), (d) => Job(_j(d)));

  // --- findings / reviews / evidence -------------------------------------------------
  Future<(List<Finding>, Map<String, int>)> findings(String versionId, {String? verdict, String? checkType, String? q}) =>
      _wrap(() => _dio.get('/versions/$versionId/findings', queryParameters: {'verdict': ?verdict, 'check_type': ?checkType, if (q != null && q.isNotEmpty) 'q': q}), (d) {
        final j = _j(d);
        return (j.objs('items').map(Finding.new).toList(), j.obj('counts').map((k, v) => MapEntry(k, (v as num).toInt())));
      });
  Future<Finding> finding(String id) => _wrap(() => _dio.get('/findings/$id'), (d) => Finding(_j(d)));
  Future<Review> review(String findingId, Json body) => _wrap(() => _dio.post('/findings/$findingId/reviews', data: body), (d) => Review(_j(d)));
  Future<Page<Evidence>> evidence({String? inspectionId, String? versionId, String? kind, String? findingId, int page = 1, int pageSize = 60}) => _wrap(
      () => _dio.get('/evidence', queryParameters: {'inspection_id': ?inspectionId, 'version_id': ?versionId, 'kind': ?kind, 'finding_id': ?findingId, 'page': page, 'page_size': pageSize}), (d) {
        final j = _j(d);
        return Page(j.objs('items').map(Evidence.new).toList(), j.integer('total'), j.integer('page'), j.integer('page_size'));
      });

  // --- reports, analytics, queue, demo ------------------------------------------------
  Future<Json> createReport(String versionId, String format) => _wrap(() => _dio.post('/versions/$versionId/reports', data: {'format': format}), _j);
  Future<List<Json>> reports({String? inspectionId, String? versionId}) =>
      _wrap(() => _dio.get('/reports', queryParameters: {'inspection_id': ?inspectionId, 'version_id': ?versionId}), (d) => _j(d).objs('items'));
  Future<Json> analytics({String dataset = 'all', String? dateFrom, String? dateTo}) =>
      _wrap(() => _dio.get('/analytics/overview', queryParameters: {'dataset': dataset, 'date_from': ?dateFrom, 'date_to': ?dateTo}), _j);
  Future<List<Json>> activity({int limit = 20, String dataset = 'all'}) =>
      _wrap(() => _dio.get('/analytics/activity', queryParameters: {'limit': limit, 'dataset': dataset}), (d) => _j(d).objs('items'));
  Future<Json> reviewQueue({String? inspectionId, String? reason, String? checkType, String sort = 'tier', String dataset = 'all'}) => _wrap(
      () => _dio.get('/review-queue', queryParameters: {'inspection_id': ?inspectionId, 'reason': ?reason, 'check_type': ?checkType, 'sort': sort, 'dataset': dataset}), _j);
  Future<Json> fixtures() => _wrap(() => _dio.get('/demo/fixtures'), _j);
  Future<Json> sampleInspection({String variant = 'v1', bool run = true}) => _wrap(() => _dio.post('/demo/sample-inspection', data: {'variant': variant, 'run': run}), _j);
  Future<Json> sampleReinspect(String inspectionId) => _wrap(() => _dio.post('/demo/sample-inspection/$inspectionId/reinspect'), _j);
}

final apiProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(appConfigProvider).apiBase));
