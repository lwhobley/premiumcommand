import '../../../core/permissions/app_permission.dart';

/// The signed-in user's access at one venue.
class AppSession {
  const AppSession({
    required this.userId,
    required this.displayName,
    required this.venueId,
    required this.venueName,
    required this.timeZone,
    required this.roles,
  });

  final String userId;
  final String displayName;
  final String venueId;
  final String venueName;
  final String timeZone;
  final Set<AppRole> roles;

  Set<AppPermission> get permissions => permissionsFor(roles);

  bool can(AppPermission permission) => permissions.contains(permission);
}
