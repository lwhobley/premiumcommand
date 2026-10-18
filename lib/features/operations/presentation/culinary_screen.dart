import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/venue_time.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/app_session.dart';
import '../../events/domain/readiness.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../../document_import/domain/document_import.dart';
import '../../document_import/presentation/document_import_screen.dart';
import '../application/operations_providers.dart';
import '../domain/operations.dart';

/// Banquet timeline, culinary production and handoffs, and the event menu.
class CulinaryScreen extends ConsumerWidget {
  const CulinaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) {
      return const BackendRequired(title: 'Banquets & Culinary');
    }

    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final eventId = ref.watch(selectedEventIdProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ScreenHeader(
                kicker: 'Operations',
                title: 'Banquets & Culinary',
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.screen - 16),
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Timeline'),
                    Tab(text: 'Culinary'),
                    Tab(text: 'Menu'),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.screen,
                  AppSpace.m,
                  AppSpace.screen,
                  0,
                ),
                child: EventPicker(),
              ),
              if (eventId != null)
                Expanded(
                  child: TabBarView(
                    children: [
                      _TimelineTab(
                        eventId: eventId,
                        session: session,
                        permissions: permissions,
                      ),
                      _BatchTab(
                        eventId: eventId,
                        session: session,
                        permissions: permissions,
                      ),
                      _MenuTab(eventId: eventId, permissions: permissions),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineTab extends ConsumerWidget {
  const _TimelineTab({
    required this.eventId,
    required this.session,
    required this.permissions,
  });

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
              icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
              label: const Text('Timeline item'),
            )
          : null,
      body: items.when(
        loading: () => const Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(),
        ),
        error: (error, _) => _Note('$error'),
        data: (list) {
          if (list.isEmpty) return const _Note('No timeline items yet.');
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screen,
              8,
              AppSpace.screen,
              96,
            ),
            children: [
              for (final item in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.row),
                  child: OpenRow(
                    title: item.title,
                    trailing: Tag(
                      item.isLate(now) ? 'Late' : item.status.label,
                      item.isLate(now) ||
                              item.status == TimelineStatus.late ||
                              item.status == TimelineStatus.blocked
                          ? Tone.alert
                          : item.status == TimelineStatus.done ||
                                item.status == TimelineStatus.inProgress
                          ? Tone.accent
                          : Tone.neutral,
                    ),
                    meta:
                        '${DateFormat('h:mm a').format(atVenue(item.scheduledStart, session?.timeZone ?? 'UTC'))} · ${item.department.label}'
                        '${item.assigneeName.isEmpty ? '' : ' · ${item.assigneeName}'}',
                    below: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.notes.isNotEmpty) ...[
                          Text(item.notes, style: AppText.body),
                          const SizedBox(height: 8),
                        ],
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (item.status != TimelineStatus.done &&
                                item.status != TimelineStatus.inProgress)
                              OutlinedButton(
                                onPressed: () => _set(
                                  context,
                                  ref,
                                  item,
                                  TimelineStatus.inProgress,
                                ),
                                child: const Text('Start'),
                              ),
                            if (item.status != TimelineStatus.done)
                              FilledButton.tonal(
                                onPressed: () => _set(
                                  context,
                                  ref,
                                  item,
                                  TimelineStatus.done,
                                ),
                                child: const Text('Done'),
                              ),
                            if (item.status != TimelineStatus.blocked &&
                                item.status != TimelineStatus.done)
                              TextButton(
                                onPressed: () => _block(context, ref, item),
                                child: const Text('Block'),
                              ),
                          ],
                        ),
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

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    TimelineItem item,
    TimelineStatus to, {
    String note = '',
  }) async {
    await runWrite(context, () async {
      await ref
          .read(operationsRepositoryProvider)
          .setTimelineStatus(item, to, note: note);
      ref.invalidate(timelineProvider(eventId));
    });
  }

  Future<void> _block(
    BuildContext context,
    WidgetRef ref,
    TimelineItem item,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _TextPromptDialog(
        title: 'Why is this blocked?',
        label: 'Reason',
      ),
    );
    if (reason == null || reason.isEmpty || !context.mounted) return;
    await _set(context, ref, item, TimelineStatus.blocked, note: reason);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    final draft = await showDialog<_TimelineDraft>(
      context: context,
      builder: (_) => _TimelineDialog(timeZone: session?.timeZone ?? 'UTC'),
    );
    if (draft == null || session == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref
          .read(operationsRepositoryProvider)
          .addTimelineItem(
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
  const _BatchTab({
    required this.eventId,
    required this.session,
    required this.permissions,
  });

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
              icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
              label: const Text('Batch'),
            )
          : null,
      body: batches.when(
        loading: () => const Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(),
        ),
        error: (error, _) => _Note('$error'),
        data: (list) {
          if (list.isEmpty) return const _Note('No culinary batches yet.');
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screen,
              8,
              AppSpace.screen,
              96,
            ),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpace.m),
                child: Text(
                  'Ready is not delivered. Each handoff is recorded separately: ready, collected, delivered, received.',
                  style: AppText.meta,
                ),
              ),
              for (final b in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.row),
                  child: OpenRow(
                    title: '${b.quantity} × ${b.description}',
                    trailing: Tag(b.state.label, _batchTone(b)),
                    meta: [
                      if (b.destination.isNotEmpty) b.destination,
                      if (b.dueAt != null)
                        'Due ${DateFormat('h:mm a').format(atVenue(b.dueAt!, session?.timeZone ?? 'UTC'))}',
                      if (b.isLateDelivery()) 'Delivered late',
                      if (b.receivedBy.isNotEmpty)
                        'Received by ${b.receivedBy}',
                    ].join(' · '),
                    below: _nextStep(
                      context,
                      ref,
                      b,
                      canProduce: canProduce,
                      canRun: canRun,
                      canReceive: canReceive,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _nextStep(
    BuildContext context,
    WidgetRef ref,
    CulinaryBatch b, {
    required bool canProduce,
    required bool canRun,
    required bool canReceive,
  }) {
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
            builder: (_) => const _TextPromptDialog(
              title: 'Who received it?',
              label: 'Receiver name',
            ),
          );
          if (name == null || name.isEmpty || !context.mounted) return;
          receiver = name;
        }
        if (!context.mounted) return;
        await runWrite(context, () async {
          await ref
              .read(operationsRepositoryProvider)
              .advanceBatch(b, next, receiver: receiver);
          ref.invalidate(batchesProvider(eventId));
        });
      },
      child: Text(label),
    );
  }

  Tone _batchTone(CulinaryBatch b) => switch (b.state) {
    BatchState.received || BatchState.delivered => Tone.accent,
    BatchState.collected => Tone.accent,
    BatchState.ready => Tone.accent,
    _ => Tone.neutral,
  };

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_BatchDraft>(
      context: context,
      builder: (_) => _BatchDialog(timeZone: session?.timeZone ?? 'UTC'),
    );
    if (draft == null || session == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref
          .read(operationsRepositoryProvider)
          .createBatch(
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
                final draft = await showDialog<_MenuDraft>(
                  context: context,
                  builder: (_) => const _MenuDialog(),
                );
                if (draft == null || !context.mounted) return;
                final session = ref.read(sessionProvider);
                if (session == null) return;
                await runWrite(context, () async {
                  await ref
                      .read(operationsRepositoryProvider)
                      .addMenuItem(
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
              icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
              label: const Text('Menu item'),
            )
          : null,
      body: menu.when(
        loading: () => const Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(),
        ),
        error: (error, _) => _Note('$error'),
        data: (items) {
          // The document assistant is for administrators only.
          final import =
              canEdit && permissions.contains(AppPermission.manageConfiguration)
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _import(context, ref),
                    icon: const PhosphorIcon(PhosphorIconsDuotone.sparkle),
                    label: const Text('Import menu with AI'),
                  ),
                )
              : null;
          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screen,
                8,
                AppSpace.screen,
                96,
              ),
              children: [const EmptyNote('No menu items yet.'), ?import],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screen,
              8,
              AppSpace.screen,
              96,
            ),
            children: [
              ?import,
              for (final m in items)
                OpenRow(
                  title: m.name,
                  meta: [
                    if (m.course.isNotEmpty) m.course,
                    if (m.dietaryTags.isNotEmpty) m.dietaryTags.join(', '),
                    if (m.allergens.isNotEmpty) 'Allergens: ${m.allergens}',
                  ].join(' · '),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Reads a menu document with the assistant and adds the dishes the administrator keeps.
  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final outcome = await showDocumentImport(
      context,
      kind: ImportKind.menu,
      eventId: eventId,
    );
    final session = ref.read(sessionProvider);
    if (outcome == null ||
        outcome.menuItems.isEmpty ||
        session == null ||
        !context.mounted) {
      return;
    }
    final count = outcome.menuItems.length;
    await runWrite(context, () async {
      final operations = ref.read(operationsRepositoryProvider);
      for (final item in outcome.menuItems) {
        await operations.addMenuItem(
          venueId: session.venueId,
          eventId: eventId,
          name: item.name,
          course: item.course,
          allergens: item.allergens,
          dietaryTags: item.dietaryTags,
        );
      }
      ref.invalidate(menuProvider(eventId));
    }, success: '$count menu ${count == 1 ? 'item' : 'items'} added.');
  }
}

/// A muted message for empty, loading-failed tabs, flush left at the screen padding.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(AppSpace.screen, 8, AppSpace.screen, 96),
    children: [EmptyNote(text)],
  );
}

class _TimelineDraft {
  const _TimelineDraft({
    required this.title,
    required this.department,
    required this.assignee,
    required this.start,
    this.target,
  });

  final String title;
  final Department department;
  final String assignee;
  final DateTime start;
  final DateTime? target;
}

class _TimelineDialog extends StatefulWidget {
  const _TimelineDialog({required this.timeZone});
  final String timeZone;

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
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: 'What happens',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _assignee,
              decoration: const InputDecoration(labelText: 'Assigned to'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Department>(
              initialValue: _dept,
              decoration: const InputDecoration(labelText: 'Department'),
              items: [
                for (final d in Department.values)
                  DropdownMenuItem(value: d, child: Text(d.label)),
              ],
              onChanged: (v) => setState(() => _dept = v ?? _dept),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async {
                final picked = await pickDateTime(
                  context,
                  _start,
                  timeZone: widget.timeZone,
                );
                if (picked != null && mounted) setState(() => _start = picked);
              },
              child: Text(
                'Starts ${DateFormat('MMM d, h:mm a').format(atVenue(_start, widget.timeZone))} ${widget.timeZone}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) {
              setState(() => _error = 'Describe the item.');
              return;
            }
            Navigator.pop(
              context,
              _TimelineDraft(
                title: _title.text.trim(),
                department: _dept,
                assignee: _assignee.text.trim(),
                start: _start,
                target: null,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _BatchDraft {
  const _BatchDraft({
    required this.description,
    required this.quantity,
    required this.destination,
    this.due,
  });

  final String description;
  final int quantity;
  final String destination;
  final DateTime? due;
}

class _BatchDialog extends StatefulWidget {
  const _BatchDialog({required this.timeZone});
  final String timeZone;

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
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: 'Dish or item',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _destination,
              decoration: const InputDecoration(
                labelText: 'Destination (suite, pickup point)',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async {
                final picked = await pickDateTime(
                  context,
                  _due ?? DateTime.now().add(const Duration(hours: 1)),
                  timeZone: widget.timeZone,
                );
                if (picked != null && mounted) setState(() => _due = picked);
              },
              child: Text(
                _due == null
                    ? 'Set due time'
                    : 'Due ${DateFormat('h:mm a').format(atVenue(_due!, widget.timeZone))} ${widget.timeZone}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
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
            Navigator.pop(
              context,
              _BatchDraft(
                description: _description.text.trim(),
                quantity: qty,
                destination: _destination.text.trim(),
                due: _due,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _MenuDraft {
  const _MenuDraft({
    required this.name,
    required this.course,
    required this.allergens,
    required this.tags,
  });

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
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _course,
              decoration: const InputDecoration(labelText: 'Course'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Dietary tags (comma separated)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _allergens,
              decoration: const InputDecoration(labelText: 'Allergens'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _MenuDraft(
                name: _name.text.trim(),
                course: _course.text.trim(),
                allergens: _allergens.text.trim(),
                tags: _tags.text
                    .split(',')
                    .map((t) => t.trim())
                    .where((t) => t.isNotEmpty)
                    .toList(),
              ),
            );
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
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
