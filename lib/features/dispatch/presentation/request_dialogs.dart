import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../events/domain/readiness.dart';
import '../data/dispatch_repository.dart';
import '../domain/service_request.dart';

/// Collects a new request. The client id is created once per sheet so a retry cannot duplicate it.
Future<ServiceRequestDraft?> showNewRequestDialog(BuildContext context) {
  return showModalBottomSheet<ServiceRequestDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _NewRequestDialog(),
  );
}

class _NewRequestDialog extends StatefulWidget {
  const _NewRequestDialog();

  @override
  State<_NewRequestDialog> createState() => _NewRequestDialogState();
}

class _NewRequestDialogState extends State<_NewRequestDialog> {
  final _clientRequestId = newClientRequestId();
  final _location = TextEditingController();
  final _description = TextEditingController();
  RequestCategory _category = RequestCategory.guestAssistance;
  RequestPriority _priority = RequestPriority.normal;
  String? _error;

  @override
  void dispose() {
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (_description.text.trim().isEmpty) {
      setState(() => _error = 'Describe what is needed.');
      return;
    }
    Navigator.of(context).pop(
      ServiceRequestDraft(
        clientRequestId: _clientRequestId,
        category: _category,
        location: _location.text.trim(),
        description: _description.text.trim(),
        priority: _priority,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screen,
            0,
            AppSpace.screen,
            AppSpace.l,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New service request', style: AppText.sectionHeading),
              const SizedBox(height: AppSpace.m),
              const Text('Category', style: AppText.meta),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in RequestCategory.values)
                    ChoiceChip(
                      label: Text(c.label),
                      selected: _category == c,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.m),
              TextField(
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'Location (suite, club, bar, pickup point)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'What is needed',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: AppSpace.m),
              const Text('Priority', style: AppText.meta),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<RequestPriority>(
                  showSelectedIcon: false,
                  segments: [
                    for (final p in RequestPriority.values)
                      ButtonSegment(
                        value: p,
                        label: Text(p.label, softWrap: false, maxLines: 1),
                      ),
                  ],
                  selected: {_priority},
                  onSelectionChanged: (value) =>
                      setState(() => _priority = value.first),
                ),
              ),
              const SizedBox(height: AppSpace.l),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpace.s),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Create request'),
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

/// Asks for a department to assign the request to. Returns null if cancelled.
Future<Department?> showAssignDialog(BuildContext context) {
  return showDialog<Department>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Assign to department'),
      children: [
        for (final dept in Department.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(dept),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(dept.label),
            ),
          ),
      ],
    ),
  );
}

/// Requires a non-empty reason before a block, reject, or cancel. Returns null if dismissed.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(title: title),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _reason.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'A reason is required.');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _reason,
        autofocus: true,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(labelText: 'Reason', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Confirm')),
      ],
    );
  }
}
