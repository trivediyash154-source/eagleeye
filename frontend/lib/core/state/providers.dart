import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../util/local_store.dart';

/// Dataset filter shared by dashboard, analytics, history and queues: all | real | demo.
class DatasetNotifier extends Notifier<String> {
  static const _key = 'eagleeye.dataset';
  @override
  String build() => LocalStore.get(_key) ?? 'all';
  void set(String v) {
    LocalStore.set(_key, v);
    state = v;
  }
}

final datasetProvider = NotifierProvider<DatasetNotifier, String>(DatasetNotifier.new);

/// Polls /system/status. The top bar, landing hero and health screens read it.
class SystemStatusNotifier extends Notifier<AsyncValue<SystemStatus>> {
  Timer? _timer;
  late ApiClient _api;

  @override
  AsyncValue<SystemStatus> build() {
    _api = ref.watch(apiProvider);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(refresh);
    return const AsyncLoading();
  }

  Future<void> refresh() async {
    try {
      final s = await _api.systemStatus();
      state = AsyncData(s);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final systemStatusProvider = NotifierProvider<SystemStatusNotifier, AsyncValue<SystemStatus>>(SystemStatusNotifier.new);

/// Active (queued/running) jobs, polled for the top-bar job indicator.
class ActiveJobsNotifier extends Notifier<List<Job>> {
  Timer? _timer;
  late ApiClient _api;

  @override
  List<Job> build() {
    _api = ref.watch(apiProvider);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => refresh());
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(refresh);
    return const [];
  }

  Future<void> refresh() async {
    try {
      state = await _api.jobs(active: true);
    } catch (_) {
      // connectivity problems are surfaced by systemStatusProvider
    }
  }
}

final activeJobsProvider = NotifierProvider<ActiveJobsNotifier, List<Job>>(ActiveJobsNotifier.new);

final inspectionProvider = FutureProvider.family<Inspection, String>((ref, id) => ref.watch(apiProvider).inspection(id));

final findingsProvider = FutureProvider.family<(List<Finding>, Map<String, int>), String>((ref, versionId) => ref.watch(apiProvider).findings(versionId));

final findingDetailProvider = FutureProvider.family<Finding, String>((ref, id) => ref.watch(apiProvider).finding(id));

final mediaProvider = FutureProvider.family<Json, String>((ref, versionId) => ref.watch(apiProvider).media(versionId));

final drawingProvider = FutureProvider.family<Json, String>((ref, versionId) => ref.watch(apiProvider).drawing(versionId));

/// Recent inspections for pickers (respects the dataset filter).
final recentInspectionsProvider = FutureProvider<List<Inspection>>((ref) async {
  final page = await ref.watch(apiProvider).inspections(dataset: ref.watch(datasetProvider), pageSize: 60);
  return page.items;
});

/// Invalidate everything derived from inspection data (after a run, review or upload).
void refreshInspectionData(WidgetRef ref, {String? inspectionId, String? versionId}) {
  ref.invalidate(recentInspectionsProvider);
  if (inspectionId != null) ref.invalidate(inspectionProvider(inspectionId));
  if (versionId != null) {
    ref.invalidate(findingsProvider(versionId));
    ref.invalidate(mediaProvider(versionId));
    ref.invalidate(drawingProvider(versionId));
  }
}
