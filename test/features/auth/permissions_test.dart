import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/auth/domain/app_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('director holds every permission', () {
    expect(permissionsFor({AppRole.director}), AppPermission.values.toSet());
  });

  test('runner can update requests but cannot manage events', () {
    final perms = permissionsFor({AppRole.runner});
    expect(perms.contains(AppPermission.manageRequests), isTrue);
    expect(perms.contains(AppPermission.manageEvents), isFalse);
    expect(perms.contains(AppPermission.approveBeo), isFalse);
  });

  test('users with multiple roles get the union of permissions', () {
    final perms = permissionsFor({AppRole.culinaryLead, AppRole.banquetCaptain});
    expect(perms.contains(AppPermission.viewCulinary), isTrue);
    expect(perms.contains(AppPermission.manageBanquets), isTrue);
    expect(perms.contains(AppPermission.manageEvents), isFalse);
  });

  test('role codes round-trip and unknown codes are rejected', () {
    for (final role in AppRole.values) {
      expect(AppRole.fromCode(role.code), role);
    }
    expect(AppRole.fromCode('ticket_scanner'), isNull);
  });

  test('session permissions derive from its roles', () {
    const session = AppSession(
      userId: 'u',
      displayName: 'Test',
      venueId: 'v',
      venueName: 'V',
      timeZone: 'UTC',
      roles: {AppRole.suiteAttendant},
    );
    expect(session.can(AppPermission.runInspections), isTrue);
    expect(session.can(AppPermission.closeOutEvents), isFalse);
  });
}
