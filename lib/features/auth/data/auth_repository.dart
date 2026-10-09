import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../dispatch/domain/routing.dart';
import '../../events/domain/readiness.dart';
import '../domain/app_session.dart';

abstract interface class AuthRepository {
  Future<AppSession?> restoreSession();

  Future<AppSession> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

/// Demo mode: no backend. Lets any role be previewed with sample data.
class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository({this.demoRole = AppRole.director});

  final AppRole demoRole;

  @override
  Future<AppSession?> restoreSession() async => null;

  @override
  Future<AppSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    throw const AppFailure('Password sign-in needs a Supabase connection. Use demo sign-in.');
  }

  /// Returns a demo session for [role] at the demo venue.
  AppSession demoSession(AppRole role) {
    return AppSession(
      userId: 'demo-user-${role.code}',
      displayName: 'Demo ${role.label}',
      venueId: demoVenueId,
      venueName: 'Demonstration Venue (sample data)',
      timeZone: 'America/Chicago',
      roles: {role},
      departments: departmentsFor({role}),
    );
  }

  @override
  Future<void> signOut() async {}

  static const demoVenueId = 'demo-venue';
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AppSession?> restoreSession() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return _loadSession(user);
  }

  @override
  Future<AppSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(email: email, password: password);
    final user = response.user;
    if (user == null) throw const AppFailure('Sign-in failed. Check your email and password.');
    return _loadSession(user);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  /// Loads venue access from the database. RLS limits these rows to the caller.
  Future<AppSession> _loadSession(User user) async {
    final rows = (await _client
            .from('role_assignments')
            .select('role_code, venue_id, venues(name, time_zone)')
            .eq('user_id', user.id))
        .cast<Map<String, dynamic>>();

    if (rows.isEmpty) {
      throw const AppFailure('This account has no venue access yet. Contact your administrator.');
    }

    // Venue selection is single-venue for now; multi-venue switching is a later milestone.
    final venueId = rows.first['venue_id'] as String;
    final venue = rows.first['venues'] as Map<String, dynamic>;
    final roles = rows
        .where((row) => row['venue_id'] == venueId)
        .map((row) => AppRole.fromCode(row['role_code'] as String))
        .whereType<AppRole>()
        .toSet();

    final profile = await _client
        .from('user_profiles')
        .select('display_name')
        .eq('id', user.id)
        .maybeSingle();

    final deptRows = (await _client
            .from('department_memberships')
            .select('department')
            .eq('venue_id', venueId)
            .eq('user_id', user.id))
        .cast<Map<String, dynamic>>();
    final departments = {for (final r in deptRows) Department.fromCode(r['department'] as String)};

    return AppSession(
      userId: user.id,
      displayName: (profile?['display_name'] as String?) ?? user.email ?? 'Team member',
      venueId: venueId,
      venueName: venue['name'] as String,
      timeZone: venue['time_zone'] as String,
      roles: roles,
      departments: departments,
    );
  }
}
