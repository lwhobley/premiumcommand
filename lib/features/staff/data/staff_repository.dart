import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/my_assignment.dart';
import '../domain/staff_availability.dart';
import '../domain/staff_profile.dart';

/// Staff accounts. Reads go through row-level security, so a staff member sees only their own
/// profile. Writes are checked again by the database; PIN and account changes also pass through
/// the staff-admin edge function.
class StaffRepository {
  StaffRepository(this._client);

  final SupabaseClient _client;

  Future<List<StaffProfile>> list(String venueId) async {
    final rows = await _client
        .from('staff_profiles')
        .select()
        .eq('venue_id', venueId)
        .order('full_name');
    return rows
        .cast<Map<String, dynamic>>()
        .map(StaffProfile.fromJson)
        .toList();
  }

  /// Creates the account and returns the new profile id. The PIN is sent once and never kept
  /// by the app.
  Future<String> create({
    required String venueId,
    required Map<String, Object?> fields,
    required List<String> roles,
    required String pin,
  }) async {
    final data = await _invoke({
      'action': 'create',
      'venue_id': venueId,
      'fields': fields,
      'roles': roles,
      'pin': pin,
    });
    return data['id'] as String;
  }

  Future<void> updateDetails(
    StaffProfile profile,
    Map<String, Object?> fields,
  ) async {
    await _client.rpc<void>(
      'staff_update_profile',
      params: {
        'p_profile': profile.id,
        'p_fields': fields,
        'p_expected_version': profile.version,
      },
    );
  }

  Future<void> setPin(String profileId, String pin) async {
    await _invoke({'action': 'set_pin', 'profile_id': profileId, 'pin': pin});
  }

  Future<void> setActive(String profileId, bool active) async {
    await _invoke({
      'action': 'set_status',
      'profile_id': profileId,
      'active': active,
    });
  }

  Future<void> remove(String profileId) async {
    await _invoke({'action': 'remove', 'profile_id': profileId});
  }

  /// Uploads the photo to the private bucket, then records its path on the profile.
  Future<void> uploadPhoto(
    String venueId,
    String profileId,
    Uint8List jpeg,
  ) async {
    final path = staffPhotoPath(venueId, profileId);
    await _client.storage
        .from('staff-photos')
        .uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(
            upsert: true,
            cacheControl: '0',
            contentType: 'image/jpeg',
          ),
        );
    await _client.rpc<void>(
      'staff_set_photo',
      params: {'p_profile': profileId, 'p_path': path},
    );
  }

  /// A short-lived link to a photo the caller is allowed to see.
  Future<String> photoUrl(String path) async {
    final signed = Uri.parse(
      await _client.storage.from('staff-photos').createSignedUrl(path, 3600),
    );
    // A replaced photo uses the same storage path. Give each renewed link a new
    // cache key so clients and intermediaries fetch the current bytes.
    return signed
        .replace(
          queryParameters: {
            ...signed.queryParameters,
            'v': DateTime.now().microsecondsSinceEpoch.toString(),
          },
        )
        .toString();
  }

  /// Staff directory without contact details. Requires view_deployment.
  Future<List<StaffDirectoryEntry>> directory(String venueId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'staff_directory',
      params: {'p_venue': venueId},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(StaffDirectoryEntry.fromJson)
        .toList();
  }

  /// Availability windows that end within the last day or later, for the whole venue.
  Future<List<StaffAvailability>> availability(String venueId) async {
    final since = DateTime.now()
        .subtract(const Duration(days: 1))
        .toUtc()
        .toIso8601String();
    final rows = await _client
        .from('staff_availability')
        .select()
        .eq('venue_id', venueId)
        .gte('ends_at', since)
        .order('starts_at');
    return rows
        .cast<Map<String, dynamic>>()
        .map(StaffAvailability.fromJson)
        .toList();
  }

  Future<void> addAvailability({
    required String venueId,
    required String userId,
    required AvailabilityStatus status,
    required DateTime startsAt,
    required DateTime endsAt,
    required String note,
  }) async {
    await _client.from('staff_availability').insert({
      'venue_id': venueId,
      'user_id': userId,
      'status': status.code,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'note': note.trim(),
    });
  }

  Future<void> deleteAvailability(String id) async {
    await _client.from('staff_availability').delete().eq('id', id);
  }

  /// The signed-in person's assignments on events that have not closed.
  Future<List<MyAssignment>> myAssignments(String userId) async {
    final rows = await _client
        .from('event_staff')
        .select(
          'id, role_label, department, zone, station, acknowledged_at, '
          'events(name, status), suite_event_assignments(venue_suites(name))',
        )
        .eq('user_id', userId)
        .order('created_at');
    return rows
        .cast<Map<String, dynamic>>()
        .where((row) {
          final status = (row['events'] as Map?)?['status'];
          return status != 'closed' && status != 'cancelled';
        })
        .map(MyAssignment.fromJson)
        .toList();
  }

  /// Records that the signed-in person has read their assignment. The database accepts only
  /// the person's own assignments.
  Future<void> acknowledgeAssignment(String staffId) async {
    await _client.rpc<void>(
      'acknowledge_assignment',
      params: {'p_staff': staffId},
    );
  }

  Future<Map<String, dynamic>> _invoke(Map<String, Object?> body) async {
    try {
      final response = await _client.functions.invoke(
        'staff-admin',
        body: body,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      throw const AppFailure('The request returned an unexpected response.');
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : 'The request failed. Try again.';
      throw AppFailure(message);
    }
  }
}
