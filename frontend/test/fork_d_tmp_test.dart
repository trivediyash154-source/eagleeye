// TEMPORARY layout smoke test (fork D) — deleted after validation.
import 'dart:convert';
import 'dart:io';

import 'package:eagle_eye/core/api/api_client.dart';
import 'package:eagle_eye/core/api/models.dart';
import 'package:eagle_eye/core/theme/app_theme.dart';
import 'package:eagle_eye/features/evidence/evidence_page.dart';
import 'package:eagle_eye/features/history/history_page.dart';
import 'package:eagle_eye/features/reports/reports_page.dart';
import 'package:eagle_eye/features/review/review_queue_page.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const dir = '/tmp/claude-0/-home-user-eagleeye/902a5252-d93b-526b-87b2-21377901893f/scratchpad/fork_d_json';
Json load(String n) => (jsonDecode(File('$dir/$n').readAsStringSync()) as Map).cast<String, dynamic>();

Json twoVersions() {
  final j = load('inspection.json');
  final v1 = (j['versions'] as List).first as Map<String, dynamic>;
  final v2 = Map<String, dynamic>.from(v1)
    ..['id'] = 'ver_two'
    ..['version_no'] = 2
    ..['label'] = 'Reinspection'
    ..['parent_version_id'] = v1['id'];
  j['versions'] = [v1, v2];
  j['version_count'] = 2;
  j['latest_version'] = v2;
  return j;
}

class FakeApi extends ApiClient {
  FakeApi() : super('http://fake');
  @override
  Future<Page<Inspection>> inspections({String? q, String dataset = 'all', String? status, String? verdict, String sort = 'created_at', String order = 'desc', int page = 1, int pageSize = 20, String? dateFrom, String? dateTo}) async {
    final j = load('inspections.json');
    return Page(j.objs('items').map(Inspection.new).toList(), j.integer('total'), 1, pageSize);
  }

  @override
  Future<Inspection> inspection(String id) async => Inspection(twoVersions());
  @override
  Future<List<Json>> timeline(String id) async => load('timeline.json').objs('items');
  @override
  Future<Json> compare(String id, {int? from, int? to}) async => {
        'from_version': 1,
        'to_version': 2,
        'summary': {'counts': {'resolved': 2, 'persistent': 1, 'still_uncertain': 1, 'unchanged_pass': 3}},
        'categories': {'resolved': 'fixed', 'persistent': 'still there', 'still_uncertain': 'u', 'unchanged_pass': 'p'},
        'items': [
          {'finding_key': 'a', 'check_type': 'ferrule_label', 'subject': 'X12:4', 'zone_code': 'Z4', 'category': 'resolved', 'expected': 'X12-4B',
           'from': {'finding_id': 'f1', 'seq': 43, 'machine_verdict': 'FAIL', 'effective_verdict': 'FAIL', 'observed': 'X12-8B'},
           'to': {'finding_id': 'f2', 'seq': 43, 'verdict': 'PASS', 'observed': 'X12-4B'}},
          {'finding_key': 'b', 'check_type': 'device_label', 'subject': 'K2', 'zone_code': 'Z3', 'category': 'still_uncertain', 'expected': 'K2',
           'from': {'finding_id': 'f3', 'seq': 31, 'machine_verdict': 'UNCERTAIN', 'effective_verdict': 'UNCERTAIN', 'observed': null}, 'to': null},
        ],
      };
  @override
  Future<Json> reviewQueue({String? inspectionId, String? reason, String? checkType, String sort = 'tier', String dataset = 'all'}) async => load('queue.json');
  @override
  Future<Page<Evidence>> evidence({String? inspectionId, String? versionId, String? kind, String? findingId, int page = 1, int pageSize = 60}) async {
    final j = load('evidence.json');
    final items = j.objs('items').map(Evidence.new).toList();
    items.add(Evidence({...items.first.j, 'id': 'evd_missing', 'url': null, 'thumbnail_url': null, 'error': 'No crop: zone could not be projected onto the photo.'}));
    return Page(items, j.integer('total') + 1, 1, pageSize);
  }

  @override
  Future<List<Json>> reports({String? inspectionId, String? versionId}) async => load('reports.json').objs('items');
}

Future<void> pumpPage(WidgetTester t, Widget page, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(ProviderScope(
    overrides: [apiProvider.overrideWithValue(FakeApi())],
    child: MaterialApp(theme: buildTheme(), home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: page))),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final size in const [Size(1440, 1000), Size(900, 1000), Size(390, 844)]) {
    testWidgets('review queue ${size.width}', (t) async {
      await pumpPage(t, const ReviewQueuePage(), size);
      expect(find.text('Review Queue'), findsOneWidget);
      expect(find.textContaining('CB44'), findsWidgets);
    });
    testWidgets('history ${size.width}', (t) async {
      await pumpPage(t, const HistoryPage(inspectionId: 'insp_x'), size);
      expect(find.text('Version timeline'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Event timeline'), 300, scrollable: find.byType(Scrollable).last);
      expect(find.text('Version comparison'), findsOneWidget);
    });
    testWidgets('history list ${size.width}', (t) async {
      await pumpPage(t, const HistoryPage(), size);
      expect(find.textContaining('EYE-0001'), findsWidgets);
    });
    testWidgets('reports ${size.width}', (t) async {
      await pumpPage(t, const ReportsPage(inspectionId: 'insp_cbeef192fb42420b8a0b'), size);
      expect(find.textContaining('EAGLE-EYE_EYE-0001'), findsWidgets);
    });
    testWidgets('evidence ${size.width}', (t) async {
      await pumpPage(t, const EvidencePage(), size);
      expect(find.text('Evidence Explorer'), findsOneWidget);
    });
  }
}
