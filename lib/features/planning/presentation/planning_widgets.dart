import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/venue_time.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../auth/application/session_controller.dart';
import '../../events/application/event_providers.dart';
import '../../events/domain/ops_event.dart';
import '../application/planning_providers.dart';

/// Shown in demo mode for features that need the database.
class BackendRequired extends StatelessWidget {
  const BackendRequired({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      kicker: 'Demo mode',
      title: title,
      children: const [
        EmptyNote(
          'This section needs a live Supabase connection. Demo mode has sample events only.',
        ),
      ],
    );
  }
}

/// Event selector shared by planning screens. Lists events that are not closed or cancelled.
class EventPicker extends ConsumerWidget {
  const EventPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(eventSnapshotsProvider);
    final zone = ref.watch(sessionProvider)?.timeZone ?? 'UTC';
    return snapshots.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('$error'),
      data: (items) {
        final events = items
            .map((s) => s.event)
            .where(
              (e) =>
                  e.status != EventStatus.closed &&
                  e.status != EventStatus.cancelled,
            )
            .toList();
        if (events.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(bottom: AppSpace.l),
            child: EmptyNote(
              'No open events yet. Create one in the Event Workspace.',
            ),
          );
        }
        final selected = ref.watch(selectedEventIdProvider);
        final current = events.any((e) => e.id == selected)
            ? selected!
            : events.first.id;
        if (current != selected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedEventIdProvider.notifier).select(current);
          });
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.l),
          child: DropdownButtonFormField<String>(
            initialValue: current,
            decoration: const InputDecoration(labelText: 'Event'),
            items: [
              for (final e in events)
                DropdownMenuItem(
                  value: e.id,
                  child: Text(
                    '${e.name} · ${DateFormat('MMM d, h:mm a').format(atVenue(e.serviceStart, zone))} $zone',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) =>
                ref.read(selectedEventIdProvider.notifier).select(value),
          ),
        );
      },
    );
  }
}

/// Runs a write, shows a friendly error, and returns whether it succeeded.
Future<bool> runWrite(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null && context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    }
    return false;
  }
}

/// Date then time picker. Returns null if cancelled.
Future<DateTime?> pickDateTime(
  BuildContext context,
  DateTime initial, {
  String timeZone = 'UTC',
}) async {
  final wall = atVenue(initial, timeZone);
  final date = await showDatePicker(
    context: context,
    initialDate: wall,
    firstDate: atVenue(
      DateTime.now().subtract(const Duration(days: 30)),
      timeZone,
    ),
    lastDate: atVenue(DateTime.now().add(const Duration(days: 730)), timeZone),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(wall),
  );
  if (time == null) return null;
  return venueWallTimeUtc(
    DateTime.utc(date.year, date.month, date.day, time.hour, time.minute),
    timeZone,
  );
}

/// True when the app has a backend. Planning screens check this before reading.
bool get backendAvailable => AppConfig.hasSupabase;
