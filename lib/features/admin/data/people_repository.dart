import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/permissions/app_permission.dart';
import '../../events/domain/readiness.dart';

/// One person with access to the venue, as administrators see them.
class PersonAccess {
  const PersonAccess({
    required this.userId,
    required this.name,
    required this.email,
    required this.active,
    required this.roles,
    required this.departments,
  });

  final String userId;
  final String name;
  final String email;
  final bool active;
  final Set<AppRole> roles;
  final Set<Department> departments;

  factory PersonAccess.fromJson(Map<String, dynamic> json) {
    return PersonAccess(
      userId: json['user_id'] as String,
      name: (json['display_name'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      active: json['membership_status'] == 'active',
      roles: {
        for (final code in ((json['roles'] as List?) ?? const []).cast<String>())
          if (AppRole.fromCode(code) != null) AppRole.fromCode(code)!,
      },
      departments: {
        for (final code in ((json['departments'] as List?) ?? const []).cast<String>())
          Department.fromCode(code),
      },
    );
  }
}

/// Administrator actions for people and access. Every call is checked again by the database.
class PeopleRepository {
  PeopleRepository(this._client);

  final SupabaseClient _client;

  Future<List<PersonAccess>> list(String venueId) async {
    final rows = await _client.rpc<List<dynamic>>('list_venue_people', params: {'p_venue': venueId});
    return rows.cast<Map<String, dynamic>>().map(PersonAccess.fromJson).toList();
  }

  Future<void> addByEmail(String venueId, String email) async {
    await _client.rpc<String>('add_venue_member', params: {'p_venue': venueId, 'p_email': email});
  }

  Future<void> setActive(String venueId, String userId, bool active) async {
    await _client.rpc<void>('set_membership_status', params: {
      'p_venue': venueId,
      'p_user': userId,
      'p_active': active,
    });
  }

  Future<void> setRole(String venueId, String userId, AppRole role, bool on) async {
    await _client.rpc<void>('set_person_role', params: {
      'p_venue': venueId,
      'p_user': userId,
      'p_role': role.code,
      'p_on': on,
    });
  }

  Future<void> setDepartment(String venueId, String userId, Department dept, bool on) async {
    await _client.rpc<void>('set_person_department', params: {
      'p_venue': venueId,
      'p_user': userId,
      'p_department': dept.code,
      'p_on': on,
    });
  }
}

final peopleRepositoryProvider = Provider<PeopleRepository>((ref) {
  return PeopleRepository(Supabase.instance.client);
});

final peopleProvider = FutureProvider.family<List<PersonAccess>, String>((ref, venueId) {
  return ref.watch(peopleRepositoryProvider).list(venueId);
});
