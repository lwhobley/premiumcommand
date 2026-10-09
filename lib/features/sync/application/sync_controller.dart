import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure_kind.dart';
import '../../../core/offline/outbox.dart';
import '../../auth/application/session_controller.dart';
import '../../dispatch/application/dispatch_providers.dart';
import '../../dispatch/data/dispatch_repository.dart';
import '../../dispatch/domain/service_request.dart';
import '../../events/application/event_providers.dart';
import '../../events/domain/readiness.dart';

const outboxCreateRequest = 'create_service_request';
const outboxTransitionRequest = 'transition_service_request';
const outboxSetTaskStatus = 'set_task_status';

final outboxStoreProvider = Provider<OutboxStore>((ref) => OutboxStore());

final offlineCacheProvider = Provider<OfflineCache>((ref) => OfflineCache());

class SyncState {
  const SyncState({this.pending = 0, this.needsReview = 0, this.syncing = false, this.lastError});

  final int pending;
  final int needsReview;
  final bool syncing;
  final String? lastError;

  bool get hasWork => pending > 0 || needsReview > 0;
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Saves writes made while offline and sends them in order. Writes that conflict are kept for review.
class SyncController extends Notifier<SyncState> {
  late final OutboxStore _store = ref.read(outboxStoreProvider);
  Timer? _timer;
  bool _flushing = false;

  @override
  SyncState build() {
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
    ref.onDispose(() => _timer?.cancel());
    unawaited(_store.load().then((_) {
      _publish();
      flush();
    }));
    return const SyncState();
  }

  /// Only the signed-in person's queued changes.
  List<OutboxItem> get items {
    final userId = ref.read(sessionProvider)?.userId;
    return _store.items.where((i) => i.userId.isEmpty || i.userId == userId).toList();
  }

  void _publish({String? error, bool clearError = false, bool? syncing}) {
    final userId = ref.read(sessionProvider)?.userId;
    final mine = _store.items.where((i) => i.userId.isEmpty || i.userId == userId).toList();
    final pending = mine.where((i) => !i.needsReview).length;
    final review = mine.where((i) => i.needsReview).length;
    state = SyncState(
      pending: pending,
      needsReview: review,
      syncing: syncing ?? _flushing,
      lastError: clearError ? null : (error ?? state.lastError),
    );
  }

  /// Saves a write for later. Returns immediately; sending happens in [flush].
  Future<void> enqueue(String kind, Map<String, dynamic> payload, {String? id}) async {
    final item = OutboxItem(
      id: id ?? _newId(),
      kind: kind,
      payload: payload,
      userId: ref.read(sessionProvider)?.userId ?? '',
      createdAt: DateTime.now(),
    );
    await _store.add(item);
    _publish();
    unawaited(flush());
  }

  /// Sends everything waiting, oldest first. Stops at the first network error to keep order.
  Future<void> flush() async {
    if (_flushing) return;
    // With nobody signed in there is no valid identity to send under, so nothing leaves the device.
    final userId = ref.read(sessionProvider)?.userId;
    if (userId == null) return;
    _flushing = true;
    _publish(syncing: true);
    try {
      for (final item in List<OutboxItem>.from(_store.items)) {
        if (item.needsReview) continue;
        // Another person's queued work waits for that person; it is never sent under this account.
        if (item.userId.isNotEmpty && item.userId != userId) continue;
        try {
          await _send(item);
          await _store.remove(item.id);
        } catch (error) {
          final kind = classifyFailure(error);
          if (kind == FailureKind.offline) {
            await _store.replace(item.copyWith(attempts: item.attempts + 1, lastError: 'Offline'));
            _publish(error: 'Offline. Waiting to sync.');
            break;
          }
          // Conflicts, permission changes, and rule failures go to review. Nothing is overwritten.
          await _store.replace(item.copyWith(
            attempts: item.attempts + 1,
            needsReview: true,
            lastError: friendlyMessage(error),
          ));
        }
      }
      _publish(clearError: true);
    } finally {
      _flushing = false;
      _publish(syncing: false);
    }
  }

  Future<void> _send(OutboxItem item) async {
    final p = item.payload;
    switch (item.kind) {
      case outboxCreateRequest:
        await ref.read(dispatchRepositoryProvider).createRequest(
              p['event_id'] as String,
              ServiceRequestDraft(
                clientRequestId: p['client_request_id'] as String,
                category: RequestCategory.fromCode(p['category'] as String),
                location: (p['location'] as String?) ?? '',
                description: p['description'] as String,
                priority: RequestPriority.fromCode(p['priority'] as String),
              ),
            );
      case outboxTransitionRequest:
        await ref.read(dispatchRepositoryProvider).transition(
              requestId: p['request_id'] as String,
              to: RequestStatus.fromCode(p['to'] as String),
              expectedVersion: (p['expected_version'] as num).toInt(),
              note: (p['note'] as String?) ?? '',
              department: p['department'] as String?,
              userId: p['user_id'] as String?,
            );
      case outboxSetTaskStatus:
        await ref.read(eventRepositoryProvider).setTaskStatus(
              p['task_id'] as String,
              TaskStatus.fromCode(p['status'] as String),
            );
      default:
        throw StateError('Unknown queued change: ${item.kind}');
    }
  }

  /// Puts a reviewed item back in the queue. The server re-checks it, so a stale change still fails safely.
  Future<void> retry(String id) async {
    final item = _store.items.where((i) => i.id == id).firstOrNull;
    if (item == null) return;
    await _store.replace(item.copyWith(needsReview: false, lastError: ''));
    _publish();
    unawaited(flush());
  }

  /// Drops a queued change the user chose not to keep.
  Future<void> discard(String id) async {
    await _store.remove(id);
    _publish();
  }

  static String _newId() => newClientRequestId();
}
