import 'dart:async';

import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/auth/application/session_controller.dart';
import 'package:cutx_premium_command/features/chat/application/chat_providers.dart';
import 'package:cutx_premium_command/features/chat/data/chat_repository.dart';
import 'package:cutx_premium_command/features/chat/domain/chat.dart';
import 'package:cutx_premium_command/features/chat/presentation/chat_thread.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeChat extends ChatRepository {
  FakeChat()
    : super(
        SupabaseClient(
          'https://example.com',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final pending = Completer<void>();
  ChatMessage? cursor;
  ChatMessage message(String id) => ChatMessage(
    id: id,
    conversationId: 'c',
    senderId: 'other',
    body: id,
    createdAt: DateTime.utc(2026, 10, 16),
  );
  @override
  Future<List<ChatMessage>> messages(String id, {ChatMessage? before}) async {
    cursor = before;
    return [message(before == null ? 'new' : 'old')];
  }

  @override
  Future<List<ChatConversation>> conversations(String id) async => [];
  @override
  Future<List<ChatParticipant>> participants(String id) async => [];
  @override
  Future<Map<String, String>> memberNames(String id) async => {};
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> send(String id, String body) => pending.future;
}

void main() {
  Future<ProviderContainer> showThread(
    WidgetTester tester,
    FakeChat repo,
  ) async {
    final container = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(repo)],
    );
    container.read(sessionProvider.notifier).signInAsDemo(AppRole.director);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ChatThreadView(conversationId: 'c')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('earlier messages use cursor and survive latest refresh', (
    tester,
  ) async {
    final repo = FakeChat();
    final container = await showThread(tester, repo);
    await tester.tap(find.text('Load earlier messages'));
    await tester.pumpAndSettle();
    expect(repo.cursor?.id, 'new');
    expect(find.text('old'), findsOneWidget);
    container.invalidate(chatMessagesProvider('c'));
    await tester.pumpAndSettle();
    expect(find.text('old'), findsOneWidget);
    expect(find.text('new'), findsOneWidget);
    expect(find.text('Load earlier messages'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  for (final fails in [false, true]) {
    testWidgets('leaving thread during send is safe (failure=$fails)', (
      tester,
    ) async {
      final repo = FakeChat();
      final container = await showThread(tester, repo);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      if (fails) {
        repo.pending.completeError(Exception('offline'));
      } else {
        repo.pending.complete();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      container.dispose();
    });
  }
}
