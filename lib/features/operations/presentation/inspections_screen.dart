import 'package:flutter/material.dart';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
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
    if (!backendAvailable) return const BackendRequired(title: 'Inspections & Checklists');

    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final eventId = ref.watch(selectedEventIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Inspections & Checklists')),
      floatingActionButton: eventId != null && permissions.contains(AppPermission.runInspections)
          ? FloatingActionButton.extended(
              onPressed: () => _start(context, ref, eventId, session!),
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('Start inspection'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const EventPicker(),
          if (eventId != null) _Instances(eventId: eventId, permissions: permissions, session: session),
        ],
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref, String eventId, AppSession session) async {
    final templates = await ref.read(templatesProvider.future);
    if (!context.mounted) return;
    final draft = await showDialog<(ChecklistTemplate, String)>(
      context: context,
      builder: (_) => _StartDialog(templates: templates),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(operationsRepositoryProvider).createInspection(
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
  const _Instances({required this.eventId, required this.permissions, required this.session});

  final String eventId;
  final Set<AppPermission> permissions;
  final AppSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(inspectionsProvider(eventId));
    final templates = ref.watch(templatesProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: instances.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text('$error'),
        data: (items) {
          if (items.isEmpty) {
            return const Text('No inspections for this event yet.', style: TextStyle(color: AppColors.charcoalMuted));
          }
          return Column(
            children: [
              for (final inst in items)
                templates.maybeWhen(
                  data: (list) {
                    final template = list.where((t) => t.id == inst.templateId).firstOrNull;
                    if (template == null) return const SizedBox.shrink();
                    return _InstanceCard(
                      instance: inst,
                      template: template,
                      canRun: permissions.contains(AppPermission.runInspections),
                      canApprove: permissions.contains(AppPermission.reviewInspections),
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

  Future<void> _complete(BuildContext context, WidgetRef ref, InspectionInstance inst, ChecklistTemplate template) async {
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
      final failures = await ref.read(operationsRepositoryProvider).completeInspection(inst.id, responses);
      ref.invalidate(inspectionsProvider(eventId));
      messenger.showSnackBar(SnackBar(content: Text(failures == 0
          ? 'Inspection complete. No failures.'
          : 'Inspection complete. $failures failed item(s) opened corrective tasks.')));
    });
  }

  Future<void> _approve(BuildContext context, WidgetRef ref, InspectionInstance inst) async {
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
    final color = switch (instance.status) {
      'approved' => AppColors.ready,
      'completed' => AppColors.inProgress,
      _ => AppColors.attention,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('${template.name} · ${instance.subject}',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              StatusChip(label: instance.status[0].toUpperCase() + instance.status.substring(1), color: color),
            ]),
            const SizedBox(height: 4),
            Text('${template.items.length} items', style: const TextStyle(color: AppColors.charcoalMuted, fontSize: 13)),
            const SizedBox(height: 8),
            if (instance.status == 'open' && canRun)
              FilledButton.tonal(onPressed: onComplete, child: const Text('Complete inspection')),
            if (instance.status == 'completed' && canApprove)
              FilledButton(onPressed: onApprove, child: const Text('Approve')),
          ],
        ),
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
            items: [for (final t in widget.templates) DropdownMenuItem(value: t, child: Text(t.name))],
            onChanged: (v) => setState(() => _template = v ?? _template),
          ),
          const SizedBox(height: 10),
          TextField(controller: _subject, decoration: const InputDecoration(labelText: 'Where (suite, bar, room)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
  late final Map<String, bool?> _passed = {for (final i in widget.template.items) i.id: null};
  final Map<String, TextEditingController> _notes = {};
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
      messenger.showSnackBar(SnackBar(content: Text(error is StateError ? error.message : 'The photo could not be added.')));
    } finally {
      if (mounted) setState(() => _uploading.remove(itemId));
    }
  }

  @override
  void dispose() {
    for (final c in _notes.values) {
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
        'text_value': _notes[item.id]?.text.trim() ?? '',
        'photo_url': _photos[item.id] ?? '',
      });
    }
    if (responses.length != widget.template.items.length) return;
    Navigator.pop(context, responses);
  }

  @override
  Widget build(BuildContext context) {
    final unanswered = _passed.values.where((v) => v == null).length;
    return AlertDialog(
      title: Text(widget.template.name),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in widget.template.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (item.requiresManagerApproval)
                        const Text('Needs manager approval', style: TextStyle(color: AppColors.attention, fontSize: 12)),
                      Row(children: [
                        ChoiceChip(
                          label: const Text('Pass'),
                          selected: _passed[item.id] == true,
                          onSelected: (_) => setState(() => _passed[item.id] = true),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Fail'),
                          selected: _passed[item.id] == false,
                          onSelected: (_) => setState(() => _passed[item.id] = false),
                        ),
                      ]),
                      if (_passed[item.id] == false)
                        TextField(
                          controller: _notes.putIfAbsent(item.id, () => TextEditingController()),
                          decoration: const InputDecoration(labelText: 'What failed? (opens a corrective task)'),
                        ),
                      const SizedBox(height: 6),
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: _uploading.contains(item.id) ? null : () => _addPhoto(item.id),
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: Text(_uploading.contains(item.id)
                              ? 'Uploading…'
                              : _photos.containsKey(item.id)
                                  ? 'Photo added (replace)'
                                  : 'Add photo'),
                        ),
                      ]),
                    ],
                  ),
                ),
              if (unanswered > 0)
                Text('$unanswered item(s) still need a response.',
                    style: const TextStyle(color: AppColors.blocked)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: unanswered == 0 ? _submit : null, child: const Text('Submit')),
      ],
    );
  }
}
