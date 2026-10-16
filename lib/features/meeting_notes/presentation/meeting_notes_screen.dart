import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/venue_time.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/application/session_controller.dart';
import '../../events/application/event_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../application/meeting_notes_providers.dart';
import '../domain/meeting_note.dart';

Color meetingNoteStatusColor(MeetingNoteStatus status) => switch (status) {
  MeetingNoteStatus.draft => AppColors.neutral,
  MeetingNoteStatus.analyzed => AppColors.attention,
  MeetingNoteStatus.applied => AppColors.ready,
  MeetingNoteStatus.dismissed => AppColors.neutral,
};

/// Administrators record meeting notes here. The assistant finds the event each note is about
/// and proposes changes; nothing changes until an administrator applies them.
class MeetingNotesScreen extends ConsumerWidget {
  const MeetingNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meeting Notes')),
      floatingActionButton: backendAvailable
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/meeting-notes/new'),
              icon: const Icon(Icons.add),
              label: const Text('New meeting note'),
            )
          : null,
      body: backendAvailable
          ? const _NoteList()
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Connect a backend to record meeting notes.',
                  style: TextStyle(color: AppColors.charcoalMuted),
                ),
              ),
            ),
    );
  }
}

class _NoteList extends ConsumerWidget {
  const _NoteList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(meetingNotesProvider);
    final zone = ref.watch(sessionProvider)?.timeZone ?? 'UTC';
    final events = {
      for (final snapshot
          in ref.watch(eventSnapshotsProvider).value ?? const [])
        snapshot.event.id: snapshot.event.name,
    };

    return RefreshIndicator(
      onRefresh: () => ref.refresh(meetingNotesProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(
                Icons.auto_awesome_outlined,
                color: AppColors.brass,
              ),
              title: Text('Write or paste notes from a meeting'),
              subtitle: Text(
                'The assistant finds the event they are about and suggests updates: guest count, '
                'timing, tasks, menu, suite details, and notes for staff. You review every change '
                'before it is applied.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...notes.when(
            loading: () => const [
              Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            ],
            error: (error, _) => [Text(userMessageFor(error))],
            data: (list) => list.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No meeting notes yet.',
                        style: TextStyle(color: AppColors.charcoalMuted),
                      ),
                    ),
                  ]
                : [
                    for (final note in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(note.displayTitle),
                          subtitle: Text(
                            '${note.eventId == null ? 'No event linked' : events[note.eventId] ?? 'Event'}'
                            ' · ${DateFormat('MMM d, y').format(atVenue(note.meetingAt ?? note.createdAt, zone))}',
                          ),
                          trailing: StatusChip(
                            label: note.status.label,
                            color: meetingNoteStatusColor(note.status),
                          ),
                          onTap: () =>
                              context.push('/meeting-notes/${note.id}'),
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}
