import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/session_controller.dart';
import '../data/chat_repository.dart';
import '../domain/chat.dart';
import 'chat_realtime.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  ref.watch(sessionProvider);
  return ChatRepository(Supabase.instance.client);
});

final chatListProvider = FutureProvider.family<List<ChatConversation>, String>((
  ref,
  venueId,
) {
  ref.watch(sessionProvider);
  return ref.watch(chatRepositoryProvider).conversations(venueId);
});

final chatMessagesProvider = FutureProvider.family<List<ChatMessage>, String>((
  ref,
  conversationId,
) {
  return ref.watch(chatRepositoryProvider).messages(conversationId);
});

final chatParticipantsProvider =
    FutureProvider.family<List<ChatParticipant>, String>((ref, conversationId) {
      return ref.watch(chatRepositoryProvider).participants(conversationId);
    });

/// Display names for everyone in a conversation, keyed by user id. Fetched in one call and not
/// refreshed by read receipts; adding people refreshes it.
final chatNamesProvider = FutureProvider.family<Map<String, String>, String>((
  ref,
  conversationId,
) {
  return ref.watch(chatRepositoryProvider).memberNames(conversationId);
});

/// The conversation the person is looking at, so new messages there count as read.
class OpenChatController extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String? conversationId) => state = conversationId;

  /// Clears the open conversation only if it is still [conversationId]. On wide screens the next
  /// thread opens before the previous one is disposed, and must not be cleared by it.
  void close(String conversationId) {
    if (state == conversationId) state = null;
  }
}

final openChatProvider = NotifierProvider<OpenChatController, String?>(
  OpenChatController.new,
);

class OnlineUsersController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void replace(Set<String> ids) => state = ids;
}

final onlineUsersProvider =
    NotifierProvider<OnlineUsersController, Set<String>>(
      OnlineUsersController.new,
    );

/// Starts live updates for the venue while the chat is on screen. Disposed when it leaves.
final chatRealtimeProvider = Provider.autoDispose.family<ChatRealtime, String>((
  ref,
  venueId,
) {
  final myUserId = ref.watch(sessionProvider)?.userId ?? '';
  final repo = ref.watch(chatRepositoryProvider);

  final realtime = ChatRealtime(
    client: Supabase.instance.client,
    venueId: venueId,
    myUserId: myUserId,
    onMessage: (conversationId, senderId) {
      ref.invalidate(chatListProvider(venueId));
      ref.invalidate(chatMessagesProvider(conversationId));
      if (senderId == myUserId) return;
      // Opened conversations are read at once; others only count as delivered.
      if (ref.read(openChatProvider) == conversationId) {
        // Refresh the list after the read lands, so the unread badge clears.
        unawaited(
          repo
              .markRead(conversationId)
              .then((_) => ref.invalidate(chatListProvider(venueId)))
              .catchError((_) {}),
        );
      } else {
        unawaited(repo.markDelivered(conversationId).catchError((_) {}));
      }
    },
    // Receipts only change the ticks in the open thread. The list does not show them.
    onReceipt: (conversationId) {
      if (ref.read(openChatProvider) == conversationId) {
        ref.invalidate(chatParticipantsProvider(conversationId));
      }
    },
    onPresence: (ids) => ref.read(onlineUsersProvider.notifier).replace(ids),
  )..start();

  ref.onDispose(realtime.dispose);
  return realtime;
});
