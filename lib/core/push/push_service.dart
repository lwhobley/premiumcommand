import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registers this device for push notifications. Does nothing until [initialize] succeeds, so
/// demo mode, tests, and builds without Firebase keep working.
class PushService {
  static bool _ready = false;
  StreamSubscription<String>? _refresh;
  String? _token;

  /// Called once at startup. Push is optional: any failure leaves the app running without it.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Asks for permission and links this device to the signed-in user.
  Future<void> start(SupabaseClient client) async {
    if (!_ready) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // Show alerts while the app is open too.
      await messaging.setForegroundNotificationPresentationOptions(alert: true, sound: true);
      _token = await messaging.getToken();
      if (_token != null) await _register(client, _token!);
      await _refresh?.cancel();
      _refresh = messaging.onTokenRefresh.listen((token) {
        _token = token;
        _register(client, token);
      });
    } catch (_) {
      // No notification permission or no network: the in-app inbox still works.
    }
  }

  /// Stops pushes to this device for the person who is signing out.
  Future<void> stop(SupabaseClient client) async {
    await _refresh?.cancel();
    _refresh = null;
    final token = _token;
    _token = null;
    if (!_ready || token == null) return;
    try {
      await client.rpc('unregister_device_token', params: {'p_token': token});
    } catch (_) {
      // Offline sign-out: the next sign-in on this device re-assigns the token anyway.
    }
  }

  Future<void> _register(SupabaseClient client, String token) async {
    try {
      await client.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      });
    } catch (_) {}
  }
}
