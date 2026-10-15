import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../planning/application/planning_providers.dart';
import '../suites/domain/premium_level_layout.dart';
import '../suites/domain/suite.dart';
import '../suites/presentation/suite_map_section.dart';
import '../suites/presentation/suite_map_view.dart';

/// The premium level for the active event, colored by each suite's live state. Staff placed
/// in a premium space are listed beneath it. Tapping a suite opens its panel.
class PremiumLevelCard extends ConsumerWidget {
  const PremiumLevelCard({
    super.key,
    required this.venueId,
    required this.eventId,
    required this.eventName,
  });

  final String venueId;
  final String eventId;
  final String eventName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suites = ref.watch(suitesProvider(eventId));
    final staff = ref.watch(staffProvider(eventId)).value ?? const [];

    return suites.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('$error'),
      data: (assignments) {
        if (assignments.isEmpty) {
          return Text(
            'No premium spaces are assigned to $eventName yet.',
            style: const TextStyle(color: AppColors.charcoalMuted),
          );
        }
        final colors = <String, Color>{};
        for (final a in assignments) {
          final number = planSuiteNumber(a.suiteName);
          if (number != null) colors[number] = suiteStateColor(a.state);
        }
        final byId = {for (final a in assignments) a.id: a};
        final onSuites = [
          for (final person in staff)
            if (person.suiteAssignmentId != null &&
                byId[person.suiteAssignmentId] != null)
              (
                suite: byId[person.suiteAssignmentId]!.suiteName,
                name: person.displayName,
                role: person.roleLabel,
              ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Premium level',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              eventName,
              style: const TextStyle(
                color: AppColors.charcoalMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final entry in {
                  'Ready or in service': suiteStateColor(SuiteState.ready),
                  'Setup or closing': suiteStateColor(
                    SuiteState.setupInProgress,
                  ),
                  'Not started': suiteStateColor(SuiteState.notStarted),
                  'Closed': suiteStateColor(SuiteState.closed),
                }.entries)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: entry.value,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(entry.key, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 360,
                child: SuiteMapView(
                  sceneData: buildSuiteColorScene(colors),
                  onSuiteTap: (number) => showSuitePanel(
                    context,
                    venueId: venueId,
                    eventId: eventId,
                    suiteNumber: number,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              onSuites.isEmpty
                  ? 'No staff placed in a premium space yet.'
                  : 'Staff in premium spaces',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final person in onSuites)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${person.suite} · ${person.name}'
                  '${person.role.isEmpty ? '' : ' (${person.role})'}',
                ),
              ),
          ],
        );
      },
    );
  }
}
