import 'package:cutx_premium_command/features/staff/application/staff_providers.dart';
import 'package:cutx_premium_command/features/staff/data/staff_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Photos implements StaffRepository {
  int requests = 0;

  @override
  Future<String> photoUrl(String path) async =>
      'https://example.test/$path?token=${++requests}';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a long shift renews photo links before they expire', (
    tester,
  ) async {
    final photos = _Photos();
    final container = ProviderContainer(
      overrides: [staffRepositoryProvider.overrideWithValue(photos)],
    );
    final provider = staffPhotoUrlProvider('venue/person.jpg');
    container.listen(provider, (_, _) {});
    expect(await container.read(provider.future), endsWith('token=1'));
    await tester.pump(const Duration(minutes: 55));
    await tester.pump();
    expect(await container.read(provider.future), endsWith('token=2'));
    container.dispose();
    await tester.pump(const Duration(hours: 1));
    expect(photos.requests, 2);
  });
}
