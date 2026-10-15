import 'package:cutx_premium_command/features/chat/application/chat_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closing an older thread does not clear the one now open', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final open = container.read(openChatProvider.notifier);

    // Wide screens: chat B opens before chat A is disposed.
    open.open('A');
    open.open('B');
    open.close('A');
    expect(container.read(openChatProvider), 'B');

    open.close('B');
    expect(container.read(openChatProvider), isNull);
  });
}
