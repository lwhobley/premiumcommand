import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../application/staff_providers.dart';
import '../domain/my_assignment.dart';

/// The signed-in person's assignments, with a button to acknowledge each one. Shows nothing when
/// there are no assignments.
class MyAssignmentsCard extends ConsumerWidget {
  const MyAssignmentsCard({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(myAssignmentsProvider(userId));
    return assignments.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text(userMessageFor(error)),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final pending = items.where((a) => !a.acknowledged).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pending == 0
                  ? 'Your assignments'
                  : 'Your assignments · $pending to acknowledge',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final a in items)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.eventName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          StatusChip(
                            label: a.acknowledged
                                ? 'Acknowledged'
                                : 'Needs acknowledgment',
                            color: a.acknowledged
                                ? AppColors.ready
                                : AppColors.attention,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${a.roleLabel} · ${a.location}'),
                      if (!a.acknowledged) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: () => _acknowledge(context, ref, a),
                            child: const Text('Acknowledge'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _acknowledge(
    BuildContext context,
    WidgetRef ref,
    MyAssignment a,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(staffRepositoryProvider).acknowledgeAssignment(a.id);
      ref.invalidate(myAssignmentsProvider(userId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Assignment acknowledged.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    }
  }
}
