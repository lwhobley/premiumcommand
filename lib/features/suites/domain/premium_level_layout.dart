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

/// A premium club: one of the two open ends of the premium level, identified as
/// clubs by the venue operator on October 16, 2026. Not drawn on the supplied plan,
/// so each outline fills the concourse between the arena floor's edge and the
/// level's outer edge, from the last suite on one side to the first on the other.
class ClubOutline {
  const ClubOutline(this.mapArea, this.label, this.place, this.points);

  /// Stored in `venue_suites.map_area` for the space drawn here.
  final String mapArea;

  /// Short label on the map.
  final String label;

  /// Where it is, for people choosing it: 'between suites 229 and 201'.
  final String place;
  final List<PlanPoint> points;
}

const premiumLevelClubs = <ClubOutline>[
  // Between 229 and 201: from 201's inner corner, along the floor's edge, to 229's.
  ClubOutline('club_a', 'West Club', 'between suites 229 and 201', [
    (237.5, 206.0),
    (252.0, 221.0),
    (195.0, 318.0),
    (195.0, 512.4),
    (252.0, 609.4),
    (237.5, 624.4),
    (166.0, 512.4),
    (166.0, 318.0),
  ]),
  // Between 215 and 216: from 215's inner edge, around the floor's edge, to 216's end wall.
  ClubOutline('club_b', 'Loge Club', 'between suites 215 and 216', [
    (906.8, 193.5),
    (934.0, 145.6),
    (1000.0, 205.0),
    (1066.0, 318.0),
    (1066.0, 512.4),
    (1000.0, 625.0),
    (870.3, 718.7),
    (870.3, 701.9),
    (862.5, 683.4),
    (857.8, 665.8),
    (965.0, 603.9),
    (1026.0, 512.4),
    (1026.0, 318.0),
    (965.0, 226.5),
  ]),
];

/// A seating section from the venue's seating chart (supplied October 16, 2026), drawn
/// for orientation. Sections are not spaces: they cannot be selected or ordered for.
class SectionOutline {
  const SectionOutline(this.name, this.points);

  /// The number on the chart: '104', or 'W242' for a West Club section.
  final String name;
  final List<PlanPoint> points;
}

/// The lower bowl, sections 100 through 120, ringing the arena floor below the suites.
/// Traced from the seating chart and fitted to the plan by the suites both show.
const lowerBowlSections = <SectionOutline>[
  SectionOutline('100', [
    (220.5, 285.6),
    (200.6, 320.6),
    (200.5, 409.4),
    (249.1, 409.1),
    (251.0, 398.6),
    (290.6, 398.3),
    (292.4, 408.8),
    (324.8, 408.5),
    (324.9, 356.3),
    (332.1, 345.8),
    (303.3, 330.3),
    (296.1, 339.1),
    (260.1, 318.4),
    (261.9, 308.0),
  ]),
  SectionOutline('101', [
    (254.8, 227.9),
    (229.5, 271.6),
    (272.7, 295.7),
    (278.1, 286.9),
    (314.1, 305.8),
    (310.5, 314.6),
    (341.1, 330.0),
    (351.9, 316.0),
    (335.8, 288.3),
    (326.8, 291.8),
    (305.2, 258.9),
    (314.2, 251.9),
    (290.8, 210.2),
  ]),
  SectionOutline('102', [
    (404.4, 176.3),
    (348.5, 176.7),
    (305.2, 201.4),
    (328.6, 243.0),
    (337.6, 237.7),
    (359.2, 274.2),
    (350.2, 279.5),
    (366.4, 307.2),
    (388.0, 296.6),
    (404.2, 296.5),
    (404.3, 265.1),
    (393.4, 263.5),
    (393.5, 225.2),
    (404.3, 223.3),
  ]),
  SectionOutline('103', [
    (422.4, 176.2),
    (422.3, 223.2),
    (433.1, 224.9),
    (433.1, 263.2),
    (422.3, 265.0),
    (422.2, 296.3),
    (499.7, 295.8),
    (499.7, 264.4),
    (488.9, 262.8),
    (489.0, 224.5),
    (499.8, 222.6),
    (499.8, 175.6),
  ]),
  SectionOutline('104', [
    (517.9, 175.5),
    (517.8, 222.5),
    (528.6, 224.2),
    (528.6, 262.5),
    (517.8, 264.3),
    (517.7, 295.7),
    (595.2, 295.1),
    (595.2, 263.7),
    (584.4, 262.1),
    (584.5, 223.8),
    (595.3, 221.9),
    (595.3, 174.9),
  ]),
  SectionOutline('105', [
    (611.5, 174.8),
    (611.5, 221.8),
    (622.3, 223.5),
    (622.2, 261.8),
    (611.4, 263.6),
    (611.4, 295.0),
    (688.9, 294.4),
    (688.9, 263.1),
    (678.1, 261.4),
    (678.1, 223.1),
    (689.0, 221.3),
    (689.0, 174.2),
  ]),
  SectionOutline('106', [
    (707.0, 174.1),
    (707.0, 221.1),
    (717.8, 222.8),
    (717.7, 261.1),
    (706.9, 262.9),
    (706.9, 294.3),
    (784.3, 293.7),
    (784.4, 262.4),
    (773.6, 260.7),
    (773.6, 222.4),
    (784.4, 220.6),
    (784.5, 173.5),
  ]),
  SectionOutline('107', [
    (802.5, 173.4),
    (802.5, 220.4),
    (813.3, 222.1),
    (813.2, 260.4),
    (802.4, 262.2),
    (802.4, 293.6),
    (818.6, 293.5),
    (840.2, 303.8),
    (856.4, 275.8),
    (847.4, 270.6),
    (869.1, 233.9),
    (878.1, 239.0),
    (901.6, 197.1),
    (858.4, 173.0),
  ]),
  SectionOutline('108', [
    (965.0, 226.5),
    (919.9, 200.5),
    (892.5, 247.6),
    (901.5, 252.8),
    (894.3, 265.1),
    (906.9, 273.7),
    (921.3, 297.9),
    (988.0, 261.1),
  ]),
  SectionOutline('109', [
    (997.5, 275.3),
    (991.5, 276.5),
    (874.4, 341.8),
    (881.6, 352.2),
    (881.5, 376.6),
    (1022.1, 375.6),
    (1022.1, 312.2),
  ]),
  SectionOutline('110', [
    (973.4, 393.4),
    (973.3, 429.9),
    (1022.0, 429.6),
    (1022.0, 393.0),
  ]),
  SectionOutline('111', [
    (881.4, 448.0),
    (881.4, 472.4),
    (874.2, 482.9),
    (991.2, 546.5),
    (1000.2, 548.2),
    (1021.9, 511.4),
    (1022.0, 447.0),
  ]),
  SectionOutline('112', [
    (921.0, 526.1),
    (906.5, 550.6),
    (893.9, 559.4),
    (901.1, 571.5),
    (892.1, 576.8),
    (922.3, 628.5),
    (965.0, 603.9),
    (988.3, 568.9),
    (991.2, 563.9),
  ]),
  SectionOutline('113', [
    (818.3, 532.1),
    (802.1, 532.2),
    (802.0, 563.5),
    (812.8, 565.2),
    (812.8, 603.5),
    (802.0, 605.3),
    (801.9, 652.4),
    (856.0, 652.0),
    (861.9, 663.4),
    (907.8, 636.9),
    (877.7, 585.6),
    (868.7, 590.9),
    (847.1, 556.2),
    (856.1, 549.2),
    (839.9, 521.5),
  ]),
  SectionOutline('114', [
    (706.6, 532.9),
    (706.5, 564.2),
    (717.4, 565.9),
    (717.3, 604.2),
    (706.5, 606.0),
    (706.4, 653.0),
    (783.9, 652.5),
    (784.0, 605.5),
    (773.2, 603.8),
    (773.2, 565.5),
    (784.0, 563.7),
    (784.1, 532.3),
  ]),
  SectionOutline('115', [
    (611.1, 533.6),
    (611.1, 564.9),
    (621.9, 566.6),
    (621.8, 604.9),
    (611.0, 606.7),
    (611.0, 653.7),
    (688.4, 653.2),
    (688.5, 606.2),
    (677.7, 604.5),
    (677.7, 566.2),
    (688.5, 564.4),
    (688.6, 533.0),
  ]),
  SectionOutline('116', [
    (517.4, 534.3),
    (517.4, 565.6),
    (528.2, 567.3),
    (528.1, 605.6),
    (517.3, 607.4),
    (517.3, 654.4),
    (594.7, 653.9),
    (594.8, 606.8),
    (584.0, 605.2),
    (584.0, 566.9),
    (594.8, 565.0),
    (594.9, 533.7),
  ]),
  SectionOutline('117', [
    (421.9, 534.9),
    (421.9, 566.3),
    (432.7, 568.0),
    (432.7, 606.3),
    (421.8, 608.1),
    (421.8, 655.1),
    (499.3, 654.6),
    (499.3, 607.5),
    (488.5, 605.9),
    (488.5, 571.0),
    (468.7, 571.2),
    (466.9, 555.5),
    (466.9, 566.0),
    (461.5, 567.7),
    (457.9, 564.3),
    (456.1, 552.1),
    (461.6, 548.6),
    (467.0, 552.0),
    (467.0, 534.6),
  ]),
  SectionOutline('118', [
    (366.1, 524.9),
    (349.8, 552.9),
    (358.9, 558.0),
    (337.2, 594.8),
    (328.2, 589.6),
    (304.7, 631.6),
    (347.9, 655.7),
    (403.8, 655.2),
    (403.8, 608.2),
    (393.0, 606.6),
    (393.1, 568.2),
    (403.9, 566.4),
    (403.9, 535.1),
    (387.7, 535.2),
  ]),
  SectionOutline('119', [
    (340.9, 502.4),
    (310.3, 518.3),
    (317.5, 520.0),
    (315.6, 537.5),
    (310.2, 534.0),
    (310.2, 528.8),
    (279.6, 546.4),
    (272.4, 537.8),
    (229.1, 562.5),
    (254.3, 605.8),
    (290.3, 623.0),
    (313.8, 581.0),
    (304.8, 574.1),
    (326.4, 540.9),
    (335.4, 544.3),
    (351.7, 516.3),
  ]),
  SectionOutline('120', [
    (200.5, 425.1),
    (200.4, 513.9),
    (220.1, 548.6),
    (261.6, 525.7),
    (259.8, 515.2),
    (295.9, 494.1),
    (303.1, 502.7),
    (331.9, 486.8),
    (324.7, 476.4),
    (324.8, 424.2),
    (292.4, 424.4),
    (290.5, 434.9),
    (250.9, 435.2),
    (249.1, 424.7),
  ]),
];

/// The West Club's seating, W244 at suite 201's end to W240 at suite 229's: five
/// equal bands across the club. The chart draws these as thin strips at that end.
const westClubSections = <SectionOutline>[
  SectionOutline('W244', [
    (252.0, 221.0),
    (209.5, 293.3),
    (188.0, 283.6),
    (237.5, 206.0),
  ]),
  SectionOutline('W243', [
    (209.5, 293.3),
    (195.0, 318.0),
    (195.0, 373.3),
    (166.0, 369.2),
    (166.0, 318.0),
    (188.0, 283.6),
  ]),
  SectionOutline('W242', [
    (195.0, 373.3),
    (195.0, 457.1),
    (166.0, 461.2),
    (166.0, 369.2),
  ]),
  SectionOutline('W241', [
    (195.0, 457.1),
    (195.0, 512.4),
    (209.5, 537.1),
    (188.0, 546.8),
    (166.0, 512.4),
    (166.0, 461.2),
  ]),
  SectionOutline('W240', [
    (209.5, 537.1),
    (252.0, 609.4),
    (237.5, 624.4),
    (188.0, 546.8),
  ]),
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

/// The arena floor as a serviceable space, stored in `venue_suites.map_area`. Its
/// outline is [premiumLevelBowlEdge]; it is drawn flat at ground level, not raised.
const arenaFloorArea = 'arena_floor';

/// The concourse as a serviceable space, stored in `venue_suites.map_area`: the lower
/// level's walkway, wrapping around behind the lower bowl beneath the premium level.
/// Its outline is [premiumLevelFootprint] around [premiumLevelBowlEdge], drawn flat
/// at ground level under the raised premium level.
const concourseArea = 'concourse';

/// The map outline a premium space is drawn as. [mapArea] (`venue_suites.map_area`)
/// pins it to a plan suite number, a club, the arena floor, or the concourse, so its name and number
/// can change freely. A space without one falls back to the plan number in its name.
/// Null when it is not on the map.
String? planAreaId(String name, String? mapArea) {
  if (mapArea != null) return isMapArea(mapArea) ? mapArea : null;
  return planSuiteNumber(name);
}

/// True when [areaId] is a position on the map: a plan suite number, a club, the floor,
/// or the concourse.
bool isMapArea(String areaId) =>
    areaId == arenaFloorArea ||
    areaId == concourseArea ||
    premiumLevelClubs.any((c) => c.mapArea == areaId) ||
    premiumLevelSuites.any((s) => s.number == areaId);

/// Every position a space can be placed on, with a description for choosing it.
List<({String id, String label})> get mapPositions => [
  for (final suite in premiumLevelSuites)
    (id: suite.number, label: 'Plan suite ${suite.number}'),
  for (final club in premiumLevelClubs)
    (id: club.mapArea, label: '${club.label}, ${club.place}'),
  (id: arenaFloorArea, label: 'Arena floor, the open center'),
  (id: concourseArea, label: 'Concourse, the lower level around the bowl'),
];

/// The short label drawn on the map for a space: its name without a leading
/// "Suite" or "Premium", shortened to fit ('Suite 304' -> '304').
String mapLabel(String name) {
  final short = name.trim().replaceFirst(
    RegExp(r'^(suite|premium)\s+', caseSensitive: false),
    '',
  );
  final label = short.isEmpty ? name.trim() : short;
  return label.length <= 16 ? label : '${label.substring(0, 15)}…';
}

/// True when [areaId] is a club rather than a suite.
bool isClubArea(String areaId) =>
    premiumLevelClubs.any((c) => c.mapArea == areaId);

/// Every space drawn on the map: 29 suites, 2 clubs, the arena floor, and the concourse.
int get premiumLevelAreaCount =>
    premiumLevelSuites.length + premiumLevelClubs.length + 2;
