import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/session_controller.dart';
import '../data/meeting_notes_repository.dart';
import '../domain/meeting_note.dart';

final meetingNotesRepositoryProvider = Provider<MeetingNotesRepository>((ref) {
  ref.watch(sessionProvider);
  return MeetingNotesRepository(Supabase.instance.client);
});

/// Every meeting note at the signed-in venue. Administrators only.
final meetingNotesProvider = FutureProvider<List<MeetingNote>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  return ref.watch(meetingNotesRepositoryProvider).listNotes(session.venueId);
});

/// Applied notes shown on an event.
final eventMeetingNotesProvider =
    FutureProvider.family<List<MeetingNote>, String>((ref, eventId) {
      return ref.watch(meetingNotesRepositoryProvider).listForEvent(eventId);
    });
