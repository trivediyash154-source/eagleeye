import 'package:eagle_eye/core/api/models.dart';
import 'package:eagle_eye/core/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Finding parses API JSON and exposes effective verdict', () {
    final f = Finding({
      'id': 'fnd_1',
      'seq': 43,
      'finding_key': 'ferrule:X12:4',
      'check_type': 'ferrule_label',
      'subject': 'X12:4',
      'expected_value': 'X12-4B',
      'observed_value': 'X12-8B',
      'verdict': 'FAIL',
      'effective_verdict': 'FAIL',
      'confidences': {'ocr': 0.99, 'edit_distance': 1, 'combined': null},
      'review_reasons': <String>[],
      'bbox': [830.2, 2236.4, 922.2, 2261.2],
      'review_count': 0,
    });
    expect(f.checkLabel, 'Ferrule label');
    expect(f.bbox, [830.2, 2236.4, 922.2, 2261.2]);
    expect(f.confidences['combined'], isNull);
    expect(f.reviewCount, 0);
  });

  test('Version editability follows status', () {
    expect(Version({'status': 'draft'}).editable, isTrue);
    expect(Version({'status': 'completed'}).editable, isFalse);
    expect(Version({'status': 'running'}).isActive, isTrue);
  });

  test('SystemStatus lookup by key', () {
    final s = SystemStatus.fromJson({
      'status': 'degraded',
      'model_warmup': 'done',
      'components': [
        {'key': 'detector', 'label': 'YOLOv8', 'state': 'degraded', 'message': 'generic'},
      ],
    });
    expect(s.byKey('detector')!.state, 'degraded');
    expect(s.byKey('ocr'), isNull);
  });

  test('format helpers', () {
    expect(fmtBytes(2048), '2 KB');
    expect(fmtMs(1500), '1.5 s');
    expect(pct(0.256), '26%');
    expect(titleCase('drawing_alignment'), 'Drawing Alignment');
  });
}
