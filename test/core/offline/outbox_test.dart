import 'dart:convert';

import 'package:cutx_premium_command/core/offline/outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  OutboxItem item(String id) => OutboxItem(
        id: id,
        kind: 'set_task_status',
        payload: const {'task_id': 'task', 'status': 'completed'},
        userId: 'user-a',
        venueId: 'venue-a',
        createdAt: DateTime.utc(2026, 10, 14),
      );

  test('keeps a new write when loading saved work at the same time', () async {
    SharedPreferences.setMockInitialValues({
      'cutx.outbox.v1': jsonEncode([item('saved').toJson()]),
    });
    final store = OutboxStore();
    final loading = store.load();
    await store.add(item('new'));
    await loading;
    expect(store.items.map((entry) => entry.id), ['saved', 'new']);
    final reloaded = OutboxStore();
    await reloaded.load();
    expect(reloaded.items.map((entry) => entry.id), ['saved', 'new']);
  });

  test('one malformed saved item does not erase valid queued work', () async {
    SharedPreferences.setMockInitialValues({
      'cutx.outbox.v1': jsonEncode([item('good').toJson(), {'bad': true}]),
    });
    final store = OutboxStore();
    await store.load();
    expect(store.items.map((entry) => entry.id), ['good']);
  });
}
