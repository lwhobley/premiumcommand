import 'package:cutx_premium_command/core/push/push_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat alerts open their conversation', () {
    expect(pushRouteFor(kind: 'chat', conversationId: 'c1'), '/chat/c1');
    expect(pushRouteFor(kind: 'chat'), '/chat');
  });

  test('assignment alerts open My Shift', () {
    expect(pushRouteFor(kind: 'assignment', eventId: 'e1'), '/my-shift');
  });

  test(
    'BEO revision alerts open that event BEO, or the inbox without an event',
    () {
      expect(
        pushRouteFor(kind: 'beo_revision', eventId: 'e1'),
        '/beo/event/e1',
      );
      expect(pushRouteFor(kind: 'beo_revision'), '/communications');
    },
  );

  test('announcements and unknown alerts open the Communications inbox', () {
    expect(
      pushRouteFor(kind: 'announcement', eventId: 'e1'),
      '/communications',
    );
    expect(pushRouteFor(kind: 'something_new'), '/communications');
    expect(pushRouteFor(kind: null), '/communications');
  });
}
