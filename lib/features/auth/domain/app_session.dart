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

  /// Stored so the app can restore the last session when it starts without a connection.
  /// Access is still enforced by the database on every call.
  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'display_name': displayName,
        'venue_id': venueId,
        'venue_name': venueName,
        'time_zone': timeZone,
        'roles': [for (final r in roles) r.code],
        'departments': [for (final d in departments) d.code],
      };

  factory AppSession.fromJson(Map<String, dynamic> json) {
    return AppSession(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      venueId: json['venue_id'] as String,
      venueName: json['venue_name'] as String,
      timeZone: json['time_zone'] as String,
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
