import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/guest_service.dart';

/// Guest preference cards, comps, and runner locations. Writes are checked again by the database.
class GuestServiceRepository {
  GuestServiceRepository(this._client);

  final SupabaseClient _client;

  Future<GuestPreferences> preferences(String suiteAssignmentId) async {
    final row = await _client
        .from('guest_preferences')
        .select()
        .eq('suite_assignment_id', suiteAssignmentId)
        .maybeSingle();
    if (row == null) {
      return GuestPreferences(suiteAssignmentId: suiteAssignmentId);
    }
    return GuestPreferences.fromJson(row).withVersionOne();
  }

  /// Saves the card. Managers and administrators only; the database enforces it.
  Future<void> savePreferences(
    String venueId,
    String eventId,
    GuestPreferences card,
  ) async {
    await _client.from('guest_preferences').upsert({
      'suite_assignment_id': card.suiteAssignmentId,
      'venue_id': venueId,
      'event_id': eventId,
      'seating': card.seating.trim(),
      'drink': card.drink.trim(),
      'allergies': card.allergies.trim(),
      'notes': card.notes.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'suite_assignment_id');
  }

  Future<List<Comp>> comps(String eventId) async {
    final rows = await _client
        .from('comps')
        .select()
        .eq('event_id', eventId)
        .order('requested_at', ascending: false);
    return rows.cast<Map<String, dynamic>>().map(Comp.fromJson).toList();
  }

  Future<void> requestComp({
    required String venueId,
    required String eventId,
    required int amountCents,
    required String reason,
    String? suiteAssignmentId,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw const AppFailure('Give a reason for the comp.');
    await _client.from('comps').insert({
      'venue_id': venueId,
      'event_id': eventId,
      'suite_assignment_id': suiteAssignmentId,
      'amount_cents': amountCents,
      'reason': trimmed,
    });
  }

  /// Approve or reject a pending comp. Only managers and administrators can call it.
  Future<void> decideComp(
    String compId, {
    required CompStatus decision,
    required int expectedVersion,
    String note = '',
  }) async {
    await _client.rpc<void>(
      'decide_comp',
      params: {
        'p_comp': compId,
        'p_decision': decision.code,
        'p_expected_version': expectedVersion,
        'p_note': note.trim(),
      },
    );
  }

  Future<void> recordLocation({
    required String venueId,
    required String eventId,
    required String requestId,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) async {
    await _client.from('runner_locations').insert({
      'venue_id': venueId,
      'event_id': eventId,
      'request_id': requestId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_m': accuracyMeters,
    });
  }
}

extension on GuestPreferences {
  /// Preference cards saved to the database carry a version; the first save starts at one.
  GuestPreferences withVersionOne() => GuestPreferences(
    suiteAssignmentId: suiteAssignmentId,
    seating: seating,
    drink: drink,
    allergies: allergies,
    notes: notes,
    version: 1,
  );
}
