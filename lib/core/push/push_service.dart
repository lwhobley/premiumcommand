import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_route.dart';

/// Registers this device for push notifications. Does nothing until [initialize] succeeds, so
/// demo mode, tests, and builds without Firebase keep working.
class PushService {
  static bool _ready = false;

  // A tapped alert opens the screen it is about. A tap that arrives while signed out is held
  // until sign-in, so the router can take it once there is a session.
  static final _routeTaps = StreamController<String>.broadcast();
  static String? _pendingRoute;

  static Stream<String> get routeTaps => _routeTaps.stream;

  static String? takePendingRoute() {
    final route = _pendingRoute;
    _pendingRoute = null;
    return route;
  }

  static void _routeTap(RemoteMessage message) {
    String? text(Object? value) =>
        value is String && value.isNotEmpty ? value : null;
    final route = pushRouteFor(
      kind: text(message.data['kind']),
      conversationId: text(message.data['conversation_id']),
      eventId: text(message.data['event_id']),
    );
    _pendingRoute = route;
    _routeTaps.add(route);
  }

  StreamSubscription<String>? _refresh;
  Timer? _retry;
  String? _token;
  bool _active = false;

  /// Called once at startup. Push is optional: any failure leaves the app running without it.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
      _ready = true;
      // Alerts tapped while the app is in the background, and the one that launched it.
      FirebaseMessaging.onMessageOpenedApp.listen(_routeTap);
      final launch = await FirebaseMessaging.instance.getInitialMessage();
      if (launch != null) _routeTap(launch);
    } catch (_) {
      _ready = false;
    }
  }

  /// Asks for permission and links this device to the signed-in user.
  Future<void> start(SupabaseClient client) async {
    if (!_ready) return;
    _active = true;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // Show alerts while the app is open too.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        sound: true,
      );
      await _refresh?.cancel();
      _refresh = messaging.onTokenRefresh.listen((token) {
        _token = token;
        unawaited(_register(client, token));
      });
      await _tryRegister(client, messaging);
    } catch (_) {
      // No notification permission or no network: the in-app inbox still works.
    }
  }

  /// Stops pushes to this device for the person who is signing out.
  Future<void> stop(SupabaseClient client) async {
    _active = false;
    _retry?.cancel();
    _retry = null;
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
      await client.rpc(
        'register_device_token',
        params: {
          'p_token': token,
          'p_platform': defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
        },
      );
    } catch (_) {}
  }

  Future<void> _tryRegister(
    SupabaseClient client,
    FirebaseMessaging messaging, [
    int attempt = 0,
  ]) async {
    if (!_active) return;
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await messaging.getAPNSToken() == null) {
      if (attempt < 12) {
        _retry = Timer(
          const Duration(seconds: 5),
          () => unawaited(_tryRegister(client, messaging, attempt + 1)),
        );
      }
      return;
    }
    try {
      _token = await messaging.getToken();
      if (_active && _token != null) await _register(client, _token!);
    } catch (_) {
      if (attempt < 12) {
        _retry = Timer(
          const Duration(seconds: 5),
          () => unawaited(_tryRegister(client, messaging, attempt + 1)),
        );
      }
    }
  }
}
