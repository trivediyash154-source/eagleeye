import 'package:eagle_eye/core/api/api_client.dart';
import 'package:eagle_eye/core/api/models.dart';
import 'package:eagle_eye/core/theme/app_theme.dart';
import 'package:eagle_eye/features/inspections/new/step_case.dart';
import 'package:eagle_eye/features/inspections/new/step_config.dart';
import 'package:eagle_eye/features/inspections/new/step_drawing.dart';
import 'package:eagle_eye/features/inspections/new/step_list.dart';
import 'package:eagle_eye/features/inspections/new/step_photo.dart';
import 'package:eagle_eye/features/inspections/new/step_validate_run.dart';
import 'package:eagle_eye/features/inspections/new/wizard_controller.dart';
import 'package:eagle_eye/features/inspections/new/wizard_rails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Json versionJson() => {
      'id': 'ver_1', 'inspection_id': 'insp_1', 'version_no': 1, 'label': 'Initial inspection', 'status': 'draft',
      'config': {'checks': ['component_presence', 'device_label'], 'drawing_page': 0, 'sheets': null, 'preprocess': {'clahe': true}, 'policies': {}, 'detector': {'conf': null}},
      'summary': {}, 'effective_summary': {}, 'registration': {}, 'preprocessing': {}, 'assets': [
        {'id': 'a1', 'kind': 'photo', 'original_filename': 'CAB-07_cabinet_photo_v1_SYNTHETIC.jpg', 'content_type': 'image/jpeg', 'size_bytes': 1630528, 'sha256': '854bc2e7a03bda29c37d7d17357c6e7acb4ce95dccc57e6c1df7474545708c69',
          'analysis': {'format': 'JPEG', 'width': 4000, 'height': 3000, 'exif_orientation': 1, 'quality': {'megapixels': 12.0, 'sharpness_laplacian_var': 41.3, 'brightness_mean': 158.8, 'contrast_std': 56.0, 'clipped_highlights_ratio': 0.0005, 'rating': 'acceptable',
            'warnings': [{'code': 'blurry', 'message': 'Laplacian variance 41 suggests some blur.'}]}}, 'inherited': false, 'download_url': '/api/v1/assets/a1/file'},
        {'id': 'a2', 'kind': 'drawing', 'original_filename': 'CAB-07_GA_drawing_SYNTHETIC.pdf', 'content_type': 'application/pdf', 'size_bytes': 25384, 'sha256': 'f1fd5c10c5ee346d07d85dc7b23f2fba00',
          'analysis': {'page_count': 2, 'pages': [{'index': 0, 'width_pt': 1190.55, 'height_pt': 841.89, 'words': 118, 'vector_paths': 75, 'images': 0, 'kind': 'vector', 'text_extractable': true},
            {'index': 1, 'width_pt': 1190.55, 'height_pt': 841.89, 'words': 0, 'vector_paths': 0, 'images': 1, 'kind': 'raster', 'text_extractable': false}],
            'metadata': {'title': 'GA CAB-07 (synthetic)'}, 'warnings': [{'page': 1, 'code': 'raster_page', 'message': 'Page 2 has no text layer; OCR will be used.'}]}, 'inherited': false, 'download_url': '/x'},
        {'id': 'a3', 'kind': 'expected_list', 'original_filename': 'CAB-07_expected_list_SYNTHETIC.xlsx', 'content_type': 'x', 'size_bytes': 6619, 'sha256': 'edd99c19527df75da0eb39d66a82a548aa',
          'analysis': {'fields': {'zone': 'Zone', 'component_id': 'Component ID / reference designation', 'ferrule': 'Expected ferrule', 'terminal': 'Terminal reference'}, 'sheets': [
            {'name': 'Components', 'header_row': 2, 'columns': ['Zone', 'Ref. Designation', 'Component Type', 'Device Label', 'Qty', 'Remarks'], 'mapping': {'Zone': 'zone', 'Ref. Designation': 'component_id', 'Component Type': null, 'Device Label': null, 'Qty': null, 'Remarks': null},
              'mapping_scores': {'Zone': 100, 'Ref. Designation': 100}, 'preview': [{'row': 4, 'values': {'Zone': 'Z1', 'Ref. Designation': 'QF01', 'Component Type': 'Miniature circuit breaker (MCB)', 'Device Label': 'QF01', 'Qty': '1', 'Remarks': 'MAIN MCB 3P'}}], 'row_count': 13, 'role': 'components'},
            {'name': 'Wire List', 'header_row': 0, 'columns': ['Terminal', 'Ferrule No.'], 'mapping': {'Terminal': 'terminal', 'Ferrule No.': 'ferrule'}, 'mapping_scores': {}, 'preview': [], 'row_count': 10, 'role': 'wires'}]}, 'inherited': false, 'download_url': '/x'},
      ],
      'reviewed_count': 0, 'finding_count': 0,
    };

Inspection inspection() => Inspection({'id': 'insp_1', 'code': 'EYE-0007', 'title': 'CAB-07 sample inspection (synthetic fixture)', 'cabinet_id': 'CAB-07', 'site': 'Bench', 'is_demo': true, 'version_count': 1, 'versions': [versionJson()]});

WizardController ctl() {
  final c = WizardController(ApiClient('http://127.0.0.1:9'));
  c.load(inspection());
  c.readiness = Readiness({'ready': false, 'items': [
    {'key': 'photo', 'label': 'Cabinet photograph', 'status': 'ok', 'message': 'CAB-07_cabinet_photo_v1_SYNTHETIC.jpg: 4000×3000px, quality good'},
    {'key': 'detector', 'label': 'YOLOv8 detector', 'status': 'warning', 'message': 'yolov8n.pt: generic COCO classes only — component presence/type will be UNCERTAIN.'},
    {'key': 'expected_list', 'label': 'Expected component / wire list', 'status': 'error', 'message': 'No records parsed — check sheet selection and column mapping.'},
  ]});
  c.listPreview = {'counts': {'components': 13, 'identifiers': 10}, 'warnings': [{'sheet': 'Components', 'row': 3, 'code': 'duplicate_component', 'message': 'Component ID QF01 also appears in Components row 4.'}],
    'components': [{'tag': 'QF01', 'component_type': 'MCB', 'expected_label': 'QF01', 'zone_code': 'Z1', 'quantity': 1, 'source_row': 4}], 'identifiers': [{'terminal_ref': 'X12:1', 'value': 'X12-1A', 'wire_color': 'Brown', 'component_tag': 'QF01', 'zone_code': 'Z4', 'source_row': 2}], 'sheets': []};
  return c;
}

void main() {
  for (final size in const [Size(1440, 1000), Size(390, 900)]) {
    testWidgets('wizard steps render without layout errors at ${size.width}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ctl();
      final steps = <Widget Function()>[
        () => CaseStep(controller: c),
        () => PhotoStep(controller: c),
        () => DrawingStep(controller: c),
        () => ListStep(controller: c),
        () => ConfigStep(controller: c),
        () => ValidateStep(controller: c),
        () => RunStep(controller: c),
        () => Column(children: [StepRail(controller: c), SummaryRail(controller: c)]),
      ];
      for (final s in steps) {
        await tester.pumpWidget(ProviderScope(child: MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: s())))));
        await tester.pump(const Duration(milliseconds: 50));
        final ex = tester.takeException();
        expect(ex, isNull, reason: 'step ${steps.indexOf(s)} threw $ex');
      }
      // no-case state
      final fresh = WizardController(ApiClient('http://127.0.0.1:9'));
      await tester.pumpWidget(ProviderScope(child: MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: Column(children: [StepRail(controller: fresh), CaseStep(controller: fresh), SummaryRail(controller: fresh)]))))));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  }
}
