import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../../events/domain/readiness.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../../staff/application/staff_providers.dart';
import '../../staff/domain/staff_availability.dart';
import '../../suites/domain/suite.dart';
import '../domain/staffing.dart';

/// Colors for availability in the directory.
Color availabilityColor(AvailabilityStatus status) => switch (status) {
  AvailabilityStatus.available => AppColors.ready,
  AvailabilityStatus.limited => AppColors.attention,
  AvailabilityStatus.unavailable => AppColors.blocked,
};

/// Everyone in the venue's staff directory, with availability right now and, when an event is
/// selected, the position they hold on it. Read-only for people without deploy_staff.
class StaffDirectoryPanel extends ConsumerWidget {
  const StaffDirectoryPanel({
    super.key,
    required this.venueId,
    required this.eventId,
    required this.canManage,
  });

  final String venueId;
  final String? eventId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directory = ref.watch(staffDirectoryProvider(venueId));
    final availability =
        ref.watch(staffAvailabilityProvider(venueId)).value ?? const [];
    final positions = eventId == null
        ? const <StaffPosition>[]
        : ref.watch(staffProvider(eventId!)).value ?? const <StaffPosition>[];
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Directory', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            canManage ? 'Tap a person to record availability.' : 'Availability and current assignments. Only managers can change them.',
            style: const TextStyle(
              color: AppColors.charcoalMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          directory.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text(error.toString()),
            data: (people) {
              if (people.isEmpty) {
                return const Text(
                  'No staff accounts yet.',
                  style: TextStyle(color: AppColors.charcoalMuted),
                );
              }
              return Column(
                children: [
                  for (final person in people)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        leading: CircleAvatar(child: Text(person.initials)),
                        title: Text(person.fullName),
                        subtitle: Text(_subtitle(person, positions)),
                        trailing: StatusChip(
                          label: availabilityAt(
                            availability,
                            person.userId,
                            now,
                          ).label,
                          color: availabilityColor(
                            availabilityAt(availability, person.userId, now),
                          ),
                        ),
                        onTap: canManage && person.active
                            ? () => _recordAvailability(context, ref, person)
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _subtitle(StaffDirectoryEntry person, List<StaffPosition> positions) {
    final department =
        Department.values
            .where((d) => d.code == person.department)
            .map((d) => d.label)
            .firstOrNull ??
        person.department;
    final position = positions
        .where((p) => p.userId == person.userId)
        .firstOrNull;
    final where = position == null
        ? 'Not assigned on this event'
        : [
            if (position.roleLabel.isNotEmpty) position.roleLabel,
            if (position.suiteAssignmentId != null) 'Premium space',
            if (position.zone.isNotEmpty) 'Zone ${position.zone}',
            if (position.station.isNotEmpty) position.station,
          ].join(' · ');
    return '$department${person.jobTitle.isEmpty ? '' : ' · ${person.jobTitle}'}\n$where';
  }

  Future<void> _recordAvailability(
    BuildContext context,
    WidgetRef ref,
    StaffDirectoryEntry person,
  ) async {
    final draft = await showDialog<AvailabilityDraft>(
      context: context,
      builder: (_) => _AvailabilityDialog(name: person.fullName),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(
      context,
      () async {
        await ref
            .read(staffRepositoryProvider)
            .addAvailability(
              venueId: venueId,
              userId: person.userId,
              status: draft.status,
              startsAt: draft.startsAt,
              endsAt: draft.endsAt,
              note: draft.note,
            );
        ref.invalidate(staffAvailabilityProvider(venueId));
      },
      success:
          '${person.fullName} is now ${draft.status.label.toLowerCase()} for that time.',
    );
  }
}

class AvailabilityDraft {
  const AvailabilityDraft({
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.note,
  });

  final AvailabilityStatus status;
  final DateTime startsAt;
  final DateTime endsAt;
  final String note;
}

class _AvailabilityDialog extends StatefulWidget {
  const _AvailabilityDialog({required this.name});

  final String name;

  @override
  State<_AvailabilityDialog> createState() => _AvailabilityDialogState();
}

class _AvailabilityDialogState extends State<_AvailabilityDialog> {
  AvailabilityStatus _status = AvailabilityStatus.unavailable;
  late DateTime _start = DateTime.now();
  late DateTime _end = DateTime.now().add(const Duration(hours: 8));
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final date = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start ? _start : _end),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() => start ? _start = value : _end = value);
  }

  void _save() {
    if (!_end.isAfter(_start)) {
      return setState(
        () => _error = 'The end time must be after the start time.',
      );
    }
    Navigator.of(context).pop(
      AvailabilityDraft(
        status: _status,
        startsAt: _start,
        endsAt: _end,
        note: _note.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('EEE MMM d, h:mm a');
    return AlertDialog(
      title: Text('${widget.name} availability'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<AvailabilityStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                for (final s in AvailabilityStatus.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (value) => setState(() => _status = value ?? _status),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('From'),
              subtitle: Text(format.format(_start)),
              trailing: TextButton(
                onPressed: () => _pick(true),
                child: const Text('Change'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Until'),
              subtitle: Text(format.format(_end)),
              trailing: TextButton(
                onPressed: () => _pick(false),
                child: const Text('Change'),
              ),
            ),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.blocked)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Where a person is placed: a premium space, or a department, zone, and station elsewhere.
class PlaceChoice {
  const PlaceChoice({
    this.suiteAssignmentId,
    this.department,
    this.zone = '',
    this.station = '',
  });

  final String? suiteAssignmentId;
  final String? department;
  final String zone;
  final String station;
}

/// Chooses a place for the person. Any department is allowed, so staff can cover outside their own.
Future<PlaceChoice?> showPlaceDialog(
  BuildContext context, {
  required List<SuiteAssignment> premiumSpaces,
}) {
  return showDialog<PlaceChoice>(
    context: context,
    builder: (_) => _PlaceDialog(premiumSpaces: premiumSpaces),
  );
}

class _PlaceDialog extends StatefulWidget {
  const _PlaceDialog({required this.premiumSpaces});

  final List<SuiteAssignment> premiumSpaces;

  @override
  State<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<_PlaceDialog> {
  bool _premium = true;
  String? _suiteId;
  Department _department = Department.operations;
  final _zone = TextEditingController();
  final _station = TextEditingController();

  @override
  void initState() {
    super.initState();
    _suiteId = widget.premiumSpaces.isEmpty
        ? null
        : widget.premiumSpaces.first.id;
  }

  @override
  void dispose() {
    _zone.dispose();
    _station.dispose();
    super.dispose();
  }

  void _save() {
    if (_premium) {
      if (_suiteId == null) return;
      // Premium spaces belong to the suites department.
      return Navigator.of(context).pop(
        PlaceChoice(
          suiteAssignmentId: _suiteId,
          department: Department.suites.code,
        ),
      );
    }
    Navigator.of(context).pop(
      PlaceChoice(
        department: _department.code,
        zone: _zone.text.trim(),
        station: _station.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Where?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Premium space')),
                ButtonSegment(value: false, label: Text('Other area')),
              ],
              selected: {_premium},
              onSelectionChanged: (s) => setState(() => _premium = s.first),
            ),
            const SizedBox(height: 12),
            if (_premium)
              widget.premiumSpaces.isEmpty
                  ? const Text(
                      'No premium spaces are assigned to this event yet. Add one under Premium Spaces first.',
                      style: TextStyle(color: AppColors.charcoalMuted),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: _suiteId,
                      decoration: const InputDecoration(
                        labelText: 'Premium space',
                      ),
                      items: [
                        for (final s in widget.premiumSpaces)
                          DropdownMenuItem(
                            value: s.id,
                            child: Text(s.suiteName),
                          ),
                      ],
                      onChanged: (value) => setState(() => _suiteId = value),
                    )
            else ...[
              DropdownButtonFormField<Department>(
                initialValue: _department,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  helperText:
                      'Any department, including outside the person’s own.',
                ),
                items: [
                  for (final d in Department.values)
                    DropdownMenuItem(value: d, child: Text(d.label)),
                ],
                onChanged: (value) =>
                    setState(() => _department = value ?? _department),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _zone,
                decoration: const InputDecoration(labelText: 'Zone (optional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _station,
                decoration: const InputDecoration(
                  labelText: 'Station (optional)',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Assign')),
      ],
    );
  }
}
