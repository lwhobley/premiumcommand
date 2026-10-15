import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Live updates for a venue's chat. New messages and read receipts arrive through Realtime,
/// which applies the same row-level rules as reads, so people only hear about their own chats.
/// Presence tracks who has the app open right now.
class ChatRealtime {
  ChatRealtime({
    required this.client,
    required this.venueId,
    required this.myUserId,
    required this.onMessage,
    required this.onReceipt,
    required this.onPresence,
  });

  final SupabaseClient client;
  final String venueId;
  final String myUserId;

  /// A message arrived: conversation id and sender id.
  final void Function(String conversationId, String senderId) onMessage;

  /// Someone's read or delivered position changed in this conversation.
  final void Function(String conversationId) onReceipt;

  /// The user ids currently online at this venue.
  final void Function(Set<String> onlineUserIds) onPresence;

  RealtimeChannel? _changes;
  RealtimeChannel? _presence;
  bool _disposed = false;

  // Receipts arrive in bursts (every member's app marks each message delivered). One refresh per
  // conversation per short pause is enough.
  final Map<String, Timer> _receiptTimers = {};

  void _receiptBurst(String conversationId) {
    _receiptTimers[conversationId]?.cancel();
    _receiptTimers[conversationId] = Timer(
      const Duration(milliseconds: 600),
      () {
        _receiptTimers.remove(conversationId);
        if (!_disposed) onReceipt(conversationId);
      },
    );
  }

  void start() {
    // Private channels: the database lets only active members of this venue join them.
    _changes =
        client.channel(
            'chat-changes-$venueId',
            opts: const RealtimeChannelConfig(private: true),
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'chat_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'venue_id',
              value: venueId,
            ),
            callback: (payload) {
              if (_disposed) return;
              onMessage(
                payload.newRecord['conversation_id'] as String,
                payload.newRecord['sender_id'] as String,
              );
            },
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'chat_participants',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'venue_id',
              value: venueId,
            ),
            callback: (payload) {
              if (_disposed) return;
              _receiptBurst(payload.newRecord['conversation_id'] as String);
            },
          )
          ..subscribe();

    _presence =
        client.channel(
            'chat-presence-$venueId',
            opts: RealtimeChannelConfig(key: myUserId, private: true),
          )
          ..onPresenceSync((_) {
            if (_disposed) return;
            onPresence(_onlineIds());
          })
          ..subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed &&
                myUserId.isNotEmpty) {
              _presence?.track({'user_id': myUserId});
            }
          });
  }

  Set<String> _onlineIds() {
    final states = _presence?.presenceState() ?? const <SinglePresenceState>[];
    return {for (final state in states) state.key};
  }

  void dispose() {
    _disposed = true;
    for (final timer in _receiptTimers.values) {
      timer.cancel();
    }
    _receiptTimers.clear();
    _changes?.unsubscribe();
    _presence?.unsubscribe();
  }
}
