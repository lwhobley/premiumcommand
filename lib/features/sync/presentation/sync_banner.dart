import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/outbox.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/tag.dart';
import '../application/sync_controller.dart';

/// Shows queued and review-needed changes above every screen. Hidden when there is nothing to report.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncControllerProvider);
    if (!state.hasWork) return const SizedBox.shrink();

    final review = state.needsReview > 0;
    final foreground = review ? AppColors.accent2800 : AppColors.accent800;
    final message = review
        ? '${state.needsReview} change(s) need your review.'
        : state.syncing
        ? 'Syncing ${state.pending} change(s)…'
        : '${state.pending} change(s) saved on this device. Waiting to sync.';

    return Material(
      color: review ? AppColors.accent2100 : AppColors.accent100,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.screen, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _ReviewDialog(),
                ),
                child: const Text('Review'),
              ),
              TextButton(
                onPressed: state.syncing
                    ? null
                    : () => ref.read(syncControllerProvider.notifier).flush(),
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
                      leading: Tag(
                        item.needsReview ? 'Review' : 'Waiting',
                        item.needsReview ? Tone.alert : Tone.neutral,
                      ),
                      title: Text(_label(item.kind)),
                      subtitle: Text(
                        item.needsReview
                            ? item.lastError
                            : 'Saved ${_ago(item.createdAt)}',
                      ),
                      trailing: item.needsReview
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => controller.retry(item.id),
                                  child: const Text('Retry'),
                                ),
                                TextButton(
                                  onPressed: () => controller.discard(item.id),
                                  child: const Text('Discard'),
                                ),
                              ],
                            )
                          : null,
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
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
