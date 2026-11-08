import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/session_controller.dart';
import '../../dispatch/application/dispatch_providers.dart';
import '../../dispatch/domain/service_request.dart';
import '../../events/application/event_providers.dart';
import '../data/guest_service_repository.dart';
import '../domain/guest_service.dart';

final guestServiceRepositoryProvider = Provider<GuestServiceRepository>((ref) {
  return GuestServiceRepository(Supabase.instance.client);
});

final guestPreferencesProvider =
    FutureProvider.family<GuestPreferences, String>((ref, suiteAssignmentId) {
      return ref
          .watch(guestServiceRepositoryProvider)
          .preferences(suiteAssignmentId);
    });

final eventCompsProvider = FutureProvider.family<List<Comp>, String>((
  ref,
  eventId,
) {
  return ref.watch(guestServiceRepositoryProvider).comps(eventId);
});

/// The signed-in runner's request that is in progress right now, if any. Location is shared only
/// while this is set.
final myInProgressRequestProvider = Provider<ServiceRequest?>((ref) {
  final userId = ref.watch(sessionProvider)?.userId;
  if (userId == null) return null;
  final snapshots = ref.watch(eventSnapshotsProvider).value ?? const [];
  for (final snapshot in snapshots) {
    final requests =
        ref.watch(eventRequestsProvider(snapshot.event.id)).value ?? const [];
    for (final request in requests) {
      if (request.status == RequestStatus.inProgress &&
          request.assignedUserId == userId) {
        return request;
      }
    }
  }
  return null;
});

/// Sends the runner's position to the service desk while their request is in progress, and
/// stops the moment it is no longer in progress. The state is a status line for the runner, or
/// null when location is not being shared.
final runnerLocationSharingProvider =
    NotifierProvider<RunnerLocationSharing, String?>(RunnerLocationSharing.new);

class RunnerLocationSharing extends Notifier<String?> {
  /// One point at most this often, so the desk sees movement without a stream of updates.
  static const interval = Duration(seconds: 30);

  StreamSubscription<Position>? _positions;
  DateTime? _lastSent;

  @override
  String? build() {
    final request = ref.watch(myInProgressRequestProvider);
    ref.onDispose(_stop);
    if (request == null) return null;
    unawaited(_start(request));
    return 'Sharing your location while this request is in progress.';
  }

  Future<void> _start(ServiceRequest request) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      state = 'Turn on location services to share your position.';
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      state = 'Location is off. Allow it in settings to share your position.';
      return;
    }
    // A newer request may have replaced this one while we were asking.
    if (ref.read(myInProgressRequestProvider)?.id != request.id) return;

    await _stop();
    _positions = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((position) => _record(request, position));
  }

  Future<void> _record(ServiceRequest request, Position position) async {
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < interval) return;
    _lastSent = now;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref
          .read(guestServiceRepositoryProvider)
          .recordLocation(
            venueId: session.venueId,
            eventId: request.eventId,
            requestId: request.id,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyMeters: position.accuracy,
          );
    } catch (_) {
      // A missed point is not worth interrupting the runner; the next one is sent on the interval.
    }
  }

  Future<void> _stop() async {
    await _positions?.cancel();
    _positions = null;
    _lastSent = null;
  }
}
