import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/chat.dart';

/// Chat reads go through row-level security. Every change goes through a database function,
/// which checks that the caller is still an active member of the venue.
class ChatRepository {
  ChatRepository(this._client);

  final SupabaseClient _client;

  Future<List<ChatConversation>> conversations(String venueId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'chat_list',
      params: {'p_venue': venueId},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(ChatConversation.fromJson)
        .toList();
  }

  Future<List<ChatMessage>> messages(String conversationId) async {
    final rows = await _client
        .from('chat_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(200);
    // Newest first from the server, shown oldest first in the thread.
    return rows
        .cast<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList()
        .reversed
        .toList();
  }

  Future<List<ChatParticipant>> participants(String conversationId) async {
    final rows = await _client
        .from('chat_participants')
        .select('user_id, role, last_delivered_at, last_read_at')
        .eq('conversation_id', conversationId);
    return rows
        .cast<Map<String, dynamic>>()
        .map(ChatParticipant.fromJson)
        .toList();
  }

  /// Display names for everyone in the conversation, in one call.
  Future<Map<String, String>> memberNames(String conversationId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'chat_member_names',
      params: {'p_conversation': conversationId},
    );
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        row['user_id'] as String: (row['name'] as String?) ?? 'Team member',
    };
  }

  Future<String> openDirect(String venueId, String otherUserId) async {
    final id = await _client.rpc<String>(
      'chat_open_direct',
      params: {'p_venue': venueId, 'p_other': otherUserId},
    );
    return id;
  }

  Future<String> createGroup(
    String venueId,
    String title,
    List<String> members,
  ) async {
    final id = await _client.rpc<String>(
      'chat_create_group',
      params: {'p_venue': venueId, 'p_title': title, 'p_members': members},
    );
    return id;
  }

  Future<void> addMembers(String conversationId, List<String> members) async {
    await _client.rpc<void>(
      'chat_add_members',
      params: {'p_conversation': conversationId, 'p_members': members},
    );
  }

  Future<void> send(String conversationId, String body) async {
    final text = body.trim();
    if (text.isEmpty) throw const AppFailure('Type a message first.');
    await _client.rpc<Map<String, dynamic>>(
      'chat_send',
      params: {'p_conversation': conversationId, 'p_body': text},
    );
  }

  Future<void> markDelivered(String conversationId) async {
    await _client.rpc<void>(
      'chat_mark_delivered',
      params: {'p_conversation': conversationId},
    );
  }

  Future<void> markRead(String conversationId) async {
    await _client.rpc<void>(
      'chat_mark_read',
      params: {'p_conversation': conversationId},
    );
  }
}
