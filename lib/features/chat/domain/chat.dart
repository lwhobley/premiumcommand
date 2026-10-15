import 'package:intl/intl.dart';

/// A conversation as shown in the list, with its latest message and unread count.
class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.isGroup,
    required this.title,
    required this.memberCount,
    required this.unreadCount,
    this.otherUserId,
    this.lastMessageAt,
    this.lastBody,
    this.lastSenderId,
    this.lastSenderName,
  });

  final String id;
  final bool isGroup;
  final String title;
  final String? otherUserId;
  final int memberCount;
  final int unreadCount;
  final DateTime? lastMessageAt;
  final String? lastBody;
  final String? lastSenderId;
  final String? lastSenderName;

  factory ChatConversation.fromJson(Map<String, dynamic> json) =>
      ChatConversation(
        id: json['conversation_id'] as String,
        isGroup: json['kind'] == 'group',
        title: (json['title'] as String?)?.trim().isNotEmpty == true
            ? (json['title'] as String).trim()
            : 'Conversation',
        otherUserId: json['other_user_id'] as String?,
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        lastMessageAt: json['last_message_at'] == null
            ? null
            : DateTime.parse(json['last_message_at'] as String).toLocal(),
        lastBody: json['last_body'] as String?,
        lastSenderId: json['last_sender_id'] as String?,
        lastSenderName: json['last_sender_name'] as String?,
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    conversationId: json['conversation_id'] as String,
    senderId: json['sender_id'] as String,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
}

/// A member's receipt positions, used to work out how far a sent message has travelled.
class ChatParticipant {
  const ChatParticipant({
    required this.userId,
    required this.isAdmin,
    this.lastDeliveredAt,
    this.lastReadAt,
  });

  final String userId;
  final bool isAdmin;
  final DateTime? lastDeliveredAt;
  final DateTime? lastReadAt;

  factory ChatParticipant.fromJson(Map<String, dynamic> json) =>
      ChatParticipant(
        userId: json['user_id'] as String,
        isAdmin: json['role'] == 'admin',
        lastDeliveredAt: json['last_delivered_at'] == null
            ? null
            : DateTime.parse(json['last_delivered_at'] as String).toLocal(),
        lastReadAt: json['last_read_at'] == null
            ? null
            : DateTime.parse(json['last_read_at'] as String).toLocal(),
      );
}

/// Sent: the server has it. Delivered: every other member's app has received it.
/// Read: every other member has opened the conversation since it was sent.
enum ReceiptState { sent, delivered, read }

/// Receipt for one of the signed-in person's messages, given the other members' positions.
ReceiptState receiptFor(
  ChatMessage message,
  String myUserId,
  List<ChatParticipant> participants,
) {
  final others = [
    for (final p in participants)
      if (p.userId != myUserId) p,
  ];
  if (others.isEmpty) return ReceiptState.sent;
  bool reached(DateTime? at) => at != null && !at.isBefore(message.createdAt);
  if (others.every((p) => reached(p.lastReadAt))) return ReceiptState.read;
  if (others.every(
    (p) => reached(p.lastDeliveredAt) || reached(p.lastReadAt),
  )) {
    return ReceiptState.delivered;
  }
  return ReceiptState.sent;
}

/// The preview line under a conversation title.
String chatPreview({
  required String? body,
  required String? senderName,
  required String myUserId,
  required String? senderId,
  required bool isGroup,
}) {
  if (body == null || body.isEmpty) return 'No messages yet';
  final mine = senderId == myUserId;
  if (mine) return 'You: $body';
  if (isGroup && senderName != null && senderName.isNotEmpty) {
    return '$senderName: $body';
  }
  return body;
}

/// Short time for the list: a clock time today, "Yesterday", or a date.
String chatTimeLabel(DateTime when, DateTime now) {
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return DateFormat.jm().format(when);
  if (difference == 1) return 'Yesterday';
  return DateFormat.MMMd().format(when);
}
