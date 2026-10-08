import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/session_controller.dart';
import '../application/event_providers.dart';
import '../domain/ops_event.dart';

class EventCreateScreen extends ConsumerStatefulWidget {
  const EventCreateScreen({super.key});

  @override
  ConsumerState<EventCreateScreen> createState() => _EventCreateScreenState();
}

class _EventCreateScreenState extends ConsumerState<EventCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _manager = TextEditingController();
  final _guests = TextEditingController(text: '0');
  final _notes = TextEditingController();
  EventType _type = EventType.custom;
  DateTime _start = DateTime.now().add(const Duration(days: 7));
  Duration _duration = const Duration(hours: 4);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _manager.dispose();
    _guests.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null) return;
    setState(() {
      _start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final venueId = ref.read(sessionProvider)?.venueId ?? '';
      final created = await ref.read(eventActionsProvider).createEvent(
            OpsEvent(
              id: '',
              venueId: venueId,
              name: _name.text.trim(),
              type: _type,
              serviceStart: _start,
              serviceEnd: _start.add(_duration),
              guaranteedGuests: int.tryParse(_guests.text.trim()) ?? 0,
              managerName: _manager.text.trim(),
              status: EventStatus.draft,
              notes: _notes.text.trim(),
            ),
          );
      if (mounted) context.go('/events/${created.id}');
    } catch (error) {
      setState(() => _error = userMessageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEE MMM d, y · h:mm a').format(_start);
    return Scaffold(
      appBar: AppBar(title: const Text('New event')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Event name'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Enter an event name.' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<EventType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Event type'),
              items: [
                for (final type in EventType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickStart,
              icon: const Icon(Icons.schedule),
              label: Align(alignment: Alignment.centerLeft, child: Text('Service start: $dateLabel')),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Duration>(
              initialValue: _duration,
              decoration: const InputDecoration(labelText: 'Service length'),
              items: const [
                DropdownMenuItem(value: Duration(hours: 2), child: Text('2 hours')),
                DropdownMenuItem(value: Duration(hours: 3), child: Text('3 hours')),
                DropdownMenuItem(value: Duration(hours: 4), child: Text('4 hours')),
                DropdownMenuItem(value: Duration(hours: 6), child: Text('6 hours')),
              ],
              onChanged: (value) => setState(() => _duration = value ?? _duration),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _guests,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Guaranteed guests'),
              validator: (value) =>
                  int.tryParse(value?.trim() ?? '') == null ? 'Enter a whole number.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _manager,
              decoration: const InputDecoration(labelText: 'Event manager'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Operational notes'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Creating…' : 'Create event'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.blocked)),
            ],
          ],
        ),
      ),
    );
  }
}
