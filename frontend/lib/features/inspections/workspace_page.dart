import 'package:flutter/material.dart';

class WorkspacePage extends StatelessWidget {
  const WorkspacePage({super.key, this.inspectionId, this.versionNo, this.findingId});
  final String? inspectionId;
  final int? versionNo;
  final String? findingId;

  @override
  Widget build(BuildContext context) => const Center(child: Text('WorkspacePage'));
}
