import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/text/initials.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startChat(session.venueId, session.userId),
        icon: const PhosphorIcon(PhosphorIconsDuotone.pencilSimple),
        label: const Text('New chat'),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(kicker: 'Team', title: 'Chat'),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                        const SizedBox(width: AppSpace.s),
                        Expanded(
                          child: _selected == null
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: AppSpace.screen,
                                  ),
                                  child: EmptyNote(
                                    'Choose a conversation to start reading.',
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
            ),
          ],
        ),
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
              leading: const PhosphorIcon(PhosphorIconsDuotone.user),
              title: const Text('Message a person'),
              onTap: () => Navigator.of(context).pop('direct'),
            ),
            ListTile(
              leading: const PhosphorIcon(PhosphorIconsDuotone.usersThree),
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
      loading: () => const Align(
        alignment: Alignment.topCenter,
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(userMessageFor(error), style: AppText.body),
            const SizedBox(height: AppSpace.xs),
            TextButton(
              onPressed: () => ref.invalidate(chatListProvider(venueId)),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.screen),
            child: EmptyNote(
              'No conversations yet. Use New chat to message someone or start a group.',
            ),
          );
        }
        final now = DateTime.now();
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: items.length,
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
              selectedTileColor: AppColors.accent100,
              selectedColor: AppColors.text,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpace.screen,
                vertical: 4,
              ),
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
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.background,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowTitle.copyWith(fontSize: 17),
              ),
              subtitle: Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.meta.copyWith(
                  color: c.unreadCount > 0 ? AppColors.text : AppColors.muted,
                  fontWeight: c.unreadCount > 0
                      ? FontWeight.w600
                      : FontWeight.w400,
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
                        fontSize: 11,
                        color: c.unreadCount > 0
                            ? AppColors.accent700
                            : AppColors.muted,
                      ),
                    ),
                  if (c.unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: AppRadius.all,
                      ),
                      child: Text(
                        c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                        maxLines: 1,
                        softWrap: false,
                        style: AppText.tag.copyWith(
                          color: AppColors.background,
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
      body: SafeArea(
        bottom: false,
        child: ChatThreadView(
          conversationId: conversationId,
          back: const BackLink(),
        ),
      ),
    );
  }
}
