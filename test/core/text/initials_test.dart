import 'package:cutx_premium_command/core/text/initials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initials use the first and last name', () {
    expect(initialsFor('ana maria staff'), 'AS');
    expect(initialsFor('  Cher '), 'C');
    expect(initialsFor(''), '?');
  });
}
