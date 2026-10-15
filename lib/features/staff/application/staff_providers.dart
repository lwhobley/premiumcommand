import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/session_controller.dart';
import '../data/staff_repository.dart';
import '../domain/my_assignment.dart';
import '../domain/staff_availability.dart';
import '../domain/staff_profile.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  ref.watch(sessionProvider);
  return StaffRepository(Supabase.instance.client);
});

/// Staff profiles visible to the signed-in user. Administrators get everyone; staff get only themselves.
final staffListProvider = FutureProvider.family<List<StaffProfile>, String>((
  ref,
  venueId,
) {
  ref.watch(sessionProvider);
  return ref.watch(staffRepositoryProvider).list(venueId);
});

final staffPhotoUrlProvider = FutureProvider.family<String, String>((
  ref,
  path,
) {
  return ref.watch(staffRepositoryProvider).photoUrl(path);
});

/// Staff directory and availability are visible to anyone with view_deployment. The database
/// enforces that, so the providers simply surface its answer.
final staffDirectoryProvider =
    FutureProvider.family<List<StaffDirectoryEntry>, String>((ref, venueId) {
      ref.watch(sessionProvider);
      return ref.watch(staffRepositoryProvider).directory(venueId);
    });

final staffAvailabilityProvider =
    FutureProvider.family<List<StaffAvailability>, String>((ref, venueId) {
      ref.watch(sessionProvider);
      return ref.watch(staffRepositoryProvider).availability(venueId);
    });

final myAssignmentsProvider = FutureProvider.family<List<MyAssignment>, String>(
  (ref, userId) {
    ref.watch(sessionProvider);
    return ref.watch(staffRepositoryProvider).myAssignments(userId);
  },
);
