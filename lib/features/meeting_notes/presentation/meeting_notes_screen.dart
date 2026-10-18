import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/venue_time.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../../events/application/event_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../application/meeting_notes_providers.dart';
import '../domain/meeting_note.dart';

Tone meetingNoteStatusTone(MeetingNoteStatus status) => switch (status) {
  MeetingNoteStatus.draft => Tone.neutral,
  MeetingNoteStatus.analyzed => Tone.alert,
  MeetingNoteStatus.applied => Tone.accent,
  MeetingNoteStatus.dismissed => Tone.neutral,
};

const _kicker = 'Planning';
const _title = 'Meeting Notes';

/// Administrators record meeting notes here. The assistant finds the event each note is about
/// and proposes changes; nothing changes until an administrator applies them.
class MeetingNotesScreen extends ConsumerWidget {
  const MeetingNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) {
      return const PageScaffold(
        kicker: _kicker,
        title: _title,
        children: [EmptyNote('Connect a backend to record meeting notes.')],
      );
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/meeting-notes/new'),
        icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
        label: const Text('New meeting note'),
      ),
      body: const SafeArea(bottom: false, child: _NoteList()),
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
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screen,
          0,
          AppSpace.screen,
          96,
        ),
        children: [
          const ScreenHeader(kicker: _kicker, title: _title, padded: false),
          const OpenRow(
            leading: PhosphorIcon(
              PhosphorIconsDuotone.sparkle,
              color: AppColors.accent700,
            ),
            title: 'Write or paste notes from a meeting',
            meta:
                'The assistant finds the event they are about and suggests updates: guest count, '
                'timing, tasks, menu, suite details, and notes for staff. You review every change '
                'before it is applied.',
          ),
          const SizedBox(height: AppSpace.l),
          ...notes.when(
            loading: () => const [LinearProgressIndicator()],
            error: (error, _) => [Text(userMessageFor(error))],
            data: (list) => list.isEmpty
                ? const [EmptyNote('No meeting notes yet.')]
                : [
                    for (final note in list)
                      OpenRow(
                        title: note.displayTitle,
                        meta:
                            '${note.eventId == null ? 'No event linked' : events[note.eventId] ?? 'Event'}'
                            ' · ${DateFormat('MMM d, y').format(atVenue(note.meetingAt ?? note.createdAt, zone))}',
                        trailing: Tag(
                          note.status.label,
                          meetingNoteStatusTone(note.status),
                        ),
                        onTap: () => context.push('/meeting-notes/${note.id}'),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}
