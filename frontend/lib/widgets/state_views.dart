import 'package:flutter/material.dart';

/// Shared empty/error/loading placeholders so every list screen looks and
/// behaves the same instead of each hand-rolling its own Icon+Text column.
/// Used inside a ListView (so pull-to-refresh still works) by callers.

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 44, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wraps the three states above so screens can write one `switch` instead of
/// repeating `if (_error != null) ... if (_data == null) ...` scaffolding.
/// Still lets callers embed the result of `builder` in their own ListView
/// (for pull-to-refresh) since it just returns a widget, not a full Scaffold.
class DataStateView<T> extends StatelessWidget {
  const DataStateView({
    super.key,
    required this.data,
    required this.error,
    required this.builder,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyMessage = 'Nothing here yet.',
    this.onRetry,
    this.isEmpty,
  });

  final T? data;
  final String? error;
  final Widget Function(BuildContext context, T data) builder;
  final IconData emptyIcon;
  final String emptyMessage;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;

  @override
  Widget build(BuildContext context) {
    if (error != null) return ErrorState(message: error!, onRetry: onRetry);
    final d = data;
    if (d == null) return const LoadingState();
    if (isEmpty != null && isEmpty!(d)) {
      return EmptyState(icon: emptyIcon, message: emptyMessage);
    }
    return builder(context, d);
  }
}
