import '../../../core/permissions/app_permission.dart';
import '../../events/domain/readiness.dart';

/// The signed-in user's access at one venue.
class AppSession {
  const AppSession({
    required this.userId,
    required this.displayName,
    required this.venueId,
    required this.venueName,
    required this.timeZone,
    required this.roles,
    this.departments = const {},
  });

  final String userId;
  final String displayName;
  final String venueId;
  final String venueName;
  final String timeZone;
  final Set<AppRole> roles;

  /// Departments this person works in. Used to decide who may work department-level requests.
  final Set<Department> departments;

  Set<AppPermission> get permissions => permissionsFor(roles);

  bool can(AppPermission permission) => permissions.contains(permission);
}
