import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/app_session.dart';
import '../../events/domain/readiness.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../application/operations_providers.dart';
import '../domain/operations.dart';

/// Banquet timeline, culinary production and handoffs, and the event menu.
class CulinaryScreen extends ConsumerWidget {
  const CulinaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) return const BackendRequired(title: 'Banquets & Culinary');

    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final eventId = ref.watch(selectedEventIdProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Banquets & Culinary'),
          bottom: const TabBar(tabs: [Tab(text: 'Timeline'), Tab(text: 'Culinary'), Tab(text: 'Menu')]),
        ),
        body: Column(
          children: [
            const EventPicker(),
            if (eventId != null)
              Expanded(
                child: TabBarView(
                  children: [
                    _TimelineTab(eventId: eventId, session: session, permissions: permissions),
                    _BatchTab(eventId: eventId, session: session, permissions: permissions),
                    _MenuTab(eventId: eventId, permissions: permissions),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineTab extends ConsumerWidget {
  const _TimelineTab({required this.eventId, required this.session, required this.permissions});

  final String eventId;
  final AppSession? session;
  final Set<AppPermission> permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(timelineProvider(eventId));
    final canManage = permissions.contains(AppPermission.manageBanquets);
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Timeline item'),
            )
          : null,
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('No timeline items yet.'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              for (final item in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                          StatusChip(
                            label: item.isLate(now) ? 'Late' : item.status.label,
                            color: item.isLate(now) || item.status == TimelineStatus.late
                                ? AppColors.delayed
                                : item.status == TimelineStatus.done
                                    ? AppColors.ready
                                    : item.status == TimelineStatus.blocked
                                        ? AppColors.blocked
                                        : AppColors.inProgress,
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          '${DateFormat('h:mm a').format(item.scheduledStart)} · ${item.department.label}'
                          '${item.assigneeName.isEmpty ? '' : ' · ${item.assigneeName}'}',
                          style: const TextStyle(color: AppColors.charcoalMuted, fontSize: 13),
                        ),
                        if (item.notes.isNotEmpty) Text(item.notes),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          if (item.status != TimelineStatus.done && item.status != TimelineStatus.inProgress)
                            OutlinedButton(
                              onPressed: () => _set(context, ref, item, TimelineStatus.inProgress),
                              child: const Text('Start'),
                            ),
                          if (item.status != TimelineStatus.done)
                            FilledButton.tonal(
                              onPressed: () => _set(context, ref, item, TimelineStatus.done),
                              child: const Text('Done'),
                            ),
                          if (item.status != TimelineStatus.blocked && item.status != TimelineStatus.done)
                            TextButton(
                              onPressed: () => _block(context, ref, item),
                              child: const Text('Block'),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, TimelineItem item, TimelineStatus to, {String note = ''}) async {
    await runWrite(context, () async {
      await ref.read(operationsRepositoryProvider).setTimelineStatus(item, to, note: note);
      ref.invalidate(timelineProvider(eventId));
    });
  }

  Future<void> _block(BuildContext context, WidgetRef ref, TimelineItem item) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _TextPromptDialog(title: 'Why is this blocked?', label: 'Reason'),
    );
    if (reason == null || reason.isEmpty || !context.mounted) return;
    await _set(context, ref, item, TimelineStatus.blocked, note: reason);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    final draft = await showDialog<_TimelineDraft>(
      context: context,
      builder: (_) => const _TimelineDialog(),
    );
    if (draft == null || session == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(operationsRepositoryProvider).addTimelineItem(
            venueId: session.venueId,
            eventId: eventId,
            title: draft.title,
            department: draft.department,
            assignee: draft.assignee,
            scheduledStart: draft.start,
            target: draft.target,
          );
      ref.invalidate(timelineProvider(eventId));
    }, success: 'Timeline item added.');
  }
}

class _BatchTab extends ConsumerWidget {
  const _BatchTab({required this.eventId, required this.session, required this.permissions});

  final String eventId;
  final AppSession? session;
  final Set<AppPermission> permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches = ref.watch(batchesProvider(eventId));
    final canProduce = permissions.contains(AppPermission.viewCulinary);
    final canRun = permissions.contains(AppPermission.manageRequests);
    final canReceive = permissions.contains(AppPermission.updateTasks);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canProduce
          ? FloatingActionButton.extended(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Batch'),
            )
          : null,
      body: batches.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('No culinary batches yet.'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Ready is not delivered. Each handoff is recorded separately: ready, collected, delivered, received.',
                  style: TextStyle(color: AppColors.charcoalMuted, fontSize: 13),
                ),
              ),
              for (final b in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text('${b.quantity} × ${b.description}',
                              style: const TextStyle(fontWeight: FontWeight.w600))),
                          StatusChip(label: b.state.label, color: _batchColor(b)),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (b.destination.isNotEmpty) b.destination,
                            if (b.dueAt != null) 'Due ${DateFormat('h:mm a').format(b.dueAt!)}',
                            if (b.isLateDelivery()) 'Delivered late',
                            if (b.receivedBy.isNotEmpty) 'Received by ${b.receivedBy}',
                          ].join(' · '),
                          style: const TextStyle(color: AppColors.charcoalMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        _nextStep(context, ref, b, canProduce: canProduce, canRun: canRun, canReceive: canReceive),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _nextStep(BuildContext context, WidgetRef ref, CulinaryBatch b,
      {required bool canProduce, required bool canRun, required bool canReceive}) {
    final next = b.state.next;
    if (next == null) return const SizedBox.shrink();
    final allowed = switch (next) {
      BatchState.inProduction || BatchState.ready => canProduce,
      BatchState.collected || BatchState.delivered => canRun,
      BatchState.received => canReceive,
      _ => false,
    };
    if (!allowed) return const SizedBox.shrink();
    final label = switch (next) {
      BatchState.inProduction => 'Start production',
      BatchState.ready => 'Mark ready',
      BatchState.collected => 'Collected by runner',
      BatchState.delivered => 'Mark delivered',
      BatchState.received => 'Confirm received',
      _ => next.label,
    };
    return FilledButton.tonal(
      onPressed: () async {
        var receiver = '';
        if (next == BatchState.received) {
          final name = await showDialog<String>(
            context: context,
            builder: (_) => const _TextPromptDialog(title: 'Who received it?', label: 'Receiver name'),
          );
          if (name == null || name.isEmpty || !context.mounted) return;
          receiver = name;
        }
        if (!context.mounted) return;
        await runWrite(context, () async {
          await ref.read(operationsRepositoryProvider).advanceBatch(b, next, receiver: receiver);
          ref.invalidate(batchesProvider(eventId));
        });
      },
      child: Text(label),
    );
  }

  Color _batchColor(CulinaryBatch b) => switch (b.state) {
        BatchState.received || BatchState.delivered => AppColors.ready,
        BatchState.collected => AppColors.inProgress,
        BatchState.ready => AppColors.attention,
        _ => AppColors.neutral,
      };

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_BatchDraft>(
      context: context,
      builder: (_) => const _BatchDialog(),
    );
    if (draft == null || session == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(operationsRepositoryProvider).createBatch(
            venueId: session!.venueId,
            eventId: eventId,
            description: draft.description,
            quantity: draft.quantity,
            destination: draft.destination,
            dueAt: draft.due,
          );
      ref.invalidate(batchesProvider(eventId));
    }, success: 'Batch added.');
  }
}

class _MenuTab extends ConsumerWidget {
  const _MenuTab({required this.eventId, required this.permissions});

  final String eventId;
  final Set<AppPermission> permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(menuProvider(eventId));
    final canEdit = permissions.contains(AppPermission.viewCulinary);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () async {
                final draft = await showDialog<_MenuDraft>(context: context, builder: (_) => const _MenuDialog());
                if (draft == null || !context.mounted) return;
                final session = ref.read(sessionProvider);
                if (session == null) return;
                await runWrite(context, () async {
                  await ref.read(operationsRepositoryProvider).addMenuItem(
                        venueId: session.venueId,
                        eventId: eventId,
                        name: draft.name,
                        course: draft.course,
                        allergens: draft.allergens,
                        dietaryTags: draft.tags,
                      );
                  ref.invalidate(menuProvider(eventId));
                }, success: 'Menu item added.');
              },
              icon: const Icon(Icons.add),
              label: const Text('Menu item'),
            )
          : null,
      body: menu.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (items) {
          if (items.isEmpty) return const Center(child: Text('No menu items yet.'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              for (final m in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(m.name),
                  subtitle: Text([
                    if (m.course.isNotEmpty) m.course,
                    if (m.dietaryTags.isNotEmpty) m.dietaryTags.join(', '),
                    if (m.allergens.isNotEmpty) 'Allergens: ${m.allergens}',
                  ].join(' · ')),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineDraft {
  const _TimelineDraft({required this.title, required this.department, required this.assignee, required this.start, this.target});

  final String title;
  final Department department;
  final String assignee;
  final DateTime start;
  final DateTime? target;
}

class _TimelineDialog extends StatefulWidget {
  const _TimelineDialog();

  @override
  State<_TimelineDialog> createState() => _TimelineDialogState();
}

class _TimelineDialogState extends State<_TimelineDialog> {
  final _title = TextEditingController();
  final _assignee = TextEditingController();
  Department _dept = Department.banquets;
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _assignee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Timeline item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _title, decoration: InputDecoration(labelText: 'What happens', errorText: _error)),
            const SizedBox(height: 10),
            TextField(controller: _assignee, decoration: const InputDecoration(labelText: 'Assigned to')),
            const SizedBox(height: 10),
            DropdownButtonFormField<Department>(
              initialValue: _dept,
              decoration: const InputDecoration(labelText: 'Department'),
              items: [for (final d in Department.values) DropdownMenuItem(value: d, child: Text(d.label))],
              onChanged: (v) => setState(() => _dept = v ?? _dept),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async {
                final picked = await pickDateTime(context, _start);
                if (picked != null) setState(() => _start = picked);
              },
              child: Text('Starts ${DateFormat('MMM d, h:mm a').format(_start)}'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) {
              setState(() => _error = 'Describe the item.');
              return;
            }
            Navigator.pop(context, _TimelineDraft(
              title: _title.text.trim(),
              department: _dept,
              assignee: _assignee.text.trim(),
              start: _start,
              target: _start,
            ));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _BatchDraft {
  const _BatchDraft({required this.description, required this.quantity, required this.destination, this.due});

  final String description;
  final int quantity;
  final String destination;
  final DateTime? due;
}

class _BatchDialog extends StatefulWidget {
  const _BatchDialog();

  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
  final _description = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _destination = TextEditingController();
  DateTime? _due;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New batch'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _description, decoration: InputDecoration(labelText: 'Dish or item', errorText: _error)),
            const SizedBox(height: 10),
            TextField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
            const SizedBox(height: 10),
            TextField(controller: _destination, decoration: const InputDecoration(labelText: 'Destination (suite, pickup point)')),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async {
                final picked = await pickDateTime(context, _due ?? DateTime.now().add(const Duration(hours: 1)));
                if (picked != null) setState(() => _due = picked);
              },
              child: Text(_due == null ? 'Set due time' : 'Due ${DateFormat('h:mm a').format(_due!)}'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final qty = int.tryParse(_quantity.text.trim());
            if (_description.text.trim().isEmpty) {
              setState(() => _error = 'Name the item.');
              return;
            }
            if (qty == null || qty < 1) {
              setState(() => _error = 'Quantity must be at least 1.');
              return;
            }
            Navigator.pop(context, _BatchDraft(
              description: _description.text.trim(),
              quantity: qty,
              destination: _destination.text.trim(),
              due: _due,
            ));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _MenuDraft {
  const _MenuDraft({required this.name, required this.course, required this.allergens, required this.tags});

  final String name;
  final String course;
  final String allergens;
  final List<String> tags;
}

class _MenuDialog extends StatefulWidget {
  const _MenuDialog();

  @override
  State<_MenuDialog> createState() => _MenuDialogState();
}

class _MenuDialogState extends State<_MenuDialog> {
  final _name = TextEditingController();
  final _course = TextEditingController();
  final _allergens = TextEditingController();
  final _tags = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _course, _allergens, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Menu item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(controller: _course, decoration: const InputDecoration(labelText: 'Course')),
            const SizedBox(height: 10),
            TextField(controller: _tags, decoration: const InputDecoration(labelText: 'Dietary tags (comma separated)')),
            const SizedBox(height: 10),
            TextField(controller: _allergens, decoration: const InputDecoration(labelText: 'Allergens')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(context, _MenuDraft(
              name: _name.text.trim(),
              course: _course.text.trim(),
              allergens: _allergens.text.trim(),
              tags: _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
            ));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(controller: _controller, autofocus: true, decoration: InputDecoration(labelText: widget.label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('Confirm')),
      ],
    );
  }
}
