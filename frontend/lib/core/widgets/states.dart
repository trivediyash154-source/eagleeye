import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../theme/tokens.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon = Icons.inbox_outlined, this.action});
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(EE.s8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(border: Border.all(color: EE.lineHi), borderRadius: BorderRadius.circular(EE.r2), color: EE.surfaceHi),
                child: Icon(icon, color: EE.textMuted, size: 24),
              ),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[const SizedBox(height: 6), Text(message!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center)],
              if (action != null) ...[const SizedBox(height: 16), action!],
            ]),
          ),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.error, {super.key, this.onRetry, this.compact = false});
  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final api = error is ApiException ? error as ApiException : null;
    final title = api?.isNetwork == true
        ? 'Backend not reachable'
        : api?.status == 404
            ? 'Not found'
            : 'Something went wrong';
    final msg = error.toString();
    if (compact) {
      return Row(children: [
        const Icon(Icons.error_outline_rounded, color: EE.fail, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(color: EE.fail, fontSize: 12.5))),
        if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]);
    }
    return EmptyState(
      title: title,
      message: msg + (api?.code != null && api!.code != 'error' && api.code != 'network' ? '  [${api.code}]' : ''),
      icon: api?.isNetwork == true ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
      action: onRetry == null ? null : OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Retry')),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading'});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(EE.s8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 2)),
            const SizedBox(height: 12),
            Text(label.toUpperCase(), style: const TextStyle(fontFamily: EE.fontMono, fontSize: 10.5, letterSpacing: 1.6, color: EE.textDim)),
          ]),
        ),
      );
}

/// Renders an AsyncValue with consistent loading / error / data states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView(this.value, {super.key, required this.data, this.onRetry, this.loadingLabel = 'Loading'});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return data(value.requireValue);
    if (value.hasError) return ErrorView(value.error!, onRetry: onRetry);
    return LoadingView(label: loadingLabel);
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: error ? EE.fail : EE.pass, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(message)),
    ]),
  ));
}
