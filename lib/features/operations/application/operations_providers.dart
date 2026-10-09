import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/evidence_storage.dart';
import '../data/operations_repository.dart';
import '../domain/operations.dart';

final operationsRepositoryProvider = Provider<OperationsRepository>((ref) {
  return OperationsRepository(Supabase.instance.client);
});

final evidenceStorageProvider = Provider<EvidenceStorage>((ref) {
  return EvidenceStorage(Supabase.instance.client);
});

final timelineProvider =FutureProvider.family<List<TimelineItem>, String>((ref, eventId) {
  return ref.watch(operationsRepositoryProvider).listTimeline(eventId);
});

final batchesProvider = FutureProvider.family<List<CulinaryBatch>, String>((ref, eventId) {
  return ref.watch(operationsRepositoryProvider).listBatches(eventId);
});

final menuProvider = FutureProvider.family<List<MenuItem>, String>((ref, eventId) {
  return ref.watch(operationsRepositoryProvider).listMenu(eventId);
});

final templatesProvider = FutureProvider<List<ChecklistTemplate>>((ref) {
  return ref.watch(operationsRepositoryProvider).listTemplates();
});

final inspectionsProvider = FutureProvider.family<List<InspectionInstance>, String>((ref, eventId) {
  return ref.watch(operationsRepositoryProvider).listInspections(eventId);
});

final announcementsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, eventId) {
  return ref.watch(operationsRepositoryProvider).listAnnouncements(eventId);
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  return ref.watch(operationsRepositoryProvider).listNotifications();
});

final closeoutProvider = FutureProvider.family<Closeout?, String>((ref, eventId) {
  return ref.watch(operationsRepositoryProvider).loadCloseout(eventId);
});

final closeoutsProvider = FutureProvider<List<Closeout>>((ref) {
  return ref.watch(operationsRepositoryProvider).listCloseouts();
});
