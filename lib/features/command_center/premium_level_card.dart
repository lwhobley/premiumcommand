import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/broadsheet.dart';
import '../planning/application/planning_providers.dart';
import '../staffing/domain/staffing.dart';
import '../suites/domain/premium_level_layout.dart';
import '../suites/domain/suite.dart';
import '../suites/presentation/suite_map_section.dart';
import '../suites/presentation/suite_map_view.dart';

/// The premium level, always shown on the Command Center. With an event, suites are colored by
/// their live state and staff placed in premium spaces are listed beneath. Without one, the map
/// is shown plain. Tapping a suite, club, or the arena floor opens its panel for the event.
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

    final byArea = {
      for (final a in assignments)
        if (a.planArea != null) a.planArea!: a,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Premium level'),
        Text(heading, style: AppText.meta),
        const SizedBox(height: 12),
        // One cell per suite, colored by its state. Opens Premium Spaces.
        Semantics(
          button: true,
          label: 'Open Premium Spaces',
          child: InkWell(
            onTap: () => context.go('/spaces'),
            borderRadius: AppRadius.all,
            child: SizedBox(
              height: AppSpace.minTap,
              child: Row(
                children: [
                  for (final (i, suite) in premiumLevelSuites.indexed) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      child: Tooltip(
                        message: byArea[suite.number] == null
                            ? 'S${suite.number} · not in this event'
                            : 'S${suite.number} · ${byArea[suite.number]!.state.label}',
                        child: Container(
                          decoration: BoxDecoration(
                            color: byArea[suite.number] == null
                                ? SuiteMapStatus.unassigned.color
                                : suiteStateColor(byArea[suite.number]!.state),
                            borderRadius: AppRadius.all,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final state in SuiteState.values)
              _Swatch(color: suiteStateColor(state), label: state.label),
            _Swatch(
              color: SuiteMapStatus.unassigned.color,
              label: 'Not in this event',
            ),
          ],
        ),
        const SizedBox(height: AppSpace.l),
        ClipRRect(
          borderRadius: AppRadius.all,
          child: SizedBox(
            height: 360,
            child: SuiteMapView(
              sceneData: buildSuiteColorScene(
                colors,
                labels: mapLabelsFor(
                  ref.watch(venueSuitesProvider(venueId)).value ?? const [],
                ),
              ),
              onSuiteTap: (area) {
                if (id == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Add an event to see status and orders.'),
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
        const SizedBox(height: AppSpace.m),
        if (id != null && assignments.isEmpty)
          const Text(
            'Nothing on the premium level is assigned to this event yet. Add spaces under Premium Spaces.',
            style: AppText.meta,
          )
        else if (id != null) ...[
          Text(
            onSuites.isEmpty
                ? 'No staff placed in a premium space yet.'
                : 'Staff in premium spaces',
            style: onSuites.isEmpty
                ? AppText.meta
                : const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: AppRadius.all),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppText.meta),
      ],
    );
  }
}
