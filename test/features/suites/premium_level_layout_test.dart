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
}
