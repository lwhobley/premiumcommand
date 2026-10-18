import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
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
            SectionHeading(
              pending == 0
                  ? 'Your assignments'
                  : 'Your assignments · $pending to acknowledge',
              first: true,
            ),
            for (final a in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: OpenRow(
                  title: a.eventName,
                  trailing: Tag(
                    a.acknowledged ? 'Acknowledged' : 'Needs acknowledgment',
                    a.acknowledged ? Tone.accent : Tone.alert,
                  ),
                  meta: '${a.roleLabel} · ${a.location}',
                  below: a.acknowledged
                      ? null
                      : FilledButton(
                          onPressed: () => _acknowledge(context, ref, a),
                          child: const Text('Acknowledge'),
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
