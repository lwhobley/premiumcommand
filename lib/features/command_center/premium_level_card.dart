import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../planning/application/planning_providers.dart';
import '../staffing/domain/staffing.dart';
import '../suites/domain/suite.dart';
import '../suites/presentation/suite_map_section.dart';
import '../suites/presentation/suite_map_view.dart';

/// The premium level, always shown on the Command Center. With an event, suites are colored by
/// their live state and staff placed in premium spaces are listed beneath. Without one, the map
/// is shown plain. Tapping a suite or club opens its panel for the event.
class PremiumLevelCard extends ConsumerWidget {
  const PremiumLevelCard({
    super.key,
    required this.venueId,
    required this.eventId,
    required this.heading,
  });

  final String venueId;

  /// The event the map shows, or null to show the map without event status.
  final String? eventId;

  /// The line under the title, such as "Now: Disney On Ice" or "Next: Disney On Ice".
  final String heading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = eventId;
    final assignments = id == null
        ? const <SuiteAssignment>[]
        : ref.watch(suitesProvider(id)).value ?? const <SuiteAssignment>[];
    final staff = id == null
        ? const <StaffPosition>[]
        : ref.watch(staffProvider(id)).value ?? const <StaffPosition>[];

    final colors = <String, Color>{};
    for (final a in assignments) {
      final area = a.planArea;
      if (area != null) colors[area] = suiteStateColor(a.state);
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
        Text('Premium level', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          heading,
          style: const TextStyle(color: AppColors.charcoalMuted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final entry in {
              'Ready or in service': suiteStateColor(SuiteState.ready),
              'Setup or closing': suiteStateColor(SuiteState.setupInProgress),
              'Not started': suiteStateColor(SuiteState.notStarted),
              'Not in this event': SuiteMapStatus.unassigned.color,
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
              onSuiteTap: (area) {
                if (id == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Add an event to see suite and club status and orders.',
                      ),
                    ),
                  );
                  return;
                }
                showSuitePanel(
                  context,
                  venueId: venueId,
                  eventId: id,
                  areaId: area,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (id != null && assignments.isEmpty)
          const Text(
            'No suites or clubs are assigned to this event yet. Add them under Premium Spaces.',
            style: TextStyle(color: AppColors.charcoalMuted),
          )
        else if (id != null) ...[
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
      ],
    );
  }
}
