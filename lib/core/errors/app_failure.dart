import 'failure_kind.dart';

/// An error whose message is safe to show to the user.
class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Converts any thrown object into a user-safe message. Database rule and conflict messages
/// pass through [friendlyMessage] so people can tell what to fix.
String userMessageFor(Object error) {
  if (error is AppFailure) return error.message;
  return friendlyMessage(error);
}
