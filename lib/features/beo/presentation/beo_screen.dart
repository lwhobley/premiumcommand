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
import '../../events/application/event_providers.dart';
import '../../events/domain/readiness.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/data/planning_repository.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../../document_import/domain/document_import.dart';
import '../../document_import/presentation/document_import_screen.dart';
import '../../operations/application/operations_providers.dart';
import '../domain/beo.dart';

/// BEO management: approved content, the approval queue, revision history, and department acknowledgment.
class BeoScreen extends ConsumerWidget {
  const BeoScreen({super.key, this.eventId});

  final String? eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) {
      return const BackendRequired(title: 'BEO Management');
    }

    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final activeEventId = eventId ?? ref.watch(selectedEventIdProvider);

    return PageScaffold(
      kicker: 'Planning',
      title: 'BEO Management',
      back: eventId != null && Navigator.of(context).canPop()
          ? const BackLink()
          : null,
      children: [
        if (eventId == null) const EventPicker(),
        if (activeEventId != null)
          _BeoBody(eventId: activeEventId, permissions: permissions),
      ],
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
    // The document assistant is for administrators only.
    final canImport =
        canEdit && permissions.contains(AppPermission.manageConfiguration);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.s),
      child: beo.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text('$error'),
        data: (bundle) {
          if (bundle == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EmptyNote('No BEO for this event yet.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canEdit)
                      FilledButton(
                        onPressed: () => _create(context, ref),
                        child: const Text('Create BEO'),
                      ),
                    if (canImport)
                      OutlinedButton.icon(
                        onPressed: () => _import(context, ref, null),
                        icon: const PhosphorIcon(PhosphorIconsDuotone.sparkle),
                        label: const Text('Import with AI'),
                      ),
                  ],
                ),
              ],
            );
          }
          final pending = bundle.latest?.status == RevisionStatus.draft
              ? bundle.latest
              : null;
          final approved = bundle.approved;
          final canApprove = permissions.contains(AppPermission.approveBeo);
          final canAck = permissions.contains(AppPermission.updateTasks);
          final session = ref.watch(sessionProvider);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(bundle.title, first: true),
              if (pending != null)
                _PendingCard(
                  revision: pending,
                  canApprove: canApprove,
                  onApprove: () => _approve(context, ref, pending),
                ),
              if (approved != null) ...[
                _ApprovedCard(revision: approved),
                _AcknowledgmentCard(
                  revision: approved,
                  acknowledged: bundle.acknowledgedDepartments,
                  canAck: canAck,
                  allowedDepartments:
                      session?.departments.map((d) => d.code).toSet() ??
                      const {},
                  canManageEvents: permissions.contains(
                    AppPermission.manageEvents,
                  ),
                  onAck: (dept) => _ack(context, ref, approved, dept),
                ),
              ] else
                const EmptyNote(
                  'No approved revision yet. Approve a draft to publish the BEO.',
                ),
              const SizedBox(height: AppSpace.l),
              if (canEdit && pending == null && bundle.latest != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _propose(context, ref, bundle),
                      icon: const PhosphorIcon(PhosphorIconsDuotone.notePencil),
                      label: const Text('Propose revision'),
                    ),
                    if (canImport)
                      OutlinedButton.icon(
                        onPressed: () => _import(context, ref, bundle),
                        icon: const PhosphorIcon(PhosphorIconsDuotone.sparkle),
                        label: const Text('Import revision with AI'),
                      ),
                  ],
                ),
              const SectionHeading('Revision history'),
              for (final r in bundle.revisions)
                OpenRow(
                  title: 'Revision ${r.revisionNo} · ${r.summary}',
                  meta: DateFormat('MMM d, h:mm a')
                      .format(atVenue(r.createdAt, session?.timeZone ?? 'UTC')),
                  trailing: Tag(r.status.label, switch (r.status) {
                    RevisionStatus.approved => Tone.accent,
                    RevisionStatus.draft => Tone.neutral,
                    RevisionStatus.superseded => Tone.neutral,
                  }),
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
      builder: (_) =>
          const _BeoEditorDialog(title: 'Create BEO', askTitle: true),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref
          .read(planningRepositoryProvider)
          .createBeo(
            eventId: eventId,
            title: draft.title!,
            content: draft.content,
            summary: draft.summary,
          );
      ref.invalidate(beoProvider(eventId));
    }, success: 'BEO created. It needs approval before it is published.');
  }

  /// Reads a BEO document with the assistant, then opens the usual editor with what it
  /// found: a new BEO when there is none, otherwise a revision for approval. Chosen menu
  /// items are added to the event menu once the BEO is saved.
  Future<void> _import(
    BuildContext context,
    WidgetRef ref,
    BeoBundle? bundle,
  ) async {
    final outcome = await showDocumentImport(
      context,
      kind: ImportKind.beo,
      eventId: eventId,
    );
    final content = outcome?.result.content;
    if (outcome == null || content == null || !context.mounted) return;
    final result = outcome.result;
    final draft = await showDialog<_EditorResult>(
      context: context,
      builder: (_) => _BeoEditorDialog(
        title: bundle == null ? 'Create BEO' : 'Propose revision',
        askTitle: bundle == null,
        initial: content,
        initialTitle: result.title.isEmpty ? null : result.title,
        initialSummary: result.summary.isEmpty
            ? 'Imported from a document'
            : result.summary,
      ),
    );
    if (draft == null || !context.mounted) return;
    final session = ref.read(sessionProvider);
    await runWrite(
      context,
      () async {
        final planning = ref.read(planningRepositoryProvider);
        if (bundle == null) {
          await planning.createBeo(
            eventId: eventId,
            title: draft.title!,
            content: draft.content,
            summary: draft.summary,
          );
        } else {
          await planning.proposeRevision(
            beoId: bundle.beoId,
            content: draft.content,
            summary: draft.summary,
            expectedRevision: bundle.latest!.revisionNo,
          );
        }
        ref.invalidate(beoProvider(eventId));
        if (session != null && outcome.menuItems.isNotEmpty) {
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
        }
      },
      success: [
        bundle == null
            ? 'BEO created. It needs approval before it is published.'
            : 'Revision proposed for approval.',
        if (outcome.menuItems.isNotEmpty)
          '${outcome.menuItems.length} menu ${outcome.menuItems.length == 1 ? 'item' : 'items'} added.',
      ].join(' '),
    );
  }

  Future<void> _propose(
    BuildContext context,
    WidgetRef ref,
    BeoBundle bundle,
  ) async {
    final base = bundle.approved?.content ?? bundle.latest!.content;
    final draft = await showDialog<_EditorResult>(
      context: context,
      builder: (_) =>
          _BeoEditorDialog(title: 'Propose revision', initial: base),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref
          .read(planningRepositoryProvider)
          .proposeRevision(
            beoId: bundle.beoId,
            content: draft.content,
            summary: draft.summary,
            expectedRevision: bundle.latest!.revisionNo,
          );
      ref.invalidate(beoProvider(eventId));
    }, success: 'Revision proposed for approval.');
  }

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    BeoRevision revision,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Approve revision ${revision.revisionNo}?'),
        content: const Text(
          'Approving publishes this BEO. Departments affected by a change will have their open tasks flagged for review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
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

  Future<void> _ack(
    BuildContext context,
    WidgetRef ref,
    BeoRevision revision,
    String department,
  ) async {
    await runWrite(context, () async {
      await ref
          .read(planningRepositoryProvider)
          .acknowledgeRevision(revision.id, department);
      ref.invalidate(beoProvider(eventId));
      ref.invalidate(eventSnapshotsProvider);
    }, success: 'Acknowledged for ${Department.fromCode(department).label}.');
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.revision,
    required this.canApprove,
    required this.onApprove,
  });

  final BeoRevision revision;
  final bool canApprove;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OpenRow(
            title: 'Revision ${revision.revisionNo} awaiting approval',
            meta: revision.summary,
            trailing: const Tag('Draft', Tone.neutral),
          ),
          const SizedBox(height: AppSpace.s),
          if (canApprove)
            FilledButton(onPressed: onApprove, child: const Text('Approve'))
          else
            const Text(
              'Only a director can approve BEO revisions.',
              style: AppText.meta,
            ),
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Approved · revision ${revision.revisionNo}',
                style: AppText.rowTitle,
              ),
            ),
            const Tag('Approved', Tone.accent),
          ],
        ),
        const SizedBox(height: 12),
        _Field(label: 'Guests', value: '${c.guests}'),
        _Field(
          label: 'Departments',
          value: c.departments.isEmpty
              ? '—'
              : c.departments.map((d) => d.label).join(', '),
        ),
        if (c.timeline.isNotEmpty) _Field(label: 'Timeline', value: c.timeline),
        if (c.menu.isNotEmpty) _Field(label: 'Menu', value: c.menu),
        if (c.dietary.isNotEmpty) _Field(label: 'Dietary', value: c.dietary),
        if (c.beverage.isNotEmpty) _Field(label: 'Beverage', value: c.beverage),
        if (c.equipment.isNotEmpty)
          _Field(label: 'Equipment', value: c.equipment),
        if (c.specialRequests.isNotEmpty)
          _Field(label: 'Special requests', value: c.specialRequests),
      ],
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(label, style: AppText.meta),
            ),
          ),
          Expanded(child: Text(value, style: AppText.body)),
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
    required this.allowedDepartments,
    required this.canManageEvents,
    required this.onAck,
  });

  final BeoRevision revision;
  final Set<String> acknowledged;
  final bool canAck;
  final Set<String> allowedDepartments;
  final bool canManageEvents;
  final void Function(String department) onAck;

  @override
  Widget build(BuildContext context) {
    final depts = revision.affectedDepartments.map(Department.fromCode).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (depts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Department acknowledgment'),
        for (final d in depts)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Expanded(child: Text(d.label, style: AppText.rowTitle)),
                if (acknowledged.contains(d.code))
                  const Tag('Acknowledged', Tone.accent)
                else if (canAck &&
                    (canManageEvents || allowedDepartments.contains(d.code)))
                  OutlinedButton(
                    onPressed: () => onAck(d.code),
                    child: const Text('Acknowledge'),
                  )
                else
                  const Tag('Pending', Tone.neutral),
              ],
            ),
          ),
      ],
    );
  }
}

class _EditorResult {
  const _EditorResult({
    required this.content,
    required this.summary,
    this.title,
  });

  final BeoContent content;
  final String summary;
  final String? title;
}

class _BeoEditorDialog extends StatefulWidget {
  const _BeoEditorDialog({
    required this.title,
    this.initial,
    this.askTitle = false,
    this.initialTitle,
    this.initialSummary,
  });

  final String title;
  final BeoContent? initial;
  final bool askTitle;

  /// Prefilled BEO title and revision summary, for example from an imported document.
  final String? initialTitle;
  final String? initialSummary;

  @override
  State<_BeoEditorDialog> createState() => _BeoEditorDialogState();
}

class _BeoEditorDialogState extends State<_BeoEditorDialog> {
  late final _beoTitle = TextEditingController(
    text: widget.askTitle ? (widget.initialTitle ?? 'BEO') : '',
  );
  late final _guests = TextEditingController(
    text: '${widget.initial?.guests ?? 0}',
  );
  late final _timeline = TextEditingController(
    text: widget.initial?.timeline ?? '',
  );
  late final _menu = TextEditingController(text: widget.initial?.menu ?? '');
  late final _dietary = TextEditingController(
    text: widget.initial?.dietary ?? '',
  );
  late final _beverage = TextEditingController(
    text: widget.initial?.beverage ?? '',
  );
  late final _equipment = TextEditingController(
    text: widget.initial?.equipment ?? '',
  );
  late final _special = TextEditingController(
    text: widget.initial?.specialRequests ?? '',
  );
  late final _summary = TextEditingController(
    text: widget.initialSummary ?? (widget.askTitle ? 'Initial BEO' : ''),
  );
  late final Set<Department> _departments = {...?widget.initial?.departments};
  String? _error;
  String? _errorField;

  @override
  void dispose() {
    for (final c in [
      _beoTitle,
      _guests,
      _timeline,
      _menu,
      _dietary,
      _beverage,
      _equipment,
      _special,
      _summary,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final guests = int.tryParse(_guests.text.trim());
    if (widget.askTitle && _beoTitle.text.trim().isEmpty) {
      setState(() {
        _errorField = 'title';
        _error = 'Give the BEO a title.';
      });
      return;
    }
    if (guests == null || guests < 0) {
      setState(() {
        _errorField = 'guests';
        _error = 'Guest count must be zero or greater.';
      });
      return;
    }
    if (_summary.text.trim().isEmpty) {
      setState(() {
        _errorField = 'summary';
        _error = 'Describe what changed.';
      });
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
                TextField(
                  controller: _beoTitle,
                  decoration: InputDecoration(
                    labelText: 'BEO title',
                    errorText: _errorField == 'title' ? _error : null,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _guests,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Guests',
                  errorText: _errorField == 'guests' ? _error : null,
                ),
              ),
              const SizedBox(height: 10),
              const Text('Departments affected', style: AppText.meta),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in Department.values)
                    FilterChip(
                      label: Text(d.label),
                      selected: _departments.contains(d),
                      onSelected: (on) => setState(
                        () => on ? _departments.add(d) : _departments.remove(d),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _timeline,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Service timeline',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _menu,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Menu'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dietary,
                decoration: const InputDecoration(
                  labelText: 'Dietary restrictions',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _beverage,
                decoration: const InputDecoration(
                  labelText: 'Beverage service',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _equipment,
                decoration: const InputDecoration(labelText: 'Equipment'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _special,
                decoration: const InputDecoration(
                  labelText: 'Special requests',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _summary,
                decoration: InputDecoration(
                  labelText: 'What changed (required)',
                  errorText: _errorField == 'summary' ? _error : null,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
