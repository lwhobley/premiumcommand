import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/session_controller.dart';

import '../data/floor_plan_repository.dart';
import '../domain/floor_plan.dart';

final floorPlanRepositoryProvider = Provider<FloorPlanRepository>((ref) {
  ref.watch(sessionProvider);
  return FloorPlanRepository(Supabase.instance.client);
});

final venueSpacesProvider = FutureProvider.family<List<VenueSpace>, String>((ref, venueId) {
  return ref.watch(floorPlanRepositoryProvider).listVenueSpaces(venueId);
});

final floorPlanProvider = FutureProvider.family<VenueSpaceFloorPlan?, String>((ref, venueSpaceId) {
  return ref.watch(floorPlanRepositoryProvider).getFloorPlan(venueSpaceId);
});

/// Floor plans for every space assigned to an event, skipping spaces with no plan saved yet.
final eventFloorPlansProvider = FutureProvider.family<List<VenueSpaceFloorPlan>, String>((ref, eventId) async {
  final repo = ref.watch(floorPlanRepositoryProvider);
  final spaceIds = await repo.listEventSpaceIds(eventId);
  final plans = await Future.wait(spaceIds.map(repo.getFloorPlan));
  return plans.whereType<VenueSpaceFloorPlan>().toList();
});

/// Which venue space the Floor Plan Studio is currently editing.
final selectedVenueSpaceIdProvider = NotifierProvider<SelectedVenueSpaceController, String?>(
  SelectedVenueSpaceController.new,
);

class SelectedVenueSpaceController extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(sessionProvider);
    return null;
  }

  void select(String? venueSpaceId) => state = venueSpaceId;
}
