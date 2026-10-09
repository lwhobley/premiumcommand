import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/outbox.dart';
import '../../../core/theme/app_theme.dart';
import '../application/sync_controller.dart';

/// Shows queued and review-needed changes above every screen. Hidden when there is nothing to report.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncControllerProvider);
    if (!state.hasWork) return const SizedBox.shrink();

    final review = state.needsReview > 0;
    final color = review ? AppColors.blocked : AppColors.attention;
    final message = review
        ? '${state.needsReview} change(s) need your review.'
        : state.syncing
            ? 'Syncing ${state.pending} change(s)…'
            : '${state.pending} change(s) saved on this device. Waiting to sync.';

    return Material(
      color: color.withValues(alpha: 0.10),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(review ? Icons.rule_outlined : Icons.cloud_off_outlined, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
              TextButton(
                onPressed: () => showDialog<void>(context: context, builder: (_) => const _ReviewDialog()),
                child: const Text('Review'),
              ),
              TextButton(
                onPressed: state.syncing ? null : () => ref.read(syncControllerProvider.notifier).flush(),
                child: const Text('Sync now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewDialog extends ConsumerWidget {
  const _ReviewDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild when the queue changes so retry and discard reflect immediately.
    ref.watch(syncControllerProvider);
    final items = ref.read(syncControllerProvider.notifier).items;
    final controller = ref.read(syncControllerProvider.notifier);

    return AlertDialog(
      title: const Text('Changes on this device'),
      content: SizedBox(
        width: 480,
        child: items.isEmpty
            ? const Text('Nothing waiting.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final OutboxItem item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        item.needsReview ? Icons.error_outline : Icons.schedule,
                        color: item.needsReview ? AppColors.blocked : AppColors.attention,
                      ),
                      title: Text(_label(item.kind)),
                      subtitle: Text(item.needsReview
                          ? item.lastError
                          : 'Saved ${_ago(item.createdAt)}'),
                      trailing: item.needsReview
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              TextButton(onPressed: () => controller.retry(item.id), child: const Text('Retry')),
                              TextButton(onPressed: () => controller.discard(item.id), child: const Text('Discard')),
                            ])
                          : null,
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  static String _label(String kind) => switch (kind) {
        outboxCreateRequest => 'New service request',
        outboxTransitionRequest => 'Service request update',
        outboxSetTaskStatus => 'Task update',
        _ => 'Change',
      };

  static String _ago(DateTime at) {
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'just now';
    if (minutes < 60) return '$minutes min ago';
    return '${minutes ~/ 60} h ago';
  }
}
