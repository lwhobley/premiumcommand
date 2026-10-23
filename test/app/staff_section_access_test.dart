import 'package:cutx_premium_command/app/app_section.dart';
import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Staff roles (runner, suite attendant, beverage lead) carry operations access only.
  final staff = permissionsFor({
    AppRole.runner,
    AppRole.suiteAttendant,
    AppRole.beverageLead,
  });

  test(
    'staff can open the operational sections and view Floor Plan Studio',
    () {
      expect(AppSection.commandCenter.allows(staff), isTrue);
      expect(AppSection.beoManagement.allows(staff), isTrue);
      expect(AppSection.myShift.allows(staff), isTrue);
      expect(AppSection.floorPlanStudio.allows(staff), isTrue);
    },
  );

  test(
    'staff cannot open Administration, Closeout, or Banquets & Culinary',
    () {
      expect(AppSection.administration.allows(staff), isFalse);
      expect(AppSection.closeout.allows(staff), isFalse);
      expect(AppSection.banquetsCulinary.allows(staff), isFalse);
    },
  );

  test('every section has its own route', () {
    final paths = AppSection.values.map((s) => s.path).toList();
    expect(paths.toSet(), hasLength(paths.length));
    // Navigation highlights whole path segments only.
    expect(AppSection.staffDeployment.matches('/staff-accounts'), isFalse);
    expect(AppSection.staffManagement.matches('/staff-accounts'), isTrue);
    expect(AppSection.eventWorkspace.matches('/events/e1'), isTrue);
  });
}
