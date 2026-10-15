import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/text/initials.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../application/chat_providers.dart';
import '../domain/chat.dart';
import 'chat_thread.dart';

/// Staff chat. Conversations on the left, the open thread on the right on wide screens.
/// On phones, the list opens each conversation on its own screen.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const _wideBreakpoint = 880.0;
  String? _selected;

  @override
  Widget build(BuildContext context) {
    if (!backendAvailable) return const BackendRequired(title: 'Chat');
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    // Starts live message and presence updates for as long as the chat is on screen.
    ref.watch(chatRealtimeProvider(session.venueId));
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startChat(session.venueId, session.userId),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New chat'),
      ),
      body: wide
          ? Row(
              children: [
                SizedBox(
                  width: 340,
                  child: _ConversationList(
                    venueId: session.venueId,
                    myUserId: session.userId,
                    selectedId: _selected,
                    onOpen: (id) => setState(() => _selected = id),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _selected == null
                      ? const Center(
                          child: Text(
                            'Choose a conversation to start reading.',
                            style: TextStyle(color: AppColors.charcoalMuted),
                          ),
                        )
                      : ChatThreadView(
                          key: ValueKey(_selected),
                          conversationId: _selected!,
                        ),
                ),
              ],
            )
          : _ConversationList(
              venueId: session.venueId,
              myUserId: session.userId,
              selectedId: null,
              onOpen: (id) => context.push('/chat/$id'),
            ),
    );
  }

  Future<void> _startChat(String venueId, String myUserId) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Message a person'),
              onTap: () => Navigator.of(context).pop('direct'),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('New group'),
              onTap: () => Navigator.of(context).pop('group'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final people = [
        for (final m in await ref.read(venueMembersProvider(venueId).future))
          if (m.id != myUserId) m,
      ];
      if (!mounted) return;
      if (people.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No one else is at this venue yet.')),
        );
        return;
      }
      final repo = ref.read(chatRepositoryProvider);
      String? id;
      if (choice == 'direct') {
        final other = await showDialog<({String id, String name})>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Message'),
            children: [
              for (final p in people)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(p),
                  child: Text(p.name),
                ),
            ],
          ),
        );
        if (other == null) return;
        id = await repo.openDirect(venueId, other.id);
      } else {
        final members = await pickMembers(context, 'Group members', people);
        if (members == null || members.isEmpty || !mounted) return;
        final title = await _askGroupName();
        if (title == null || !mounted) return;
        id = await repo.createGroup(venueId, title, members);
      }
      ref.invalidate(chatListProvider(venueId));
      if (!mounted) return;
      _openConversation(id);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    }
  }

  void _openConversation(String id) {
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    if (wide) {
      setState(() => _selected = id);
    } else {
      context.push('/chat/$id');
    }
  }

  Future<String?> _askGroupName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name the group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.of(context).pop(name);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}

class _ConversationList extends ConsumerWidget {
  const _ConversationList({
    required this.venueId,
    required this.myUserId,
    required this.selectedId,
    required this.onOpen,
  });

  final String venueId;
  final String myUserId;
  final String? selectedId;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(chatListProvider(venueId));
    final online = ref.watch(onlineUsersProvider);

    return conversations.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(userMessageFor(error), textAlign: TextAlign.center),
              TextButton(
                onPressed: () => ref.invalidate(chatListProvider(venueId)),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No conversations yet. Use New chat to message someone or start a group.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.charcoalMuted),
              ),
            ),
          );
        }
        final now = DateTime.now();
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) {
            final c = items[index];
            final isOnline =
                !c.isGroup &&
                c.otherUserId != null &&
                online.contains(c.otherUserId);
            final preview = chatPreview(
              body: c.lastBody,
              senderName: c.lastSenderName,
              myUserId: myUserId,
              senderId: c.lastSenderId,
              isGroup: c.isGroup,
            );
            return ListTile(
              selected: c.id == selectedId,
              selectedTileColor: AppColors.brassSoft,
              leading: Stack(
                children: [
                  CircleAvatar(child: Text(initialsFor(c.title))),
                  if (isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.ready,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: c.unreadCount > 0
                      ? FontWeight.w700
                      : FontWeight.w600,
                ),
              ),
              subtitle: Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.unreadCount > 0
                      ? AppColors.charcoal
                      : AppColors.charcoalMuted,
                  fontWeight: c.unreadCount > 0
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.lastMessageAt != null)
                    Text(
                      chatTimeLabel(c.lastMessageAt!, now),
                      style: TextStyle(
                        fontSize: 12,
                        color: c.unreadCount > 0
                            ? AppColors.ready
                            : AppColors.charcoalMuted,
                      ),
                    ),
                  if (c.unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: AppColors.ready,
                      child: Text(
                        c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () => onOpen(c.id),
            );
          },
        );
      },
    );
  }
}

/// Shows a conversation on its own screen when the list is opened on a phone.
class ChatThreadScreen extends ConsumerWidget {
  const ChatThreadScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    ref.watch(chatRealtimeProvider(session.venueId));
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: ChatThreadView(conversationId: conversationId),
    );
  }
}
