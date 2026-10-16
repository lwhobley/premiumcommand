import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local session deadlines survive app restarts. This is not a server token policy.
class SessionTimingStore {
  static const key = 'cutx.session_timing.v1';
  Future<void> _tail = Future.value();

  Future<Map<String, dynamic>?> read() async {
    await _tail;
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String userId, DateTime started, DateTime activity) =>
      _enqueue(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          key,
          jsonEncode({
            'user_id': userId,
            'started': started.toUtc().toIso8601String(),
            'activity': activity.toUtc().toIso8601String(),
          }),
        );
      });

  Future<void> clear() => _enqueue(() async {
    await (await SharedPreferences.getInstance()).remove(key);
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.catchError((_) {});
    return next;
  }
}
