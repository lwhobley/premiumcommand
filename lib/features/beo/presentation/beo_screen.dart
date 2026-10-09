import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/application/session_controller.dart';
import '../../events/application/event_providers.dart';
import '../../events/domain/readiness.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/data/planning_repository.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../domain/beo.dart';

/// BEO management: approved content, the approval queue, revision history, and department acknowledgment.
class BeoScreen extends ConsumerWidget {
  const BeoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) return const BackendRequired(title: 'BEO Management');

    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final eventId = ref.watch(selectedEventIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('BEO Management')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const EventPicker(),
          if (eventId != null)
            _BeoBody(eventId: eventId, permissions: permissions),
        ],
      ),
    );
  }
}

class _BeoBody extends ConsumerWidget {
  const _BeoBody({required this.eventId, required this.permissions});

  final String eventId;
  final Set<AppPermission> permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final beo = ref.watch(beoProvider(eventId));
    final canEdit = permissions.contains(AppPermission.manageEvents);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: beo.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text('$error'),
        data: (bundle) {
          if (bundle == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('No BEO for this event yet.', style: TextStyle(color: AppColors.charcoalMuted)),
                const SizedBox(height: 12),
                if (canEdit)
                  FilledButton(
                    onPressed: () => _create(context, ref),
                    child: const Text('Create BEO'),
                  ),
              ],
            );
          }
          final pending = bundle.latest?.status == RevisionStatus.draft ? bundle.latest : null;
          final approved = bundle.approved;
          final canApprove = permissions.contains(AppPermission.approveBeo);
          final canAck = permissions.contains(AppPermission.updateTasks);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bundle.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (pending != null)
                _PendingCard(
                  revision: pending,
                  canApprove: canApprove,
                  onApprove: () => _approve(context, ref, pending),
                ),
              if (approved != null) ...[
                _ApprovedCard(revision: approved),
                const SizedBox(height: 12),
                _AcknowledgmentCard(
                  revision: approved,
                  acknowledged: bundle.acknowledgedDepartments,
                  canAck: canAck,
                  onAck: (dept) => _ack(context, ref, approved, dept),
                ),
              ] else
                const Text('No approved revision yet. Approve a draft to publish the BEO.',
                    style: TextStyle(color: AppColors.charcoalMuted)),
              const SizedBox(height: 12),
              if (canEdit && pending == null && bundle.latest != null)
                OutlinedButton.icon(
                  onPressed: () => _propose(context, ref, bundle),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Propose revision'),
                ),
              const SizedBox(height: 20),
              Text('Revision history', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final r in bundle.revisions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Revision ${r.revisionNo} · ${r.summary}'),
                  subtitle: Text(DateFormat('MMM d, h:mm a').format(r.createdAt)),
                  trailing: StatusChip(
                    label: r.status.label,
                    color: switch (r.status) {
                      RevisionStatus.approved => AppColors.ready,
                      RevisionStatus.draft => AppColors.attention,
                      RevisionStatus.superseded => AppColors.neutral,
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_EditorResult>(
      context: context,
      builder: (_) => const _BeoEditorDialog(title: 'Create BEO', askTitle: true),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(planningRepositoryProvider).createBeo(
            eventId: eventId,
            title: draft.title!,
            content: draft.content,
            summary: draft.summary,
          );
      ref.invalidate(beoProvider(eventId));
    }, success: 'BEO created. It needs approval before it is published.');
  }

  Future<void> _propose(BuildContext context, WidgetRef ref, BeoBundle bundle) async {
    final base = bundle.approved?.content ?? bundle.latest!.content;
    final draft = await showDialog<_EditorResult>(
      context: context,
      builder: (_) => _BeoEditorDialog(title: 'Propose revision', initial: base),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(planningRepositoryProvider).proposeRevision(
            beoId: bundle.beoId,
            content: draft.content,
            summary: draft.summary,
            expectedRevision: bundle.latest!.revisionNo,
          );
      ref.invalidate(beoProvider(eventId));
    }, success: 'Revision proposed for approval.');
  }

  Future<void> _approve(BuildContext context, WidgetRef ref, BeoRevision revision) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Approve revision ${revision.revisionNo}?'),
        content: const Text(
          'Approving publishes this BEO. Departments affected by a change will have their open tasks flagged for review.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(planningRepositoryProvider).approveRevision(revision.id);
      ref.invalidate(beoProvider(eventId));
      ref.invalidate(eventSnapshotsProvider);
    }, success: 'BEO approved.');
  }

  Future<void> _ack(BuildContext context, WidgetRef ref, BeoRevision revision, String department) async {
    await runWrite(context, () async {
      await ref.read(planningRepositoryProvider).acknowledgeRevision(revision.id, department);
      ref.invalidate(beoProvider(eventId));
      ref.invalidate(eventSnapshotsProvider);
    }, success: 'Acknowledged for ${Department.fromCode(department).label}.');
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.revision, required this.canApprove, required this.onApprove});

  final BeoRevision revision;
  final bool canApprove;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.brassSoft,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Revision ${revision.revisionNo} awaiting approval',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(revision.summary),
            const SizedBox(height: 10),
            if (canApprove)
              FilledButton(onPressed: onApprove, child: const Text('Approve'))
            else
              const Text('Only a director can approve BEO revisions.',
                  style: TextStyle(color: AppColors.charcoalMuted)),
          ],
        ),
      ),
    );
  }
}

class _ApprovedCard extends StatelessWidget {
  const _ApprovedCard({required this.revision});

  final BeoRevision revision;

  @override
  Widget build(BuildContext context) {
    final c = revision.content;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Approved · revision ${revision.revisionNo}',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              const StatusChip(label: 'Approved', color: AppColors.ready),
            ]),
            const SizedBox(height: 10),
            _Field(label: 'Guests', value: '${c.guests}'),
            _Field(label: 'Departments', value: c.departments.isEmpty ? '—' : c.departments.map((d) => d.label).join(', ')),
            if (c.timeline.isNotEmpty) _Field(label: 'Timeline', value: c.timeline),
            if (c.menu.isNotEmpty) _Field(label: 'Menu', value: c.menu),
            if (c.dietary.isNotEmpty) _Field(label: 'Dietary', value: c.dietary),
            if (c.beverage.isNotEmpty) _Field(label: 'Beverage', value: c.beverage),
            if (c.equipment.isNotEmpty) _Field(label: 'Equipment', value: c.equipment),
            if (c.specialRequests.isNotEmpty) _Field(label: 'Special requests', value: c.specialRequests),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppColors.charcoalMuted))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _AcknowledgmentCard extends StatelessWidget {
  const _AcknowledgmentCard({
    required this.revision,
    required this.acknowledged,
    required this.canAck,
    required this.onAck,
  });

  final BeoRevision revision;
  final Set<String> acknowledged;
  final bool canAck;
  final void Function(String department) onAck;

  @override
  Widget build(BuildContext context) {
    final depts = revision.content.departments.toList()..sort((a, b) => a.index.compareTo(b.index));
    if (depts.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Department acknowledgment', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final d in depts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(d.label)),
                    if (acknowledged.contains(d.code))
                      const StatusChip(label: 'Acknowledged', color: AppColors.ready)
                    else if (canAck)
                      OutlinedButton(onPressed: () => onAck(d.code), child: const Text('Acknowledge'))
                    else
                      const StatusChip(label: 'Pending', color: AppColors.attention),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditorResult {
  const _EditorResult({required this.content, required this.summary, this.title});

  final BeoContent content;
  final String summary;
  final String? title;
}

class _BeoEditorDialog extends StatefulWidget {
  const _BeoEditorDialog({required this.title, this.initial, this.askTitle = false});

  final String title;
  final BeoContent? initial;
  final bool askTitle;

  @override
  State<_BeoEditorDialog> createState() => _BeoEditorDialogState();
}

class _BeoEditorDialogState extends State<_BeoEditorDialog> {
  late final _beoTitle = TextEditingController(text: widget.askTitle ? 'BEO' : '');
  late final _guests = TextEditingController(text: '${widget.initial?.guests ?? 0}');
  late final _timeline = TextEditingController(text: widget.initial?.timeline ?? '');
  late final _menu = TextEditingController(text: widget.initial?.menu ?? '');
  late final _dietary = TextEditingController(text: widget.initial?.dietary ?? '');
  late final _beverage = TextEditingController(text: widget.initial?.beverage ?? '');
  late final _equipment = TextEditingController(text: widget.initial?.equipment ?? '');
  late final _special = TextEditingController(text: widget.initial?.specialRequests ?? '');
  late final _summary = TextEditingController(text: widget.askTitle ? 'Initial BEO' : '');
  late final Set<Department> _departments = {...?widget.initial?.departments};
  String? _error;

  @override
  void dispose() {
    for (final c in [_beoTitle, _guests, _timeline, _menu, _dietary, _beverage, _equipment, _special, _summary]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final guests = int.tryParse(_guests.text.trim());
    if (widget.askTitle && _beoTitle.text.trim().isEmpty) {
      setState(() => _error = 'Give the BEO a title.');
      return;
    }
    if (guests == null || guests < 0) {
      setState(() => _error = 'Guest count must be a whole number.');
      return;
    }
    if (_summary.text.trim().isEmpty) {
      setState(() => _error = 'Describe what changed.');
      return;
    }
    Navigator.pop(
      context,
      _EditorResult(
        title: widget.askTitle ? _beoTitle.text.trim() : null,
        summary: _summary.text.trim(),
        content: BeoContent(
          guests: guests,
          departments: _departments,
          timeline: _timeline.text.trim(),
          menu: _menu.text.trim(),
          dietary: _dietary.text.trim(),
          beverage: _beverage.text.trim(),
          equipment: _equipment.text.trim(),
          specialRequests: _special.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.askTitle) ...[
                TextField(controller: _beoTitle, decoration: const InputDecoration(labelText: 'BEO title')),
                const SizedBox(height: 10),
              ],
              TextField(controller: _guests, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Guests')),
              const SizedBox(height: 10),
              const Text('Departments affected'),
              Wrap(
                spacing: 6,
                children: [
                  for (final d in Department.values)
                    FilterChip(
                      label: Text(d.label),
                      selected: _departments.contains(d),
                      onSelected: (on) => setState(() => on ? _departments.add(d) : _departments.remove(d)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: _timeline, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Service timeline')),
              const SizedBox(height: 10),
              TextField(controller: _menu, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'Menu')),
              const SizedBox(height: 10),
              TextField(controller: _dietary, decoration: const InputDecoration(labelText: 'Dietary restrictions')),
              const SizedBox(height: 10),
              TextField(controller: _beverage, decoration: const InputDecoration(labelText: 'Beverage service')),
              const SizedBox(height: 10),
              TextField(controller: _equipment, decoration: const InputDecoration(labelText: 'Equipment')),
              const SizedBox(height: 10),
              TextField(controller: _special, decoration: const InputDecoration(labelText: 'Special requests')),
              const SizedBox(height: 10),
              TextField(
                controller: _summary,
                decoration: InputDecoration(labelText: 'What changed (required)', errorText: _error),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
