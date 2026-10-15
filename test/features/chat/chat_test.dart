import 'package:cutx_premium_command/features/chat/domain/chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sent = DateTime(2026, 10, 15, 18, 0);
  final message = ChatMessage(
    id: 'm1',
    conversationId: 'c1',
    senderId: 'me',
    body: 'Gate 3 is open',
    createdAt: sent,
  );

  ChatParticipant person(String id, {DateTime? delivered, DateTime? read}) =>
      ChatParticipant(
        userId: id,
        isAdmin: false,
        lastDeliveredAt: delivered,
        lastReadAt: read,
      );

  group('receipts', () {
    test('a message with nobody else in the conversation is only sent', () {
      expect(receiptFor(message, 'me', [person('me')]), ReceiptState.sent);
    });

    test('delivered once every other member has received it', () {
      final participants = [
        person('me'),
        person('a', delivered: sent.add(const Duration(seconds: 1))),
        person('b', delivered: sent.add(const Duration(seconds: 2))),
      ];
      expect(receiptFor(message, 'me', participants), ReceiptState.delivered);
    });

    test('still only sent while one member has not received it', () {
      final participants = [
        person('me'),
        person('a', delivered: sent.add(const Duration(seconds: 1))),
        person('b', delivered: sent.subtract(const Duration(minutes: 5))),
      ];
      expect(receiptFor(message, 'me', participants), ReceiptState.sent);
    });

    test('read once every other member has opened the conversation after it was sent', () {
      final participants = [
        person('me'),
        person('a', read: sent.add(const Duration(minutes: 1))),
        person('b', read: sent.add(const Duration(minutes: 2))),
      ];
      expect(receiptFor(message, 'me', participants), ReceiptState.read);
    });

    test(
      'a read implies delivered even if the delivered position is older',
      () {
        final participants = [
          person('me'),
          person('a', read: sent.add(const Duration(minutes: 1))),
        ];
        expect(receiptFor(message, 'me', participants), ReceiptState.read);
      },
    );

    test('a read from before the message does not count', () {
      final participants = [
        person('me'),
        person('a', read: sent.subtract(const Duration(minutes: 1))),
      ];
      expect(receiptFor(message, 'me', participants), ReceiptState.sent);
    });
  });

  group('previews', () {
    test('mine say You, group messages name the sender, direct messages show the text', () {
      expect(
        chatPreview(
          body: 'Hi',
          senderName: 'Ana',
          myUserId: 'me',
          senderId: 'me',
          isGroup: true,
        ),
        'You: Hi',
      );
      expect(
        chatPreview(
          body: 'Hi',
          senderName: 'Ana',
          myUserId: 'me',
          senderId: 'a',
          isGroup: true,
        ),
        'Ana: Hi',
      );
      expect(
        chatPreview(
          body: 'Hi',
          senderName: 'Ana',
          myUserId: 'me',
          senderId: 'a',
          isGroup: false,
        ),
        'Hi',
      );
    });

    test('an empty conversation says so', () {
      expect(
        chatPreview(
          body: null,
          senderName: null,
          myUserId: 'me',
          senderId: null,
          isGroup: false,
        ),
        'No messages yet',
      );
    });
  });

  group('time labels', () {
    final now = DateTime(2026, 10, 15, 12, 0);

    test(
      'today shows a clock time, yesterday says so, and older days show a date',
      () {
        expect(
          chatTimeLabel(DateTime(2026, 10, 15, 9, 30), now),
          isNot(contains('Yesterday')),
        );
        expect(chatTimeLabel(DateTime(2026, 10, 14, 23, 0), now), 'Yesterday');
        expect(chatTimeLabel(DateTime(2026, 10, 1, 8, 0), now), 'Oct 1');
      },
    );
  });

  test('conversation rows parse, including a group title', () {
    final c = ChatConversation.fromJson({
      'conversation_id': 'c1',
      'kind': 'group',
      'title': '  Suite crew ',
      'other_user_id': null,
      'member_count': 3,
      'unread_count': 2,
      'last_message_at': '2026-10-15T18:00:00Z',
      'last_body': 'Briefing at 6',
      'last_sender_id': 'a',
      'last_sender_name': 'Ana',
    });
    expect(c.isGroup, isTrue);
    expect(c.title, 'Suite crew');
    expect(c.unreadCount, 2);
    expect(c.lastSenderId, 'a');
  });
}
