import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/auth/application/session_controller.dart';
import 'package:cutx_premium_command/features/events/application/event_providers.dart';
import 'package:cutx_premium_command/features/meeting_notes/application/meeting_notes_providers.dart';
import 'package:cutx_premium_command/features/meeting_notes/data/meeting_notes_repository.dart';
import 'package:cutx_premium_command/features/meeting_notes/domain/meeting_note.dart';
import 'package:cutx_premium_command/features/meeting_notes/presentation/meeting_note_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serves one note and records what the screen applies. No network.
class _FakeRepository extends MeetingNotesRepository {
  _FakeRepository(this.note)
    : super(
        SupabaseClient(
          'http://localhost',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final Map<String, dynamic> note;
  List<ProposedChange>? applied;
  String? appliedEventId;

  @override
  Future<MeetingNote> getNote(String noteId) async =>
      MeetingNote.fromJson(note);

  @override
  Future<MeetingNote> apply({
    required String noteId,
    required String eventId,
    required String summary,
    required List<String> keyDetails,
    required List<ProposedChange> changes,
  }) async {
    applied = changes;
    appliedEventId = eventId;
    return MeetingNote.fromJson({
      ...note,
      'status': 'applied',
      'event_id': eventId,
      'summary': summary,
      'key_details': keyDetails,
      'applied_actions': [for (final c in changes) c.toApplyJson()],
      'applied_at': '2026-10-16T15:00:00Z',
    });
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'an administrator reviews the proposal and applies only the accepted changes',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      container.read(sessionProvider.notifier).signInAsDemo(AppRole.director);
      final event = (await container.read(eventSnapshotsProvider.future))
          .first
          .event;

      final repo = _FakeRepository({
        'id': 'note-1',
        'venue_id': event.venueId,
        'title': 'Client walkthrough',
        'body': 'Client confirmed 180 guests. Two guests are celiac.',
        'status': 'analyzed',
        'created_at': '2026-10-16T14:00:00Z',
        'analysis': {
          'event_id': event.id,
          'match': {
            'confidence': 'high',
            'reason': 'The notes name this event.',
            'alternative_event_ids': [],
            'chosen_by': 'assistant',
          },
          'summary': 'Headcount rises to 180.',
          'key_details': ['180 guests'],
          'changes': [
            {
              'type': 'update_event',
              'field': 'guaranteed_guests',
              'value': '180',
              'current': '${event.guaranteedGuests}',
              'reason': 'Client confirmed 180 guests.',
            },
            {
              'type': 'add_task',
              'department': 'culinary',
              'title': 'Plan gluten-free dessert',
              'is_required': true,
              'due_at': null,
              'reason': 'Two guests are celiac.',
            },
          ],
        },
      });

      final scope = ProviderContainer(
        parent: container,
        overrides: [meetingNotesRepositoryProvider.overrideWithValue(repo)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: const MaterialApp(
            home: MeetingNoteEditorScreen(noteId: 'note-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The page's list; the text fields inside it scroll too.
      final page = find.byType(Scrollable).first;
      final reason = find.text('The notes name this event.');
      await tester.scrollUntilVisible(reason, 200, scrollable: page);
      expect(reason, findsOneWidget);
      final summary = find.text('Headcount rises to 180.');
      await tester.scrollUntilVisible(summary, 200, scrollable: page);
      expect(summary, findsOneWidget);

      final task = find.text('Plan gluten-free dessert');
      await tester.scrollUntilVisible(task, 200, scrollable: page);
      expect(find.text('Change guaranteed guests'), findsOneWidget);
      expect(find.text('Add Culinary task, required'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Leave the task out.
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();

      final apply = find.text('Apply 1 change to event');
      await tester.scrollUntilVisible(apply, 200, scrollable: page);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(repo.appliedEventId, event.id);
      expect(repo.applied!.map((c) => c.type), [
        ProposedChangeType.updateEvent,
      ]);
      expect(find.text('Applied to ${event.name}'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      scope.dispose();
      container.dispose();
    },
  );
}
