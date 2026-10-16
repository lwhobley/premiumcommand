import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/venue_time.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../application/meeting_notes_providers.dart';

/// Applied meeting notes on the event workspace. Administrators can add new notes from here,
/// already linked to this event.
class EventMeetingNotesCard extends ConsumerWidget {
  const EventMeetingNotesCard({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) return const SizedBox.shrink();
    final session = ref.watch(sessionProvider);
    final isAdmin = session?.can(AppPermission.manageConfiguration) ?? false;
    final zone = session?.timeZone ?? 'UTC';
    final notes = ref.watch(eventMeetingNotesProvider(eventId));

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Meeting notes',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (isAdmin)
                TextButton.icon(
                  onPressed: () =>
                      context.push('/meeting-notes/new?event=$eventId'),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Add notes'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          notes.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text(userMessageFor(error)),
            data: (list) => list.isEmpty
                ? const Text(
                    'No meeting notes for this event.',
                    style: TextStyle(color: AppColors.charcoalMuted),
                  )
                : Column(
                    children: [
                      for (final note in list)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: isAdmin
                                ? () =>
                                      context.push('/meeting-notes/${note.id}')
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    note.displayTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    DateFormat('MMM d, y').format(
                                      atVenue(
                                        note.meetingAt ??
                                            note.appliedAt ??
                                            note.createdAt,
                                        zone,
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: AppColors.charcoalMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (note.summary.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(note.summary),
                                  ],
                                  if (note.keyDetails.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    for (final detail in note.keyDetails)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 2,
                                        ),
                                        child: Text('•  $detail'),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
