import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../application/floor_plan_providers.dart';
import '../data/floor_plan_pdf.dart';
import '../domain/floor_plan.dart';
import 'floor_plan_3d_view.dart';

/// Read-only 3D preview of an event's assigned space(s). Occupancy follows the
/// approved BEO's guest count when there is one (the number banquet and culinary
/// are actually staffing to), falling back to the event's guaranteed guests.
/// Shows nothing if there's no backend, or no assigned space has a saved floor plan yet.
class EventFloorPlanCard extends ConsumerWidget {
  const EventFloorPlanCard({
    super.key,
    required this.eventId,
    required this.guaranteedGuests,
  });

  final String eventId;
  final int guaranteedGuests;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) return const SizedBox.shrink();
    final plansAsync = ref.watch(eventFloorPlansProvider(eventId));
    final beoAsync = ref.watch(beoProvider(eventId));
    final session = ref.watch(sessionProvider);
    final spaces = session == null
        ? const <VenueSpace>[]
        : ref.watch(venueSpacesProvider(session.venueId)).value ??
              const <VenueSpace>[];

    return plansAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (plans) {
        if (plans.isEmpty) return const SizedBox.shrink();

        final approvedBeoGuests = beoAsync.maybeWhen(
          data: (bundle) => bundle?.approved?.content.guests,
          orElse: () => null,
        );
        final effectiveGuests = approvedBeoGuests ?? guaranteedGuests;
        final guestsDiffer =
            approvedBeoGuests != null && approvedBeoGuests != guaranteedGuests;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading('Room preview'),
            Text(
              approvedBeoGuests != null
                  ? 'Showing $effectiveGuests guests from the approved BEO.'
                  : 'Showing $effectiveGuests guaranteed guests. No approved BEO yet.',
              style: AppText.meta,
            ),
            if (guestsDiffer)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'The approved BEO ($approvedBeoGuests guests) does not match the event\'s '
                  'guaranteed guests ($guaranteedGuests). Using the BEO count.',
                  style: AppText.meta.copyWith(color: AppColors.accent2700),
                ),
              ),
            const SizedBox(height: 8),
            for (final plan in plans) ...[
              _CapacityWarning(plan: plan, guestCount: effectiveGuests),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => shareFloorPlanPdf(
                    spaceName:
                        spaces
                            .where((s) => s.id == plan.venueSpaceId)
                            .firstOrNull
                            ?.name ??
                        'Room',
                    plan: plan,
                    venueName: session?.venueName,
                  ),
                  icon: const PhosphorIcon(PhosphorIconsDuotone.filePdf),
                  label: const Text('Export floor plan PDF'),
                ),
              ),
              const SizedBox(height: 8),
              FloorPlan3DView(
                sceneData: buildFloorPlanSceneData(
                  plan: plan,
                  guestCount: effectiveGuests,
                ),
              ),
              const SizedBox(height: 8),
            ],
            const Text(
              '3D preview is an illustrative render of this layout, not a photograph. '
              'People and food are stylized placeholders, not the actual guests or menu.',
              style: AppText.meta,
            ),
          ],
        );
      },
    );
  }
}

class _CapacityWarning extends StatelessWidget {
  const _CapacityWarning({required this.plan, required this.guestCount});

  final VenueSpaceFloorPlan plan;
  final int guestCount;

  @override
  Widget build(BuildContext context) {
    final capacity = floorPlanCapacity(plan);
    if (guestCount <= capacity) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        'This floor plan seats up to $capacity guests, fewer than the $guestCount guests expected.',
        style: AppText.meta.copyWith(
          color: AppColors.accent2700,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
