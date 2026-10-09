import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../staffing/domain/staffing.dart';
import '../../suites/domain/suite.dart';
import '../data/planning_repository.dart';

final planningRepositoryProvider = Provider<PlanningRepository>((ref) {
  return PlanningRepository(Supabase.instance.client);
});

/// The event the planning screens are showing. Shared so switching sections keeps the same event.
final selectedEventIdProvider = NotifierProvider<SelectedEventController, String?>(SelectedEventController.new);

class SelectedEventController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? eventId) => state = eventId;
}

final suitesProvider = FutureProvider.family<List<SuiteAssignment>, String>((ref, eventId) {
  return ref.watch(planningRepositoryProvider).listSuites(eventId);
});

final staffProvider = FutureProvider.family<List<StaffPosition>, String>((ref, eventId) {
  return ref.watch(planningRepositoryProvider).listStaff(eventId);
});

final briefingsProvider = FutureProvider.family<List<Briefing>, String>((ref, eventId) {
  return ref.watch(planningRepositoryProvider).listBriefings(eventId);
});

final beoProvider = FutureProvider.family<BeoBundle?, String>((ref, eventId) {
  return ref.watch(planningRepositoryProvider).loadBeo(eventId);
});

final venueSuitesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, venueId) {
  return ref.watch(planningRepositoryProvider).listVenueSuites(venueId);
});
