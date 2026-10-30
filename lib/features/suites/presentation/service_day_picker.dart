import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../application/service_day_providers.dart';

/// "Fri Oct 30".
String serviceDayLabel(DateTime day) => DateFormat('EEE MMM d').format(day);

/// Day chips for an event that runs more than one day. Hidden for a single-day event.
class ServiceDayPicker extends ConsumerWidget {
  const ServiceDayPicker({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(eventServiceDaysProvider(eventId));
    if (days.length < 2) return const SizedBox.shrink();
    final selected = ref.watch(selectedServiceDayProvider(eventId));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Day', style: AppText.meta),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final day in days)
                ChoiceChip(
                  label: Text(serviceDayLabel(day)),
                  selected: day == selected,
                  onSelected: (_) => ref
                      .read(selectedServiceDayProvider(eventId).notifier)
                      .select(day),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
