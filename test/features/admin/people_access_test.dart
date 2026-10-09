import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/admin/data/people_repository.dart';
import 'package:cutx_premium_command/features/events/domain/readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a database row to a person with roles and departments', () {
    final person = PersonAccess.fromJson({
      'user_id': 'u1',
      'display_name': 'Ana Ruiz',
      'email': 'ana@example.invalid',
      'membership_status': 'active',
      'roles': ['premium_manager', 'runner'],
      'departments': ['operations', 'banquets'],
    });
    expect(person.name, 'Ana Ruiz');
    expect(person.active, isTrue);
    expect(person.roles, {AppRole.premiumManager, AppRole.runner});
    expect(person.departments, {Department.operations, Department.banquets});
  });

  test('a suspended person is inactive and unknown role codes are dropped', () {
    final person = PersonAccess.fromJson({
      'user_id': 'u2',
      'display_name': null,
      'email': 'x@example.invalid',
      'membership_status': 'suspended',
      'roles': ['not_a_role', 'director'],
      'departments': <String>[],
    });
    expect(person.active, isFalse);
    expect(person.roles, {AppRole.director});
    expect(person.name, '');
  });
}
