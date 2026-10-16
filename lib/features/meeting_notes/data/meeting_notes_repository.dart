import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/meeting_note.dart';

/// Meeting notes and the assistant that matches them to events. Row level security limits
/// drafts to administrators; `apply_meeting_note` re-checks every change it makes.
class MeetingNotesRepository {
  MeetingNotesRepository(this._client);

  final SupabaseClient _client;

  /// Every note at the venue, newest first. Administrators only.
  Future<List<MeetingNote>> listNotes(String venueId) async {
    final rows = await _client
        .from('meeting_notes')
        .select()
        .eq('venue_id', venueId)
        .order('created_at', ascending: false)
        .limit(200);
    return rows.cast<Map<String, dynamic>>().map(MeetingNote.fromJson).toList();
  }

  /// Applied notes for one event. Readable by every member of the venue.
  Future<List<MeetingNote>> listForEvent(String eventId) async {
    final rows = await _client
        .from('meeting_notes')
        .select()
        .eq('event_id', eventId)
        .eq('status', MeetingNoteStatus.applied.code)
        .order('applied_at', ascending: false);
    return rows.cast<Map<String, dynamic>>().map(MeetingNote.fromJson).toList();
  }

  Future<MeetingNote> getNote(String noteId) async {
    final row = await _client
        .from('meeting_notes')
        .select()
        .eq('id', noteId)
        .maybeSingle();
    if (row == null) throw const AppFailure('That meeting note was not found.');
    return MeetingNote.fromJson(row);
  }

  Future<MeetingNote> createNote({
    required String venueId,
    required String title,
    required String body,
    DateTime? meetingAt,
    String? eventId,
  }) async {
    final row = await _client
        .from('meeting_notes')
        .insert({
          'venue_id': venueId,
          'title': title.trim(),
          'body': body.trim(),
          'meeting_at': meetingAt?.toUtc().toIso8601String(),
          'event_id': ?eventId,
        })
        .select()
        .single();
    return MeetingNote.fromJson(row);
  }

  /// Saves edits. Changing the text makes any earlier proposal out of date, so it is cleared.
  Future<MeetingNote> updateNote(
    String noteId, {
    required String title,
    required String body,
    DateTime? meetingAt,
  }) async {
    final row = await _client
        .from('meeting_notes')
        .update({
          'title': title.trim(),
          'body': body.trim(),
          'meeting_at': meetingAt?.toUtc().toIso8601String(),
          'status': MeetingNoteStatus.draft.code,
          'analysis': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', noteId)
        .select()
        .single();
    return MeetingNote.fromJson(row);
  }

  Future<void> setDismissed(String noteId, bool dismissed) async {
    await _client
        .from('meeting_notes')
        .update({
          'status': dismissed
              ? MeetingNoteStatus.dismissed.code
              : MeetingNoteStatus.draft.code,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', noteId);
  }

  Future<void> deleteNote(String noteId) async {
    await _client.from('meeting_notes').delete().eq('id', noteId);
  }

  /// Asks the assistant which event the note is about and what should change. Passing
  /// [eventId] skips the matching step and proposes changes for that event.
  Future<NoteAnalysis> analyze(String noteId, {String? eventId}) async {
    try {
      final response = await _client.functions.invoke(
        'meeting-notes-ai',
        body: {'note_id': noteId, 'event_id': ?eventId},
      );
      final data = response.data;
      if (data is Map && data['analysis'] is Map) {
        return NoteAnalysis.fromJson(
          (data['analysis'] as Map).cast<String, dynamic>(),
        );
      }
      throw const AppFailure('The assistant returned an unexpected response.');
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : 'The assistant could not be reached. Try again.';
      throw AppFailure(message);
    }
  }

  /// Links the note to [eventId] and makes the accepted [changes] in one transaction.
  Future<MeetingNote> apply({
    required String noteId,
    required String eventId,
    required String summary,
    required List<String> keyDetails,
    required List<ProposedChange> changes,
  }) async {
    final row = await _client.rpc<Map<String, dynamic>>(
      'apply_meeting_note',
      params: {
        'p_note': noteId,
        'p_event': eventId,
        'p_summary': summary.trim(),
        'p_key_details': keyDetails,
        'p_actions': [for (final change in changes) change.toApplyJson()],
      },
    );
    return MeetingNote.fromJson(row);
  }
}
