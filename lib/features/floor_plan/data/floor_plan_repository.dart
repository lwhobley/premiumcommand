import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/floor_plan.dart';

class FloorPlanRepository {
  FloorPlanRepository(this._client);

  final SupabaseClient _client;

  Future<List<VenueSpace>> listVenueSpaces(String venueId) async {
    final rows = await _client.from('venue_spaces').select().eq('venue_id', venueId).order('name');
    return rows.cast<Map<String, dynamic>>().map(VenueSpace.fromJson).toList();
  }

  /// `null` if the space has no saved floor plan yet.
  Future<VenueSpaceFloorPlan?> getFloorPlan(String venueSpaceId) async {
    final row = await _client
        .from('venue_space_floor_plans')
        .select()
        .eq('venue_space_id', venueSpaceId)
        .maybeSingle();
    return row == null ? null : VenueSpaceFloorPlan.fromJson(row);
  }

  /// The venue-space ids assigned to an event, via `event_spaces`.
  Future<List<String>> listEventSpaceIds(String eventId) async {
    final rows = await _client.from('event_spaces').select('venue_space_id').eq('event_id', eventId);
    return rows.cast<Map<String, dynamic>>().map((row) => row['venue_space_id'] as String).toList();
  }

  Future<VenueSpaceFloorPlan> saveFloorPlan(String venueId, VenueSpaceFloorPlan plan) async {
    final row = await _client
        .from('venue_space_floor_plans')
        .upsert({'venue_id': venueId, ...plan.toUpsertJson()}, onConflict: 'venue_space_id')
        .select()
        .single();
    return VenueSpaceFloorPlan.fromJson(row);
  }
}
