import 'package:cutx_premium_command/app/app_section.dart';
import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/meeting_notes/domain/meeting_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteAnalysis', () {
    final json = {
      'event_id': 'event-1',
      'match': {
        'confidence': 'medium',
        'reason': 'The notes mention Saturday\'s Hawks game.',
        'alternative_event_ids': ['event-2'],
        'chosen_by': 'assistant',
      },
      'summary': 'Headcount rises to 180.',
      'key_details': ['180 guests', 'Gluten-free dessert'],
      'changes': [
        {
          'type': 'update_event',
          'field': 'guaranteed_guests',
          'value': '180',
          'current': '150',
          'reason': 'Client confirmed 180.',
        },
        {
          'type': 'add_task',
          'department': 'culinary',
          'title': 'Plan gluten-free dessert',
          'is_required': true,
          'due_at': '2026-10-17T12:00-05:00',
          'reason': 'Two guests are celiac.',
        },
        {
          'type': 'update_suite',
          'assignment_id': 'assignment-1',
          'field': 'dietary_notes',
          'value': 'Nut allergy',
          'current': '',
          'suite_name': 'Suite 12',
          'reason': 'Host has a nut allergy.',
        },
        {'type': 'something_new', 'reason': 'From a newer server'},
      ],
      'analyzed_at': '2026-10-16T14:00:00Z',
    };

    test('reads the match, summary, and known change types', () {
      final analysis = NoteAnalysis.fromJson(json);
      expect(analysis.eventId, 'event-1');
      expect(analysis.match.confidence, MatchConfidence.medium);
      expect(analysis.match.alternativeEventIds, ['event-2']);
      expect(analysis.match.chosenByAdministrator, isFalse);
      expect(analysis.keyDetails, hasLength(2));
      // The unknown change type is skipped rather than breaking the screen.
      expect(analysis.changes.map((c) => c.type), [
        ProposedChangeType.updateEvent,
        ProposedChangeType.addTask,
        ProposedChangeType.updateSuite,
      ]);
    });

    test('describes changes for review', () {
      final changes = NoteAnalysis.fromJson(json).changes;
      expect(changes[0].title, 'Change guaranteed guests');
      expect(changes[0].text, '180');
      expect(changes[0].detail, 'Currently: 150');
      expect(changes[1].title, 'Add Culinary task, required');
      expect(changes[1].dueAt, DateTime.utc(2026, 10, 17, 17));
      expect(changes[2].title, 'Suite 12 dietary notes');
      expect(changes[2].detail, 'Currently empty');
    });

    test(
      'apply payload keeps the fields the database checks and the edited text',
      () {
        final task = NoteAnalysis.fromJson(json).changes[1]
            .withText('Plan a GF dessert');
        final payload = task.toApplyJson();
        expect(payload['type'], 'add_task');
        expect(payload['title'], 'Plan a GF dessert');
        expect(payload['department'], 'culinary');
        expect(payload['is_required'], true);
        expect(payload['reason'], 'Two guests are celiac.');
        expect(payload.containsKey('current'), isFalse);
      },
    );
  });

  group('MeetingNote', () {
    test('reads an applied note with its changes', () {
      final note = MeetingNote.fromJson({
        'id': 'note-1',
        'venue_id': 'venue-1',
        'event_id': 'event-1',
        'title': '',
        'body': 'Walkthrough with the client\nThey want 180 guests.',
        'meeting_at': null,
        'status': 'applied',
        'analysis': null,
        'summary': 'Headcount rises to 180.',
        'key_details': ['180 guests'],
        'applied_actions': [
          {
            'type': 'append_event_notes',
            'text': 'Client prefers still water.',
            'reason': '',
          },
        ],
        'applied_at': '2026-10-16T15:00:00Z',
        'created_at': '2026-10-16T14:00:00Z',
      });
      expect(note.isApplied, isTrue);
      expect(note.displayTitle, 'Walkthrough with the client');
      expect(
        note.appliedChanges.single.type,
        ProposedChangeType.appendEventNotes,
      );
      expect(note.appliedChanges.single.text, 'Client prefers still water.');
    });
  });

  test('meeting notes are for administrators only', () {
    expect(
      AppSection.meetingNotes.allows(permissionsFor({AppRole.director})),
      isTrue,
    );
    for (final role in AppRole.values.where((r) => r != AppRole.director)) {
      expect(
        AppSection.meetingNotes.allows(permissionsFor({role})),
        isFalse,
        reason: role.code,
      );
    }
  });
}
