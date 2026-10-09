import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../application/operations_providers.dart';

/// Event announcements, your notifications, and incident reporting.
class CommunicationsScreen extends ConsumerWidget {
  const CommunicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) return const BackendRequired(title: 'Communications');

    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final eventId = ref.watch(selectedEventIdProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Communications'),
          bottom: const TabBar(tabs: [Tab(text: 'Announcements'), Tab(text: 'Inbox')]),
        ),
        body: Column(
          children: [
            const EventPicker(),
            Expanded(
              child: TabBarView(
                children: [
                  _Announcements(
                    eventId: eventId,
                    canPost: permissions.contains(AppPermission.manageEvents),
                    venueId: session?.venueId ?? '',
                  ),
                  const _Inbox(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Announcements extends ConsumerWidget {
  const _Announcements({required this.eventId, required this.canPost, required this.venueId});

  final String? eventId;
  final bool canPost;
  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = eventId;
    if (id == null) return const SizedBox.shrink();
    final items = ref.watch(announcementsProvider(id));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              onPressed: () => _post(context, ref, id),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Announce'),
            )
          : null,
      body: Column(
        children: [
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('$error')),
              data: (list) {
                if (list.isEmpty) return const Center(child: Text('No announcements yet.'));
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    for (final a in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a['body'] as String),
                              const SizedBox(height: 6),
                              Text(
                                DateFormat('MMM d, h:mm a').format(DateTime.parse(a['created_at'] as String).toLocal()),
                                style: const TextStyle(color: AppColors.charcoalMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _post(BuildContext context, WidgetRef ref, String id) async {
    final body = await showDialog<String>(
      context: context,
      builder: (_) => const _AnnounceDialog(),
    );
    if (body == null || body.isEmpty || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(operationsRepositoryProvider).postAnnouncement(venueId: venueId, eventId: id, body: body);
      ref.invalidate(announcementsProvider(id));
    }, success: 'Announcement sent to rostered staff.');
  }
}

class _Inbox extends ConsumerWidget {
  const _Inbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: Text('Your notifications', style: Theme.of(context).textTheme.titleMedium)),
          TextButton.icon(
            onPressed: () => _report(context, ref),
            icon: const Icon(Icons.report_outlined),
            label: const Text('Report incident'),
          ),
        ]),
        items.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('$error'),
          data: (list) {
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Nothing new.', style: TextStyle(color: AppColors.charcoalMuted)),
              );
            }
            return Column(
              children: [
                for (final n in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(n.isRead ? Icons.drafts_outlined : Icons.mark_email_unread_outlined,
                          color: n.isRead ? AppColors.charcoalMuted : AppColors.brass),
                      title: Text(n.title),
                      subtitle: Text(n.body),
                      trailing: n.isRead
                          ? null
                          : TextButton(
                              onPressed: () => runWrite(context, () async {
                                await ref.read(operationsRepositoryProvider).markNotificationRead(n.id);
                                ref.invalidate(notificationsProvider);
                              }),
                              child: const Text('Mark read'),
                            ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final eventId = ref.read(selectedEventIdProvider);
    if (eventId == null) return;
    final draft = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _IncidentDialog(),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(operationsRepositoryProvider).reportIncident(
            eventId: eventId,
            kind: draft.$1,
            description: draft.$2,
          );
    }, success: 'Incident reported to management.');
  }
}

class _AnnounceDialog extends StatefulWidget {
  const _AnnounceDialog();

  @override
  State<_AnnounceDialog> createState() => _AnnounceDialogState();
}

class _AnnounceDialogState extends State<_AnnounceDialog> {
  final _body = TextEditingController();

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Announcement'),
      content: TextField(
        controller: _body,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(labelText: 'Message to everyone rostered on this event'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _body.text.trim()), child: const Text('Send')),
      ],
    );
  }
}

class _IncidentDialog extends StatefulWidget {
  const _IncidentDialog();

  @override
  State<_IncidentDialog> createState() => _IncidentDialogState();
}

class _IncidentDialogState extends State<_IncidentDialog> {
  static const _kinds = {
    'guest_concern': 'Guest concern',
    'culinary_issue': 'Culinary issue',
    'equipment': 'Equipment',
    'safety': 'Safety',
    'other': 'Other',
  };
  String _kind = 'guest_concern';
  final _description = TextEditingController();

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report incident'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final e in _kinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'What happened'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_description.text.trim().isEmpty) return;
            Navigator.pop(context, (_kind, _description.text.trim()));
          },
          child: const Text('Report'),
        ),
      ],
    );
  }
}
