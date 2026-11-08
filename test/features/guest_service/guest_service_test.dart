import 'package:cutx_premium_command/features/guest_service/domain/guest_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dollar amounts', () {
    test('reads whole and cent amounts', () {
      expect(parseDollarsToCents('12.50'), 1250);
      expect(parseDollarsToCents('\$12'), 1200);
      expect(parseDollarsToCents(' 1,200.5 '), 120050);
      expect(parseDollarsToCents('0.05'), 5);
    });

    test('refuses zero, negatives, and too many decimals', () {
      expect(parseDollarsToCents('0'), isNull);
      expect(parseDollarsToCents('-4'), isNull);
      expect(parseDollarsToCents('4.567'), isNull);
      expect(parseDollarsToCents('abc'), isNull);
      expect(parseDollarsToCents(''), isNull);
    });
  });

  test('a comp reads its status and amount from the database row', () {
    final comp = Comp.fromJson({
      'id': 'c1',
      'event_id': 'e1',
      'suite_assignment_id': null,
      'amount_cents': 2500,
      'reason': 'Late food',
      'status': 'pending',
      'requested_at': '2026-11-08T12:00:00Z',
      'version': 1,
      'decision_note': '',
    });
    expect(comp.amountCents, 2500);
    expect(comp.status, CompStatus.pending);
    expect(CompStatus.fromCode('approved'), CompStatus.approved);
    expect(CompStatus.fromCode('anything'), CompStatus.pending);
  });

  test('an empty preference card is recognized', () {
    expect(GuestPreferences(suiteAssignmentId: 's1').isEmpty, isTrue);
    expect(
      GuestPreferences(suiteAssignmentId: 's1', allergies: 'Peanuts').isEmpty,
      isFalse,
    );
  });
}
