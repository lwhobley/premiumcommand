import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const _key = 'cutx.install_id';

/// A random ID for this install, sent with each PIN sign-in. The server locks sign-in after
/// repeated wrong PINs from one device, and this is the device it counts. The value is kept on
/// the device; it is not tied to a person and carries no account information.
///
/// If the ID cannot be saved, a new one is made for each attempt. Those attempts are then
/// counted only by network address.
Future<String> deviceInstallId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.length >= 16) return existing;
    final id = _randomId();
    await prefs.setString(_key, id);
    return id;
  } catch (_) {
    return _randomId();
  }
}

String _randomId() {
  final rng = Random.secure();
  return List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
}
