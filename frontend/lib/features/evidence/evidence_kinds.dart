import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

const evidenceKinds = <String, String>{
  'original_photo': 'Original photo',
  'processed_photo': 'Processed photo',
  'annotated_photo': 'Annotated photo',
  'detections_overlay': 'Detections overlay',
  'ocr_overlay': 'OCR overlay',
  'registration_overlay': 'Registered drawing',
  'drawing_page': 'Drawing page',
  'finding_crop': 'Finding crop',
  'finding_crop_annotated': 'Annotated crop',
};

String evidenceKindLabel(String kind) => evidenceKinds[kind] ?? kind.replaceAll('_', ' ');

IconData evidenceKindIcon(String kind) => switch (kind) {
      'original_photo' => Icons.photo_camera_outlined,
      'processed_photo' => Icons.tune_rounded,
      'annotated_photo' => Icons.draw_outlined,
      'detections_overlay' => Icons.center_focus_weak_rounded,
      'ocr_overlay' => Icons.text_fields_rounded,
      'registration_overlay' => Icons.layers_outlined,
      'drawing_page' => Icons.architecture_rounded,
      'finding_crop' => Icons.crop_rounded,
      'finding_crop_annotated' => Icons.crop_free_rounded,
      _ => Icons.image_outlined,
    };

Color evidenceKindColor(String kind) => switch (kind) {
      'original_photo' || 'processed_photo' => EE.ice,
      'annotated_photo' || 'finding_crop_annotated' => EE.cyan,
      'detections_overlay' || 'ocr_overlay' => EE.ultraviolet,
      'registration_overlay' || 'drawing_page' => EE.violet,
      'finding_crop' => EE.textMuted,
      _ => EE.textMuted,
    };

/// The kind most usefully compared against a given kind.
String preferredPartner(String kind) => switch (kind) {
      'finding_crop' => 'finding_crop_annotated',
      'finding_crop_annotated' => 'finding_crop',
      'original_photo' => 'annotated_photo',
      'drawing_page' => 'registration_overlay',
      _ => 'original_photo',
    };
