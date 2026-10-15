/// Where a tapped alert should open. Every alert the database creates has a screen to open;
/// an alert with no known destination opens the Communications inbox.
String pushRouteFor({
  required String? kind,
  String? conversationId,
  String? eventId,
}) {
  switch (kind) {
    case 'chat':
      if (conversationId != null && conversationId.isNotEmpty) {
        return '/chat/$conversationId';
      }
      return '/chat';
    case 'assignment':
      return '/my-shift';
    case 'beo_revision':
      if (eventId != null && eventId.isNotEmpty) return '/beo/event/$eventId';
      return '/communications';
    case 'announcement':
    default:
      return '/communications';
  }
}
