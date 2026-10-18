import 'package:cutx_premium_command/features/suites/domain/suite.dart';
import 'package:cutx_premium_command/features/suites/domain/suite_order.dart';
import 'package:cutx_premium_command/features/suites/presentation/suite_map_section.dart';
import 'package:flutter_test/flutter_test.dart';

SuiteAssignment _assignment(String id, String suiteName, {String? mapArea}) =>
    SuiteAssignment(
      id: id,
      mapArea: mapArea,
      eventId: 'event',
      suiteId: 'suite-$id',
      suiteName: suiteName,
      location: '',
      serviceZone: '',
      state: SuiteState.notStarted,
      version: 1,
    );

SuiteOrder _order(String assignmentId, SuiteOrderStatus status) => SuiteOrder(
  id: 'order-$assignmentId',
  assignmentId: assignmentId,
  status: status,
  items: const [SuiteOrderItem(name: 'Wings', quantity: 2)],
  version: 1,
);

void main() {
  test('order statuses move draft, confirmed, delivered', () {
    expect(SuiteOrderStatus.draft.next, SuiteOrderStatus.confirmed);
    expect(SuiteOrderStatus.confirmed.next, SuiteOrderStatus.delivered);
    expect(SuiteOrderStatus.delivered.next, isNull);
  });

  test('orders parse from database rows', () {
    final order = SuiteOrder.fromJson({
      'id': 'o1',
      'assignment_id': 'a1',
      'status': 'confirmed',
      'items': [
        {'name': 'Charcuterie board', 'quantity': 2, 'notes': 'No pork'},
        {'name': 'Water', 'quantity': 12},
      ],
      'version': 3,
      'deliver_at': '2026-10-15T23:30:00Z',
      'notes': 'Gate 3',
    });
    expect(order.status, SuiteOrderStatus.confirmed);
    expect(order.itemCount, 14);
    expect(order.items.first.notes, 'No pork');
    expect(order.items.last.notes, '');
    expect(order.deliverAt, DateTime.utc(2026, 10, 15, 23, 30));
  });

  test('map status follows each assigned suite order', () {
    final statuses = suiteMapStatuses(
      [
        _assignment('a1', 'Suite 201'),
        _assignment('a2', 'Suite 202'),
        _assignment('a3', 'Suite 210'),
        _assignment('a4', 'Suite 4'), // not on the plan
        _assignment('a5', 'Premium Club A', mapArea: 'club_a'),
        _assignment('a6', 'Main Arena Floor', mapArea: 'arena_floor'),
      ],
      [
        _order('a2', SuiteOrderStatus.draft),
        _order('a3', SuiteOrderStatus.delivered),
        _order('a5', SuiteOrderStatus.confirmed),
      ],
    );
    expect(statuses, {
      '201': SuiteMapStatus.noOrder,
      '202': SuiteMapStatus.draft,
      '210': SuiteMapStatus.delivered,
      'club_a': SuiteMapStatus.confirmed,
      'arena_floor': SuiteMapStatus.noOrder,
    });
  });

  test(
    'scene payload draws all suites and clubs and mutes unassigned ones',
    () {
      final scene = buildSuiteMapScene({
        '201': SuiteMapStatus.confirmed,
        'club_b': SuiteMapStatus.draft,
      }, selected: '201');
      final suites = (scene['suites']! as List).cast<Map<String, Object?>>();
      expect(suites, hasLength(31));
      final clubB = suites.firstWhere((s) => s['id'] == 'club_b');
      expect(clubB['label'], 'Loge Club');
      expect(clubB['muted'], isFalse);
      expect(suites.firstWhere((s) => s['id'] == 'club_a')['muted'], isTrue);
      final renamed =
          (buildSuiteMapScene(
                    const {},
                    labels: mapLabelsFor([
                      {'id': 's1', 'name': 'Suite 304', 'map_area': '204'},
                      {'id': 's2', 'name': 'Owners Club', 'map_area': 'club_a'},
                    ]),
                  )['suites']!
                  as List)
              .cast<Map<String, Object?>>();
      expect(renamed.firstWhere((s) => s['id'] == '204')['label'], 'S304');
      expect(
        renamed.firstWhere((s) => s['id'] == 'club_a')['label'],
        'Owners Club',
      );
      expect(renamed.firstWhere((s) => s['id'] == '205')['label'], 'S205');
      final floor = scene['floor']! as Map<String, Object?>;
      expect(floor['id'], 'arena_floor');
      expect(floor['muted'], isTrue);
      final assigned =
          buildSuiteMapScene({
                'arena_floor': SuiteMapStatus.confirmed,
              })['floor']!
              as Map<String, Object?>;
      expect(assigned['muted'], isFalse);
      expect(assigned['color'], '#0088b0');
      final concourse = scene['concourse']! as Map<String, Object?>;
      expect(concourse['id'], 'concourse');
      expect(concourse['label'], 'Concourse');
      expect(concourse['muted'], isTrue);
      expect(
        (buildSuiteMapScene({
              'concourse': SuiteMapStatus.confirmed,
            })['concourse']!
            as Map<String, Object?>)['muted'],
        isFalse,
      );
      expect(scene['selected'], '201');
      final first = suites.firstWhere((s) => s['id'] == '201');
      expect(first['muted'], isFalse);
      expect(first['color'], '#0088b0');
      expect(suites.firstWhere((s) => s['id'] == '229')['muted'], isTrue);
    },
  );

  test('scene payload draws the seating chart sections on the map', () {
    final sections = (buildSuiteMapScene(const {})['sections']! as List)
        .cast<Map<String, Object?>>();
    expect(sections.where((s) => s['kind'] == 'bowl').map((s) => s['id']), [
      for (var n = 100; n <= 120; n++) '$n',
    ]);
    final club = sections.where((s) => s['kind'] == 'club').toList();
    expect(club.map((s) => s['id']), ['W244', 'W243', 'W242', 'W241', 'W240']);
    expect(club.every((s) => s['space'] == 'club_a'), isTrue);
  });
}
