import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/venue_time.dart';
import '../../../core/widgets/broadsheet.dart';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Meeting notes',
          trailing: isAdmin
              ? TextButton.icon(
                  onPressed: () =>
                      context.push('/meeting-notes/new?event=$eventId'),
                  icon: const PhosphorIcon(PhosphorIconsDuotone.notePencil),
                  label: const Text('Add notes'),
                )
              : null,
        ),
        notes.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text(userMessageFor(error)),
          data: (list) => list.isEmpty
              ? const EmptyNote('No meeting notes for this event.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final note in list)
                      OpenRow(
                        title: note.displayTitle,
                        meta: DateFormat('MMM d, y').format(
                          atVenue(
                            note.meetingAt ?? note.appliedAt ?? note.createdAt,
                            zone,
                          ),
                        ),
                        below: note.summary.isEmpty && note.keyDetails.isEmpty
                            ? null
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (note.summary.isNotEmpty)
                                    Text(note.summary, style: AppText.body),
                                  if (note.summary.isNotEmpty &&
                                      note.keyDetails.isNotEmpty)
                                    const SizedBox(height: 8),
                                  for (final detail in note.keyDetails)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Text(
                                        '•  $detail',
                                        style: AppText.body,
                                      ),
                                    ),
                                ],
                              ),
                        onTap: isAdmin
                            ? () => context.push('/meeting-notes/${note.id}')
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
