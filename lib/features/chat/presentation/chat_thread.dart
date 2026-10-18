import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/text/initials.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/application/planning_providers.dart';
import '../application/chat_providers.dart';
import '../domain/chat.dart';
import '../data/chat_repository.dart';

/// Emoji offered in the message box. Plain text, so it works the same on every platform.
const chatEmoji = [
  '😀', '😃', '😄', '😁', '😂', '🤣', '😊', '😍', '😘', '😎', //
  '🤔', '🙂', '😉', '😅', '😢', '😡', '👍', '👎', '👏', '🙏', //
  '💪', '🎉', '🔥', '✅', '⚠️', '❤️', '🥂', '🍾', '🍰', '☕', //
];

/// One conversation: messages, receipts, and the message box. Full width on phones, beside the
/// list on wide screens.
class ChatThreadView extends ConsumerStatefulWidget {
  const ChatThreadView({super.key, required this.conversationId, this.back});

  final String conversationId;

  /// On its own screen, the thread opens with a back link and the full screen header.
  /// Without one (beside the list), it shows a compact header.
  final BackLink? back;

  @override
  ConsumerState<ChatThreadView> createState() => _ChatThreadViewState();
}

class _ChatThreadViewState extends ConsumerState<ChatThreadView> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _showEmoji = false;
  bool _sending = false;
  bool _loadingOlder = false;
  bool _hasOlder = true;
  String? _historyError;
  List<ChatMessage> _history = [];

  List<ChatMessage> _merge(List<ChatMessage> incoming) {
    final byId = {
      for (final m in [..._history, ...incoming]) m.id: m,
    };
    return byId.values.toList()..sort((a, b) {
      final time = a.createdAt.compareTo(b.createdAt);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
  }

  Future<void> _loadOlder(List<ChatMessage> current) async {
    if (_loadingOlder || !_hasOlder || current.isEmpty) return;
    final id = widget.conversationId;
    setState(() {
      _loadingOlder = true;
      _historyError = null;
    });
    try {
      final page = await ref
          .read(chatRepositoryProvider)
          .messages(id, before: current.first);
      if (!mounted || widget.conversationId != id) return;
      setState(() {
        _history = _merge([...current, ...page]);
        _hasOlder = page.length == ChatRepository.pageSize;
      });
    } catch (error) {
      if (mounted && widget.conversationId == id) {
        setState(() => _historyError = userMessageFor(error));
      }
    } finally {
      if (mounted && widget.conversationId == id) {
        setState(() => _loadingOlder = false);
      }
    }
  }

  late final OpenChatController _open = ref.read(openChatProvider.notifier);

  @override
  void initState() {
    super.initState();
    _markOpened();
  }

  @override
  void didUpdateWidget(covariant ChatThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _history = [];
      _hasOlder = true;
      _loadingOlder = false;
      _historyError = null;
      _sending = false;
      _input.clear();
      _markOpened();
    }
  }

  /// Opening a conversation reads it. Messages that arrive while it is open are read too.
  void _markOpened() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _open.open(widget.conversationId);
      ref
          .read(chatRepositoryProvider)
          .markRead(widget.conversationId)
          .then((_) {
            if (!mounted) return;
            ref.invalidate(
              chatListProvider(ref.read(sessionProvider)?.venueId ?? ''),
            );
          })
          .catchError((_) {});
    });
  }

  @override
  void dispose() {
    _open.close(widget.conversationId);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final venueId = ref.read(sessionProvider)?.venueId ?? '';
    final id = widget.conversationId;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(chatRepositoryProvider).send(id, text);
      if (!mounted || widget.conversationId != id) return;
      if (_input.text.trim() == text) _input.clear();
      ref.invalidate(chatMessagesProvider(widget.conversationId));
      ref.invalidate(chatListProvider(venueId));
    } catch (error) {
      if (!mounted || widget.conversationId != id) return;
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    } finally {
      if (mounted && widget.conversationId == id) {
        setState(() => _sending = false);
      }
    }
  }

  void _insertEmoji(String emoji) {
    final value = _input.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;
    _input.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final conversation = ref
        .watch(chatListProvider(session.venueId))
        .value
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;
    ref.listen(chatMessagesProvider(widget.conversationId), (previous, next) {
      if (previous?.hasValue == true) _history = _merge(previous!.value!);
      if (next.hasValue) _history = _merge(next.value!);
    });
    final messages = ref.watch(chatMessagesProvider(widget.conversationId));
    final participants =
        ref.watch(chatParticipantsProvider(widget.conversationId)).value ??
        const [];
    final names =
        ref.watch(chatNamesProvider(widget.conversationId)).value ?? const {};
    final online = ref.watch(onlineUsersProvider);
    final isGroup = conversation?.isGroup ?? false;
    final otherId = conversation?.otherUserId;
    final isOnline = otherId != null && online.contains(otherId);
    final title = conversation?.title ?? 'Conversation';

    final presence = isGroup
        ? '${conversation?.memberCount ?? participants.length} members'
        : (isOnline ? 'Online' : 'Offline');
    final groupAdd = isGroup
        ? _GroupAddButton(
            conversationId: widget.conversationId,
            participants: participants,
            venueId: session.venueId,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.back != null)
          ScreenHeader(
            back: widget.back,
            kicker: 'Chat',
            title: title,
            subtitle: presence,
            actions: [?groupAdd],
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screen,
              AppSpace.s,
              AppSpace.screen - 10,
              AppSpace.s,
            ),
            child: Row(
              children: [
                CircleAvatar(child: Text(initialsFor(title))),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle,
                      ),
                      Text(
                        presence,
                        style: AppText.meta.copyWith(
                          color: isOnline && !isGroup
                              ? AppColors.accent700
                              : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                ?groupAdd,
              ],
            ),
          ),
        Expanded(
          child: ColoredBox(
            color: AppColors.background,
            child: messages.when(
              loading: () => const Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppSpace.screen),
                child: Text(userMessageFor(error), style: AppText.body),
              ),
              data: (latest) {
                final items = _merge(latest);
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpace.screen),
                    child: EmptyNote('No messages yet. Say hello.'),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.screen,
                    vertical: 10,
                  ),
                  itemCount: items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == items.length) {
                      if (!_hasOlder) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_historyError != null)
                              Text(
                                _historyError!,
                                style: const TextStyle(
                                  color: AppColors.accent2700,
                                ),
                              ),
                            TextButton(
                              onPressed: _loadingOlder
                                  ? null
                                  : () => _loadOlder(items),
                              child: Text(
                                _loadingOlder
                                    ? 'Loading earlier messages…'
                                    : 'Load earlier messages',
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    // The list is shown newest at the bottom, so index 0 is the newest message.
                    final position = items.length - 1 - index;
                    final message = items[position];
                    final startsDay =
                        position == 0 ||
                        !_sameDay(
                          items[position - 1].createdAt,
                          message.createdAt,
                        );
                    final mine = message.senderId == session.userId;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (startsDay) _DayChip(day: message.createdAt),
                        _Bubble(
                          message: message,
                          mine: mine,
                          showSender: isGroup && !mine,
                          senderName: names[message.senderId] ?? 'Team member',
                          receipt: mine
                              ? receiptFor(
                                  message,
                                  session.userId,
                                  participants,
                                )
                              : null,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
        if (_showEmoji)
          Container(
            height: 180,
            color: AppColors.surface,
            child: GridView.count(
              crossAxisCount: 10,
              padding: const EdgeInsets.all(8),
              children: [
                for (final emoji in chatEmoji)
                  InkWell(
                    onTap: () => _insertEmoji(emoji),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Container(
            color: AppColors.background,
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screen - 12,
              8,
              AppSpace.screen,
              8,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: _showEmoji ? 'Hide emoji' : 'Emoji',
                  icon: PhosphorIcon(
                    _showEmoji
                        ? PhosphorIconsDuotone.keyboard
                        : PhosphorIconsDuotone.smiley,
                  ),
                  onPressed: () => setState(() => _showEmoji = !_showEmoji),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      counterText: '',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    onTap: () {
                      if (_showEmoji) setState(() => _showEmoji = false);
                    },
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send',
                  // The theme gives icon buttons accent700 icons; on the accent fill the
                  // icon is paper-colored.
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? AppColors.ink(0.45)
                          : AppColors.background,
                    ),
                  ),
                  onPressed: _input.text.trim().isEmpty || _sending
                      ? null
                      : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.background,
                          ),
                        )
                      : const PhosphorIcon(
                          PhosphorIconsDuotone.paperPlaneRight,
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.showSender,
    required this.senderName,
    required this.receipt,
  });

  final ChatMessage message;
  final bool mine;
  final bool showSender;
  final String senderName;
  final ReceiptState? receipt;

  @override
  Widget build(BuildContext context) {
    final maxWidth = (MediaQuery.sizeOf(context).width * 0.75).clamp(
      200.0,
      520.0,
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? AppColors.accent200 : AppColors.surface,
            borderRadius: AppRadius.all,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSender)
                Text(
                  senderName,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 2),
                    child: Text(message.body, style: AppText.body),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat.jm().format(message.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                      if (receipt != null) ...[
                        const SizedBox(width: 3),
                        _Ticks(state: receipt!),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ticks extends StatelessWidget {
  const _Ticks({required this.state});

  final ReceiptState state;

  @override
  Widget build(BuildContext context) {
    final icon = state == ReceiptState.sent
        ? PhosphorIconsDuotone.check
        : PhosphorIconsDuotone.checks;
    final color = state == ReceiptState.read
        ? AppColors.accent700
        : AppColors.neutral600;
    final label = switch (state) {
      ReceiptState.sent => 'Sent',
      ReceiptState.delivered => 'Delivered',
      ReceiptState.read => 'Read',
    };
    return Tooltip(
      message: label,
      child: PhosphorIcon(icon, size: 15, color: color),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sameDay =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        day.year == yesterday.year &&
        day.month == yesterday.month &&
        day.day == yesterday.day;
    final text = sameDay
        ? 'Today'
        : isYesterday
        ? 'Yesterday'
        : DateFormat.yMMMd().format(day);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Kicker(text, color: AppColors.muted),
    );
  }
}

/// Group admins add people. Everyone else gets no control here.
class _GroupAddButton extends ConsumerWidget {
  const _GroupAddButton({
    required this.conversationId,
    required this.participants,
    required this.venueId,
  });

  final String conversationId;
  final List<ChatParticipant> participants;
  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionProvider)?.userId;
    final isAdmin = participants.any((p) => p.userId == me && p.isAdmin);
    if (!isAdmin) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Add people',
      icon: const PhosphorIcon(PhosphorIconsDuotone.userPlus),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final members = await ref.read(venueMembersProvider(venueId).future);
        if (!context.mounted) return;
        final already = {for (final p in participants) p.userId};
        final choices = [
          for (final m in members)
            if (!already.contains(m.id)) m,
        ];
        if (choices.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Everyone at the venue is already in this group.'),
            ),
          );
          return;
        }
        final picked = await pickMembers(context, 'Add people', choices);
        if (picked == null || picked.isEmpty) return;
        try {
          await ref
              .read(chatRepositoryProvider)
              .addMembers(conversationId, picked);
          ref.invalidate(chatParticipantsProvider(conversationId));
          ref.invalidate(chatNamesProvider(conversationId));
          ref.invalidate(chatListProvider(venueId));
        } catch (error) {
          messenger.showSnackBar(
            SnackBar(content: Text(userMessageFor(error))),
          );
        }
      },
    );
  }
}

/// Lets someone tick several people. Used to add to a group and to create one.
Future<List<String>?> pickMembers(
  BuildContext context,
  String title,
  List<({String id, String name})> people,
) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _MemberPickerDialog(title: title, people: people),
  );
}

class _MemberPickerDialog extends StatefulWidget {
  const _MemberPickerDialog({required this.title, required this.people});

  final String title;
  final List<({String id, String name})> people;

  @override
  State<_MemberPickerDialog> createState() => _MemberPickerDialogState();
}

class _MemberPickerDialogState extends State<_MemberPickerDialog> {
  final Set<String> _chosen = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final person in widget.people)
              CheckboxListTile(
                value: _chosen.contains(person.id),
                title: Text(person.name),
                onChanged: (on) => setState(() {
                  if (on == true) {
                    _chosen.add(person.id);
                  } else {
                    _chosen.remove(person.id);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.of(context).pop(_chosen.toList()),
          child: Text('Add ${_chosen.length}'),
        ),
      ],
    );
  }
}
