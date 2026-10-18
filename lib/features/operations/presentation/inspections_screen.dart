import 'package:flutter/material.dart';

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/app_session.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../application/operations_providers.dart';
import '../data/evidence_storage.dart';
import '../domain/operations.dart';

/// Inspections and checklists: start from a template, complete item by item, then approve.
class InspectionsScreen extends ConsumerWidget {
  const InspectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) {
      return const BackendRequired(title: 'Inspections & Checklists');
    }

    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final eventId = ref.watch(selectedEventIdProvider);

    return PageScaffold(
      kicker: 'Operations',
      title: 'Inspections & Checklists',
      floatingActionButton:
          eventId != null && permissions.contains(AppPermission.runInspections)
          ? FloatingActionButton.extended(
              onPressed: () => _start(context, ref, eventId, session!),
              icon: const PhosphorIcon(PhosphorIconsDuotone.listChecks),
              label: const Text('Start inspection'),
            )
          : null,
      children: [
        const EventPicker(),
        if (eventId != null)
          _Instances(
            eventId: eventId,
            permissions: permissions,
            session: session,
          ),
      ],
    );
  }

  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    String eventId,
    AppSession session,
  ) async {
    final templates = await ref.read(templatesProvider.future);
    if (!context.mounted) return;
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No checklists are available for this venue.'),
        ),
      );
      return;
    }
    final draft = await showDialog<(ChecklistTemplate, String)>(
      context: context,
      builder: (_) => _StartDialog(templates: templates),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref
          .read(operationsRepositoryProvider)
          .createInspection(
            venueId: session.venueId,
            eventId: eventId,
            templateId: draft.$1.id,
            subject: draft.$2,
          );
      ref.invalidate(inspectionsProvider(eventId));
    }, success: 'Inspection started.');
  }
}

class _Instances extends ConsumerWidget {
  const _Instances({
    required this.eventId,
    required this.permissions,
    required this.session,
  });

  final String eventId;
  final Set<AppPermission> permissions;
  final AppSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(inspectionsProvider(eventId));
    final templates = ref.watch(templatesProvider);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.m),
      child: instances.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text('$error'),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyNote('No inspections for this event yet.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final inst in items)
                templates.maybeWhen(
                  data: (list) {
                    final template = list
                        .where((t) => t.id == inst.templateId)
                        .firstOrNull;
                    if (template == null) return const SizedBox.shrink();
                    return _InstanceCard(
                      instance: inst,
                      template: template,
                      canRun: permissions.contains(
                        AppPermission.runInspections,
                      ),
                      canApprove: permissions.contains(
                        AppPermission.reviewInspections,
                      ),
                      onComplete: () => _complete(context, ref, inst, template),
                      onApprove: () => _approve(context, ref, inst),
                    );
                  },
                  orElse: () => const LinearProgressIndicator(),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _complete(
    BuildContext context,
    WidgetRef ref,
    InspectionInstance inst,
    ChecklistTemplate template,
  ) async {
    final responses = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _CompleteDialog(
        template: template,
        storage: ref.read(evidenceStorageProvider),
        venueId: session?.venueId ?? '',
        eventId: eventId,
      ),
    );
    if (responses == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await runWrite(context, () async {
      final failures = await ref
          .read(operationsRepositoryProvider)
          .completeInspection(inst.id, responses);
      ref.invalidate(inspectionsProvider(eventId));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failures == 0
                ? 'Inspection complete. No failures.'
                : 'Inspection complete. $failures failed item(s) opened corrective tasks.',
          ),
        ),
      );
    });
  }

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    InspectionInstance inst,
  ) async {
    final responses = await ref
        .read(operationsRepositoryProvider)
        .listInspectionResponses(inst.id);
    final storage = ref.read(evidenceStorageProvider);
    final photos = await Future.wait([
      for (final row in responses)
        if ((row['photo_url'] as String? ?? '').isNotEmpty)
          storage.viewUrl(row['photo_url'] as String)
        else
          Future.value(''),
    ]);
    if (!context.mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review inspection responses'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var index = 0; index < responses.length; index++)
                ListTile(
                  title: Text(
                    (responses[index]['checklist_items'] as Map?)?['label']
                            as String? ??
                        'Item',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        responses[index]['passed'] == true
                            ? 'Passed'
                            : 'Failed',
                      ),
                      if (responses[index]['numeric_value'] != null)
                        Text('Value: ${responses[index]['numeric_value']}'),
                      if ((responses[index]['text_value'] as String? ?? '')
                          .isNotEmpty)
                        Text(responses[index]['text_value'] as String),
                      if (photos[index].isNotEmpty)
                        Image.network(photos[index], height: 160),
                    ],
                  ),
                ),
            ],
          ),
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
    if (approved != true || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(operationsRepositoryProvider).approveInspection(inst.id);
      ref.invalidate(inspectionsProvider(eventId));
    }, success: 'Inspection approved.');
  }
}

class _InstanceCard extends StatelessWidget {
  const _InstanceCard({
    required this.instance,
    required this.template,
    required this.canRun,
    required this.canApprove,
    required this.onComplete,
    required this.onApprove,
  });

  final InspectionInstance instance;
  final ChecklistTemplate template;
  final bool canRun;
  final bool canApprove;
  final VoidCallback onComplete;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final tone = switch (instance.status) {
      'approved' => Tone.accent,
      'completed' => Tone.accent,
      _ => Tone.neutral,
    };
    final showComplete = instance.status == 'open' && canRun;
    final showApprove = instance.status == 'completed' && canApprove;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.row),
      child: OpenRow(
        title: '${template.name} · ${instance.subject}',
        trailing: Tag(
          instance.status[0].toUpperCase() + instance.status.substring(1),
          tone,
        ),
        meta: '${template.items.length} items',
        below: showComplete || showApprove
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showComplete)
                    FilledButton.tonal(
                      onPressed: onComplete,
                      child: const Text('Complete inspection'),
                    ),
                  if (showApprove)
                    FilledButton(
                      onPressed: onApprove,
                      child: const Text('Review and approve'),
                    ),
                ],
              )
            : null,
      ),
    );
  }
}

class _StartDialog extends StatefulWidget {
  const _StartDialog({required this.templates});

  final List<ChecklistTemplate> templates;

  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  late ChecklistTemplate _template = widget.templates.first;
  final _subject = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Start inspection'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<ChecklistTemplate>(
            initialValue: _template,
            decoration: const InputDecoration(labelText: 'Checklist'),
            items: [
              for (final t in widget.templates)
                DropdownMenuItem(value: t, child: Text(t.name)),
            ],
            onChanged: (v) => setState(() => _template = v ?? _template),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _subject,
            decoration: const InputDecoration(
              labelText: 'Where (suite, bar, room)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_subject.text.trim().isEmpty) return;
            Navigator.pop(context, (_template, _subject.text.trim()));
          },
          child: const Text('Start'),
        ),
      ],
    );
  }
}

class _CompleteDialog extends StatefulWidget {
  const _CompleteDialog({
    required this.template,
    required this.storage,
    required this.venueId,
    required this.eventId,
  });

  final EvidenceStorage storage;
  final String venueId;
  final String eventId;

  final ChecklistTemplate template;

  @override
  State<_CompleteDialog> createState() => _CompleteDialogState();
}

class _CompleteDialogState extends State<_CompleteDialog> {
  late final Map<String, bool?> _passed = {
    for (final i in widget.template.items) i.id: null,
  };
  final Map<String, TextEditingController> _notes = {};
  final Map<String, TextEditingController> _numbers = {};
  final Map<String, String> _photos = {};
  final Set<String> _uploading = {};

  /// Picks one photo for an item and uploads it to the private evidence bucket.
  Future<void> _addPhoto(String itemId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (file == null) return;
      setState(() => _uploading.add(itemId));
      final Uint8List bytes = await file.readAsBytes();
      final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
      final path = await widget.storage.upload(
        venueId: widget.venueId,
        eventId: widget.eventId,
        bytes: bytes,
        extension: ext,
      );
      if (!mounted) return;
      setState(() => _photos[itemId] = path);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : 'The photo could not be added.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading.remove(itemId));
    }
  }

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    for (final c in _numbers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final responses = <Map<String, dynamic>>[];
    for (final item in widget.template.items) {
      final value = _passed[item.id];
      if (value == null) continue;
      responses.add({
        'item_id': item.id,
        'passed': value,
        'numeric_value': item.responseType == 'numeric'
            ? num.tryParse(_numbers[item.id]?.text.trim() ?? '')
            : null,
        'text_value': _notes[item.id]?.text.trim() ?? '',
        'photo_url': _photos[item.id] ?? '',
      });
    }
    if (responses.length != widget.template.items.length ||
        widget.template.items.any(
          (item) =>
              (item.responseType == 'numeric' &&
                  num.tryParse(_numbers[item.id]?.text.trim() ?? '') == null) ||
              (item.responseType == 'text' &&
                  (_notes[item.id]?.text.trim().isEmpty ?? true)) ||
              (item.responseType == 'photo' && !_photos.containsKey(item.id)),
        )) {
      return;
    }
    Navigator.pop(context, responses);
  }

  @override
  Widget build(BuildContext context) {
    final unanswered = widget.template.items
        .where(
          (item) =>
              _passed[item.id] == null ||
              (item.responseType == 'numeric' &&
                  num.tryParse(_numbers[item.id]?.text.trim() ?? '') == null) ||
              (item.responseType == 'text' &&
                  (_notes[item.id]?.text.trim().isEmpty ?? true)) ||
              (item.responseType == 'photo' && !_photos.containsKey(item.id)),
        )
        .length;
    return AlertDialog(
      title: Text(widget.template.name),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in widget.template.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: AppText.rowTitle.copyWith(fontSize: 17),
                      ),
                      if (item.requiresManagerApproval)
                        const Text(
                          'Needs manager approval',
                          style: AppText.meta,
                        ),
                      const SizedBox(height: 8),
                      if (item.responseType == 'numeric')
                        TextField(
                          controller: _numbers.putIfAbsent(
                            item.id,
                            () => TextEditingController(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Measured value',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      if (item.responseType == 'text')
                        TextField(
                          controller: _notes.putIfAbsent(
                            item.id,
                            () => TextEditingController(),
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Response',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        emptySelectionAllowed: true,
                        segments: [
                          ButtonSegment(
                            value: true,
                            label: Text(
                              item.responseType == 'yes_no' ? 'Yes' : 'Pass',
                              softWrap: false,
                              maxLines: 1,
                            ),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text(
                              item.responseType == 'yes_no' ? 'No' : 'Fail',
                              softWrap: false,
                              maxLines: 1,
                            ),
                          ),
                        ],
                        selected: {?_passed[item.id]},
                        // Only one segment is selected at a time, so the selected fill follows
                        // the answer: accent for a pass, accent2 for a fail.
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => !states.contains(WidgetState.selected)
                                ? Colors.transparent
                                : _passed[item.id] == false
                                ? AppColors.accent2
                                : AppColors.accent,
                          ),
                        ),
                        onSelectionChanged: (selection) {
                          if (selection.isEmpty) return;
                          setState(() => _passed[item.id] = selection.first);
                        },
                      ),
                      if (_passed[item.id] == false &&
                          item.responseType != 'text') ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _notes.putIfAbsent(
                            item.id,
                            () => TextEditingController(),
                          ),
                          decoration: const InputDecoration(
                            labelText: 'What failed? (opens a corrective task)',
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _uploading.contains(item.id)
                                ? null
                                : () => _addPhoto(item.id),
                            icon: const PhosphorIcon(
                              PhosphorIconsDuotone.camera,
                              size: 18,
                            ),
                            label: Text(
                              _uploading.contains(item.id)
                                  ? 'Uploading…'
                                  : _photos.containsKey(item.id)
                                  ? 'Photo added (replace)'
                                  : 'Add photo',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (unanswered > 0)
                Text(
                  '$unanswered item(s) still need their required response.',
                  style: const TextStyle(color: AppColors.accent2700),
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
        FilledButton(
          onPressed: unanswered == 0 ? _submit : null,
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
