import 'package:cutx_premium_command/features/auth/application/session_controller.dart';
import 'package:cutx_premium_command/features/auth/domain/app_session.dart';
import 'package:cutx_premium_command/features/events/application/event_providers.dart';
import 'package:cutx_premium_command/features/events/domain/ops_event.dart';
import 'package:cutx_premium_command/features/events/domain/readiness.dart';
import 'package:cutx_premium_command/features/suites/application/service_day_providers.dart';
import 'package:cutx_premium_command/features/suites/domain/suite.dart';
import 'package:cutx_premium_command/features/suites/domain/suite_order.dart';
import 'package:cutx_premium_command/features/suites/domain/suite_service_days.dart';
import 'package:cutx_premium_command/features/suites/presentation/suite_map_section.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _chicago = 'America/Chicago';

SuiteOrder _order(
  String assignmentId,
  List<String> itemNames, {
  DateTime? deliverAt,
}) => SuiteOrder(
  id: 'order-$assignmentId',
  assignmentId: assignmentId,
  status: SuiteOrderStatus.confirmed,
  items: [
    for (final name in itemNames) SuiteOrderItem(name: name, quantity: 1),
  ],
  version: 1,
  deliverAt: deliverAt,
);

SuiteAssignment _assignment(String id, String suiteName, {String notes = ''}) =>
    SuiteAssignment(
      id: id,
      eventId: 'event',
      suiteId: 'suite-$id',
      suiteName: suiteName,
      location: '',
      serviceZone: '',
      state: SuiteState.notStarted,
      version: 1,
      specialInstructions: notes,
    );

void main() {
  // League of Legends Worlds 2026: Quarterfinals, Nov 3 12:00 to Nov 6 23:00 at the venue.
  final quarterfinals = eventServiceDays(
    DateTime.utc(2026, 11, 3, 18),
    DateTime.utc(2026, 11, 7, 5),
    _chicago,
  );

  test('an event covers each venue day from its start to its end', () {
    expect(quarterfinals, [
      DateTime(2026, 11, 3),
      DateTime(2026, 11, 4),
      DateTime(2026, 11, 5),
      DateTime(2026, 11, 6),
    ]);
    // Ends after midnight UTC but before midnight at the venue: still one day.
    expect(
      eventServiceDays(
        DateTime.utc(2026, 10, 30, 17),
        DateTime.utc(2026, 10, 31, 4),
        _chicago,
      ),
      [DateTime(2026, 10, 30)],
    );
  });

  test('an order serves the days its items start with', () {
    final order = _order('a228', [
      'Tue Nov 3 · Popcorn',
      'Thu Nov 5 · Buffalo Wings',
      'Thursday, November 5 · Water',
    ]);
    expect(orderServiceDays(order, quarterfinals, _chicago), {
      DateTime(2026, 11, 3),
      DateTime(2026, 11, 5),
    });
  });

  test('an order serves the day it is delivered', () {
    final order = _order(
      'a201',
      ['The MVP'],
      deliverAt: DateTime.utc(2026, 11, 4, 17), // noon at the venue
    );
    expect(orderServiceDays(order, quarterfinals, _chicago), {
      DateTime(2026, 11, 4),
    });
  });

  test('an order that names no day serves every day of the event', () {
    final order = _order('a210', ['Wings']);
    expect(
      orderServiceDays(order, quarterfinals, _chicago),
      quarterfinals.toSet(),
    );
  });

  test('an order dated only outside the event serves no day', () {
    final delivered = _order(
      'a201',
      ['The MVP'],
      deliverAt: DateTime.utc(2026, 11, 2, 18), // the day before the event
    );
    expect(orderServiceDays(delivered, quarterfinals, _chicago), isEmpty);
    final named = _order('a228', ['Mon Nov 2 · Popcorn']);
    expect(orderServiceDays(named, quarterfinals, _chicago), isEmpty);
  });

  test('the picked day survives the event list reloading', () async {
    final event = OpsEvent(
      id: 'qf',
      venueId: 'v1',
      name: 'Quarterfinals',
      type: EventType.concert,
      serviceStart: DateTime.utc(2026, 11, 3, 12),
      serviceEnd: DateTime.utc(2026, 11, 6, 23),
      guaranteedGuests: 100,
      managerName: 'M',
      status: EventStatus.setup,
    );
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(_VenueSession.new),
        eventSnapshotsProvider.overrideWith(
          (ref) async => [
            EventSnapshot(event: event, tasks: const [], now: DateTime.now()),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(selectedServiceDayProvider('qf'), (_, _) {});
    await container.read(eventSnapshotProvider('qf').future);
    container
        .read(selectedServiceDayProvider('qf').notifier)
        .select(DateTime(2026, 11, 5));

    container.invalidate(eventSnapshotsProvider);
    await container.read(eventSnapshotProvider('qf').future);

    expect(
      container.read(selectedServiceDayProvider('qf')),
      DateTime(2026, 11, 5),
    );
  });

  test('only orders with items serving the day count', () {
    final orders = [
      _order('a228', ['Thu Nov 5 · Buffalo Wings']),
      _order('a201', ['Tue Nov 3 · Popcorn']),
      _order('a205', []),
    ];
    expect(
      assignmentsServedOn(
        DateTime(2026, 11, 5),
        orders,
        quarterfinals,
        _chicago,
      ),
      {'a228'},
    );
  });

  test(
    'the first day shown is today during the event, otherwise its first day',
    () {
      expect(
        defaultServiceDay(
          quarterfinals,
          DateTime.utc(2026, 11, 5, 20),
          _chicago,
        ),
        DateTime(2026, 11, 5),
      );
      expect(
        defaultServiceDay(
          quarterfinals,
          DateTime.utc(2026, 10, 28, 20),
          _chicago,
        ),
        DateTime(2026, 11, 3),
      );
      expect(defaultServiceDay(const [], DateTime.now(), _chicago), isNull);
    },
  );

  test('a BEO timeline names the suites for each day', () {
    const timeline =
        'Tue Nov 3: food delivery 3:00 PM · Premium Level Suite 228 · CaterTrax invoice #43\n'
        'Wed Nov 4: no CaterTrax invoice received yet (the workbook plans 12 guests).\n'
        'Thu Nov 5: food delivery 3:00 PM · Premium Level Party Suite 228/229 · invoice #46';
    expect(beoTimelineSuites(timeline, DateTime(2026, 11, 3), quarterfinals), {
      '228',
    });
    expect(
      beoTimelineSuites(timeline, DateTime(2026, 11, 4), quarterfinals),
      isEmpty,
    );
    expect(beoTimelineSuites(timeline, DateTime(2026, 11, 5), quarterfinals), {
      '228',
      '229',
    });
    expect(
      beoTimelineSuites(
        'Suites 201, 202 and 215: host suites',
        DateTime(2026, 10, 30),
        [DateTime(2026, 10, 30)],
      ),
      {'201', '202', '215'},
    );
    // In a multi-day event a line without a day applies to no particular day.
    expect(
      beoTimelineSuites('Suite 201 host', DateTime(2026, 11, 3), quarterfinals),
      isEmpty,
    );
  });

  test('a suite shows on the days its notes name, or every day if none', () {
    final disney = [for (var d = 24; d <= 29; d++) DateTime(2026, 11, d)];
    final suites = [
      _assignment(
        'a201',
        'Suite 201',
        notes: 'Shows:\nWed Nov 25 7:00 PM: ADA - Vet Tix Relocation',
      ),
      _assignment(
        'a228',
        'Suite 228',
        notes: 'Shows:\nWed Nov 25 7:00 PM: Prieto Party\nSat Nov 28 1:00 PM: Berry Family',
      ),
      _assignment('a229', 'Suite 229', notes: 'Shares the order on Suite 228.'),
      _assignment(
        'a203',
        'Suite 203',
        notes: 'Sat Nov 28 5:00 PM: Perez Family',
      ),
    ];
    expect(assignmentsInUseOn(DateTime(2026, 11, 25), suites, disney, {}), {
      'a201',
      'a228',
      'a229',
    });
    expect(assignmentsInUseOn(DateTime(2026, 11, 28), suites, disney, {}), {
      'a228',
      'a229',
      'a203',
    });
    // A BEO that day shows the suite even when its notes name other days.
    expect(
      assignmentsInUseOn(DateTime(2026, 11, 26), suites, disney, {'a201'}),
      {'a201', 'a229'},
    );
    // Days named mid-sentence count too.
    expect(
      namedServiceDays('Swiss Stage: occupied Wed Oct 28 and Fri Oct 30.', [
        for (var d = 23; d <= 31; d++) DateTime(2026, 10, d),
      ]),
      {DateTime(2026, 10, 28), DateTime(2026, 10, 30)},
    );
  });

  test('striped spaces are flagged in the map scene', () {
    final areas = stripedAreas(
      [_assignment('a1', 'Suite 228'), _assignment('a2', 'Suite 229')],
      {'a2'},
    );
    expect(areas, {'229'});
    final scene = buildSuiteMapScene({
      '228': SuiteMapStatus.confirmed,
      '229': SuiteMapStatus.noOrder,
    }, striped: areas);
    final suites = (scene['suites'] as List).cast<Map<String, Object?>>();
    expect(suites.firstWhere((s) => s['id'] == '229')['striped'], isTrue);
    expect(suites.firstWhere((s) => s['id'] == '228')['striped'], isFalse);
  });
}

class _VenueSession extends SessionController {
  @override
  AppSession? build() => const AppSession(
    userId: 'u1',
    displayName: 'Director',
    venueId: 'v1',
    venueName: 'CUTX',
    timeZone: _chicago,
    roles: {},
  );
}
