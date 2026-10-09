import 'dart:io';

import 'package:cutx_premium_command/core/errors/failure_kind.dart';
import 'package:cutx_premium_command/core/offline/outbox.dart';
import 'package:cutx_premium_command/features/dispatch/domain/service_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('failure classification', () {
    test('a socket failure is offline and therefore queueable', () {
      expect(classifyFailure(const SocketException('Failed host lookup')), FailureKind.offline);
      expect(isNetworkError(const SocketException('x')), isTrue);
    });

    test('a stale version is a conflict, never a silent overwrite', () {
      const error = PostgrestException(message: 'Conflict', code: '40001');
      expect(classifyFailure(error), FailureKind.conflict);
      expect(friendlyMessage(error), contains('changed this first'));
    });

    test('a refused action is a permission failure', () {
      const error = PostgrestException(message: 'Not authorized', code: '42501');
      expect(classifyFailure(error), FailureKind.permission);
      expect(friendlyMessage(error), contains("don't have permission"));
    });

    test('a business-rule failure shows the database message', () {
      const error = PostgrestException(message: 'Only accepted requests can be started', code: 'P0001');
      expect(classifyFailure(error), FailureKind.rule);
      expect(friendlyMessage(error), 'Only accepted requests can be started');
    });

    test('unknown errors never leak raw text', () {
      expect(friendlyMessage(StateError('internal detail')), 'Something went wrong. Please try again.');
    });
  });

  group('outbox store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('adding the same id twice keeps one item', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = OutboxStore(prefs: prefs);
      final item = OutboxItem(id: 'a', kind: 'set_task_status', payload: const {}, createdAt: DateTime.now());
      await store.add(item);
      await store.add(item);
      expect(store.items.length, 1);
    });

    test('items survive a reload, which is what protects work across an app restart', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = OutboxStore(prefs: prefs);
      await first.add(OutboxItem(
        id: 'create-1',
        kind: 'create_service_request',
        payload: const {'description': 'Ice'},
        createdAt: DateTime(2026, 10, 8, 12),
      ));

      final second = OutboxStore(prefs: prefs);
      await second.load();
      expect(second.items.single.id, 'create-1');
      expect(second.items.single.payload['description'], 'Ice');
    });

    test('a replaced item can be marked for review and keeps its error', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = OutboxStore(prefs: prefs);
      final item = OutboxItem(id: 'b', kind: 'transition_service_request', payload: const {}, createdAt: DateTime.now());
      await store.add(item);
      await store.replace(item.copyWith(needsReview: true, lastError: 'Conflict'));
      expect(store.items.single.needsReview, isTrue);
      expect(store.items.single.lastError, 'Conflict');
    });

    test('removing an item clears it', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = OutboxStore(prefs: prefs);
      await store.add(OutboxItem(id: 'c', kind: 'k', payload: const {}, createdAt: DateTime.now()));
      await store.remove('c');
      expect(store.items, isEmpty);
    });
  });

  group('offline cache', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a service request round-trips through the cache format', () {
      final request = ServiceRequest(
        id: 'r1',
        eventId: 'e1',
        clientRequestId: 'c1',
        category: RequestCategory.ice,
        location: 'Suite 2',
        description: 'Ice',
        priority: RequestPriority.high,
        status: RequestStatus.assigned,
        createdAt: DateTime(2026, 10, 8, 12).toUtc(),
        version: 3,
        assignedDepartment: 'operations',
      );
      final back = ServiceRequest.fromJson(request.toJson());
      expect(back.id, 'r1');
      expect(back.status, RequestStatus.assigned);
      expect(back.version, 3);
      expect(back.assignedDepartment, 'operations');
      expect(back.priority, RequestPriority.high);
    });

    test('a missing or corrupt cache entry reads as empty, not as an error', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = OfflineCache(prefs: prefs);
      expect(await cache.read('nothing-here'), isNull);
      await prefs.setString('broken', 'not json');
      expect(await cache.read('broken'), isNull);
    });
  });
}
