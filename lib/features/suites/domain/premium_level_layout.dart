/// Premium-level suite outlines traced from the venue's labeled plan
/// ("Suites Labeled.pdf", supplied October 15, 2026). Coordinates are PDF
/// points on the landscape sheet: x runs left to right, y runs top to bottom.
/// The plan has no scale bar, so the 3D map is proportional, not measured.
library;

typedef PlanPoint = (double x, double y);

class SuiteOutline {
  const SuiteOutline(this.number, this.points);

  /// The number printed on the plan, e.g. '204'.
  final String number;
  final List<PlanPoint> points;
}

// Wall lines read from the plan's vector drawing.
const _northBack = 111.7;
const _northFront = 164.6;
const _southFront = 665.8;
const _southBack = 718.8;

/// The top and bottom suite rows mirror each other across this line.
const _mirrorSum = 830.4;

PlanPoint _mirror(PlanPoint p) => (p.$1, _mirrorSum - p.$2);

List<SuiteOutline> _row(
  List<String> numbers,
  List<double> dividers,
  double top,
  double bottom,
) => [
  for (var i = 0; i < numbers.length; i++)
    SuiteOutline(numbers[i], [
      (dividers[i], top),
      (dividers[i + 1], top),
      (dividers[i + 1], bottom),
      (dividers[i], bottom),
    ]),
];

// Corner lounges at the top left (201, 202) and the end suites of the top row
// (203, 214). The bottom-left lounge (229, 228) and bottom-row ends (227, 216)
// are their mirror images on the plan.
const _suite201 = <PlanPoint>[
  (237.5, 168.0),
  (274.0, 146.3),
  (301.6, 194.4),
  (252.0, 221.0),
  (237.5, 206.0),
];
const _suite202 = <PlanPoint>[
  (274.0, 146.3),
  (317.2, 121.6),
  (331.0, 114.5),
  (345.4, 139.5),
  (345.2, 146.6),
  (350.0, 164.6),
  (301.6, 194.4),
];
const _suite203 = <PlanPoint>[
  (346.4, 111.7),
  (384.5, 111.7),
  (384.5, 164.6),
  (350.0, 164.6),
  (345.2, 146.6),
  (346.4, 140.0),
];
const _suite214 = <PlanPoint>[
  (823.5, 111.7),
  (870.3, 111.7),
  (870.3, 128.5),
  (862.5, 147.0),
  (857.8, 164.6),
  (823.5, 164.6),
];
const _suite215 = <PlanPoint>[
  (857.8, 164.6),
  (862.5, 147.0),
  (864.4, 140.8),
  (879.7, 114.2),
  (893.4, 121.6),
  (934.0, 145.6),
  (906.8, 193.5),
];

/// All 29 suites on the plan, 201 through 229.
final List<SuiteOutline> premiumLevelSuites = [
  const SuiteOutline('201', _suite201),
  const SuiteOutline('202', _suite202),
  const SuiteOutline('203', _suite203),
  ..._row(
    ['204', '205', '206', '207', '208', '209', '210', '211', '212', '213'],
    [
      384.5,
      419.5,
      459.0,
      503.7,
      549.0,
      604.0,
      659.0,
      704.3,
      749.0,
      788.5,
      823.5,
    ],
    _northBack,
    _northFront,
  ),
  const SuiteOutline('214', _suite214),
  const SuiteOutline('215', _suite215),
  SuiteOutline('216', _suite214.map(_mirror).toList()),
  ..._row(
    ['217', '218', '219', '220', '221'],
    [823.5, 788.5, 749.0, 704.3, 659.8, 610.0],
    _southFront,
    _southBack,
  ),
  // A corridor separates 221 and 222.
  ..._row(
    ['222', '223', '224', '225', '226'],
    [597.5, 548.2, 503.7, 458.8, 419.5, 384.5],
    _southFront,
    _southBack,
  ),
  SuiteOutline('227', _suite203.map(_mirror).toList()),
  SuiteOutline('228', _suite202.map(_mirror).toList()),
  SuiteOutline('229', _suite201.map(_mirror).toList()),
];

/// Inner edge of the premium level: the outline of the arena floor, which the suites overlook.
final List<PlanPoint> premiumLevelBowlEdge = [
  (350.0, _northFront),
  (857.8, _northFront),
  (965.0, 226.5),
  (1026.0, 318.0),
  (1026.0, 512.4),
  (965.0, 603.9),
  (857.8, _southFront),
  (350.0, _southFront),
  (251.4, 610.4),
  (195.0, 512.4),
  (195.0, 318.0),
  (251.4, 220.0),
];

/// Outer footprint of the premium level (concourse slab).
const List<PlanPoint> premiumLevelFootprint = [
  (164.0, 92.0),
  (1106.0, 92.0),
  (1106.0, 740.0),
  (164.0, 740.0),
];

/// The suite number in a configured suite name ('Suite 204' -> '204'), or
/// null when the name does not contain one of the plan's numbers.
String? planSuiteNumber(String suiteName) {
  for (final match in RegExp(r'\d+').allMatches(suiteName)) {
    final number = match.group(0)!;
    if (premiumLevelSuites.any((s) => s.number == number)) return number;
  }
  return null;
}
