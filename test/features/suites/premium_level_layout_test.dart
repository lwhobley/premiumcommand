import 'package:cutx_premium_command/features/suites/domain/premium_level_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Centers of the suite numbers printed on "Suites Labeled.pdf", in the same
/// landscape point coordinates as the traced outlines.
const _labelCenters = <String, PlanPoint>{
  '201': (272.0, 196.5),
  '202': (322.0, 170.0),
  '203': (368.3, 157.0),
  '204': (404.9, 157.3),
  '205': (439.1, 157.3),
  '206': (481.1, 157.3),
  '207': (525.8, 157.3),
  '208': (576.1, 157.3),
  '209': (629.3, 157.0),
  '210': (683.0, 157.3),
  '211': (724.1, 157.3),
  '212': (774.3, 157.3),
  '213': (808.3, 157.0),
  '214': (842.0, 157.3),
  '215': (885.4, 168.9),
  '216': (838.8, 676.6),
  '217': (806.1, 676.6),
  '218': (769.3, 676.6),
  '219': (727.9, 676.6),
  '220': (684.8, 676.6),
  '221': (635.1, 676.6),
  '222': (573.0, 676.6),
  '223': (525.7, 676.6),
  '224': (482.0, 676.6),
  '225': (439.5, 676.6),
  '226': (402.5, 676.6),
  '227': (367.6, 676.6),
  '228': (323.8, 662.0),
  '229': (274.5, 634.2),
};

bool _contains(List<PlanPoint> polygon, PlanPoint p) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final (xi, yi) = polygon[i];
    final (xj, yj) = polygon[j];
    if ((yi > p.$2) != (yj > p.$2) &&
        p.$1 < (xj - xi) * (p.$2 - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

void main() {
  test('the plan has the 29 suites numbered 201 through 229', () {
    expect(premiumLevelSuites.map((s) => s.number).toList(), [
      for (var n = 201; n <= 229; n++) '$n',
    ]);
  });

  test('each printed suite number lies inside its own outline only', () {
    for (final MapEntry(key: number, value: label) in _labelCenters.entries) {
      final containing = premiumLevelSuites
          .where((s) => _contains(s.points, label))
          .map((s) => s.number)
          .toList();
      expect(containing, [number], reason: 'label $number');
    }
  });

  test('suites sit between the bowl edge and the level footprint', () {
    final (left, top) = premiumLevelFootprint.first;
    final (right, bottom) = premiumLevelFootprint[2];
    for (final suite in premiumLevelSuites) {
      for (final (x, y) in suite.points) {
        expect(x, inInclusiveRange(left, right), reason: suite.number);
        expect(y, inInclusiveRange(top, bottom), reason: suite.number);
      }
      final centerX =
          suite.points.map((p) => p.$1).reduce((a, b) => a + b) /
          suite.points.length;
      final centerY =
          suite.points.map((p) => p.$2).reduce((a, b) => a + b) /
          suite.points.length;
      expect(
        _contains(premiumLevelBowlEdge, (centerX, centerY)),
        isFalse,
        reason: suite.number,
      );
    }
  });

  test('suite names map to plan numbers', () {
    expect(planSuiteNumber('Suite 204'), '204');
    expect(planSuiteNumber('204'), '204');
    expect(planSuiteNumber('Suite 4'), isNull);
    expect(planSuiteNumber('Level 2 Suite 230'), isNull);
  });

  group('premium clubs', () {
    PlanPoint center(List<PlanPoint> points) => (
      points.map((p) => p.$1).reduce((a, b) => a + b) / points.length,
      points.map((p) => p.$2).reduce((a, b) => a + b) / points.length,
    );

    test('two clubs, both on the level', () {
      expect(premiumLevelClubs.map((c) => c.mapArea), ['club_a', 'club_b']);
      expect(premiumLevelAreaCount, 33);
      final (left, top) = premiumLevelFootprint.first;
      final (right, bottom) = premiumLevelFootprint[2];
      for (final club in premiumLevelClubs) {
        for (final (x, y) in club.points) {
          expect(x, inInclusiveRange(left, right), reason: club.mapArea);
          expect(y, inInclusiveRange(top, bottom), reason: club.mapArea);
        }
      }
    });

    test('each club fills its end of the level without covering the floor or a suite', () {
      // Points just inside the floor's ends must not fall in a club.
      for (final probe in <PlanPoint>[(205, 415), (1015, 415), (610, 415)]) {
        expect(_contains(premiumLevelBowlEdge, probe), isTrue);
        for (final club in premiumLevelClubs) {
          expect(
            _contains(club.points, probe),
            isFalse,
            reason: '${club.mapArea} $probe',
          );
        }
      }
      for (final suite in premiumLevelSuites) {
        final c = center(suite.points);
        for (final club in premiumLevelClubs) {
          expect(
            _contains(club.points, c),
            isFalse,
            reason: '${club.mapArea} over ${suite.number}',
          );
        }
      }
      for (final club in premiumLevelClubs) {
        final c = (club.mapArea == 'club_a') ? (180.0, 415.0) : (1045.0, 415.0);
        expect(_contains(club.points, c), isTrue, reason: club.mapArea);
        expect(
          premiumLevelSuites.where((s) => _contains(s.points, c)),
          isEmpty,
        );
      }
    });

    test(
      'a space with a map area is placed as that club, never by its name',
      () {
        expect(planAreaId('Premium Club A', 'club_a'), 'club_a');
        expect(planAreaId('Club by 201', 'club_b'), 'club_b');
        expect(planAreaId('Suite 204', null), '204');
        expect(planAreaId('Suite 204', 'unknown_area'), isNull);
        expect(planAreaId('Main Arena Floor', arenaFloorArea), arenaFloorArea);
        expect(isClubArea(arenaFloorArea), isFalse);
        expect(planAreaId('Concourse', concourseArea), concourseArea);
        expect(isClubArea(concourseArea), isFalse);
        expect(isClubArea('club_a'), isTrue);
        expect(isClubArea('204'), isFalse);
      },
    );
  });

  group('seating sections', () {
    test('the lower bowl rings the arena floor, inside its edge', () {
      expect(lowerBowlSections, hasLength(21));
      for (final section in lowerBowlSections) {
        for (final (x, y) in section.points) {
          // Nudged a hair toward the center, so a point on the edge counts as inside.
          final p = (x + (610.5 - x) * 0.001, y + (415.2 - y) * 0.001);
          expect(
            _contains(premiumLevelBowlEdge, p),
            isTrue,
            reason: '${section.name} $p',
          );
        }
      }
      // The middle of the floor stays open.
      for (final section in lowerBowlSections) {
        expect(_contains(section.points, (610.5, 415.2)), isFalse);
      }
    });

    test('the West Club sections cover the West Club', () {
      final westClub = premiumLevelClubs.firstWhere(
        (c) => c.mapArea == 'club_a',
      );
      expect(westClub.label, 'West Club');
      expect(
        premiumLevelClubs.firstWhere((c) => c.mapArea == 'club_b').label,
        'Loge Club',
      );
      for (final probe in <PlanPoint>[(180, 415), (215, 270), (215, 560)]) {
        expect(
          westClubSections.where((s) => _contains(s.points, probe)),
          hasLength(1),
          reason: '$probe',
        );
      }
    });
  });

  group('renaming spaces', () {
    test('a pinned space stays in place whatever it is called', () {
      expect(planAreaId('Suite 304', '204'), '204');
      expect(planAreaId('Owners Lounge', '204'), '204');
      expect(planAreaId('Suite 204', '999'), isNull);
      // Unpinned spaces still match by the plan number in their name.
      expect(planAreaId('Suite 207', null), '207');
    });

    test('every map position can be chosen once', () {
      final ids = mapPositions.map((p) => p.id).toList();
      expect(ids, hasLength(premiumLevelAreaCount));
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.every(isMapArea), isTrue);
    });

    test('map labels come from the name', () {
      expect(mapLabel('Suite 304'), '304');
      expect(mapLabel('suite 12A'), '12A');
      expect(mapLabel('Premium Club A'), 'Club A');
      expect(mapLabel('Owners Club'), 'Owners Club');
      expect(mapLabel('The Very Long Executive Club Name'), 'The Very Long E…');
      expect(mapLabel('Suite'), 'Suite');
    });
  });
}
