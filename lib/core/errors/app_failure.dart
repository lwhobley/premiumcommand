/// An error whose message is safe to show to the user.
class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Converts any thrown object into a user-safe message.
String userMessageFor(Object error) {
  if (error is AppFailure) return error.message;
  return 'Something went wrong. Please try again.';
}
