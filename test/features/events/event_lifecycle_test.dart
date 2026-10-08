import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/events/domain/event_lifecycle.dart';
import 'package:cutx_premium_command/features/events/domain/ops_event.dart';
import 'package:flutter_test/flutter_test.dart';

const manager = {AppPermission.manageEvents, AppPermission.approveBeo, AppPermission.updateTasks};
final director = AppPermission.values.toSet();

void main() {
  group('evaluateTransition', () {
    test('allows the next forward step with manage_events', () {
      final decision = evaluateTransition(
        from: EventStatus.planning,
        to: EventStatus.approved,
        permissions: manager,
        requiredTasksComplete: false,
      );
      expect(decision.allowed, isTrue);
    });

    test('rejects skipping a lifecycle step', () {
      final decision = evaluateTransition(
        from: EventStatus.draft,
        to: EventStatus.approved,
        permissions: director,
        requiredTasksComplete: true,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, contains('one lifecycle step'));
    });

    test('rejects going backwards', () {
      final decision = evaluateTransition(
        from: EventStatus.setup,
        to: EventStatus.approved,
        permissions: director,
        requiredTasksComplete: true,
      );
      expect(decision.allowed, isFalse);
    });

    test('requires approve_beo to approve', () {
      final decision = evaluateTransition(
        from: EventStatus.planning,
        to: EventStatus.approved,
        permissions: {AppPermission.manageEvents},
        requiredTasksComplete: false,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, contains('BEO'));
    });

    test('blocks ready until required tasks are complete', () {
      final blocked = evaluateTransition(
        from: EventStatus.setup,
        to: EventStatus.ready,
        permissions: manager,
        requiredTasksComplete: false,
      );
      final allowed = evaluateTransition(
        from: EventStatus.setup,
        to: EventStatus.ready,
        permissions: manager,
        requiredTasksComplete: true,
      );
      expect(blocked.allowed, isFalse);
      expect(allowed.allowed, isTrue);
    });

    test('only directors may cancel', () {
      final managerCancel = evaluateTransition(
        from: EventStatus.planning,
        to: EventStatus.cancelled,
        permissions: manager,
        requiredTasksComplete: false,
      );
      final directorCancel = evaluateTransition(
        from: EventStatus.planning,
        to: EventStatus.cancelled,
        permissions: director,
        requiredTasksComplete: false,
      );
      expect(managerCancel.allowed, isFalse);
      expect(directorCancel.allowed, isTrue);
    });

    test('closed events cannot be cancelled', () {
      final decision = evaluateTransition(
        from: EventStatus.closed,
        to: EventStatus.cancelled,
        permissions: director,
        requiredTasksComplete: true,
      );
      expect(decision.allowed, isFalse);
    });

    test('reopening a closed event to breakdown is director-only', () {
      final managerReopen = evaluateTransition(
        from: EventStatus.closed,
        to: EventStatus.breakdown,
        permissions: manager,
        requiredTasksComplete: true,
      );
      final directorReopen = evaluateTransition(
        from: EventStatus.closed,
        to: EventStatus.breakdown,
        permissions: director,
        requiredTasksComplete: true,
      );
      expect(managerReopen.allowed, isFalse);
      expect(directorReopen.allowed, isTrue);
    });

    test('a cancelled event may only reopen to planning', () {
      final toApproved = evaluateTransition(
        from: EventStatus.cancelled,
        to: EventStatus.approved,
        permissions: director,
        requiredTasksComplete: true,
      );
      final toPlanning = evaluateTransition(
        from: EventStatus.cancelled,
        to: EventStatus.planning,
        permissions: director,
        requiredTasksComplete: true,
      );
      expect(toApproved.allowed, isFalse);
      expect(toPlanning.allowed, isTrue);
    });

    test('lifecycle order matches the specification', () {
      expect(lifecycleOrder.map((s) => s.code).toList(), [
        'draft',
        'planning',
        'approved',
        'setup',
        'ready',
        'in_service',
        'breakdown',
        'closed',
      ]);
    });
  });
}
