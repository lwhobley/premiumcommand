import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A write saved on this device, waiting to reach the server.
/// [id] is a client-generated key. The server treats repeated sends of the same id as one action.
class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.userId = '',
    this.attempts = 0,
    this.needsReview = false,
    this.lastError = '',
  });

  final String id;
  final String kind;

  /// Who made the change. Only this user's session may send it, so a shared device cannot
  /// send one person's queued work under another person's account.
  final String userId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;

  /// Set when the server refused the write because the record changed. Kept, never auto-applied.
  final bool needsReview;
  final String lastError;

  OutboxItem copyWith({int? attempts, bool? needsReview, String? lastError}) => OutboxItem(
        id: id,
        kind: kind,
        payload: payload,
        createdAt: createdAt,
        userId: userId,
        attempts: attempts ?? this.attempts,
        needsReview: needsReview ?? this.needsReview,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'payload': payload,
        'user_id': userId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'needs_review': needsReview,
        'last_error': lastError,
      };

  factory OutboxItem.fromJson(Map<String, dynamic> json) => OutboxItem(
        id: json['id'] as String,
        kind: json['kind'] as String,
        payload: (json['payload'] as Map).cast<String, dynamic>(),
        userId: (json['user_id'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        needsReview: json['needs_review'] as bool? ?? false,
        lastError: (json['last_error'] as String?) ?? '',
      );
}

/// Persistent queue. Storage problems never block the app: if preferences fail, the queue
/// stays in memory for this session.
class OutboxStore {
  OutboxStore({this._prefs});

  static const _key = 'cutx.outbox.v1';

  SharedPreferences? _prefs;
  List<OutboxItem> _items = [];

  List<OutboxItem> get items => List.unmodifiable(_items);

  Future<void> load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        _items = (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(OutboxItem.fromJson).toList();
      }
    } catch (_) {
      _items = [];
    }
  }

  Future<void> _save() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_key, jsonEncode([for (final i in _items) i.toJson()]));
    } catch (_) {
      // Keep the in-memory queue; persistence is best-effort.
    }
  }

  /// Adds an item unless one with the same id already exists, so enqueueing twice is harmless.
  Future<void> add(OutboxItem item) async {
    if (_items.any((i) => i.id == item.id)) return;
    _items = [..._items, item];
    await _save();
  }

  Future<void> replace(OutboxItem item) async {
    _items = [for (final i in _items) i.id == item.id ? item : i];
    await _save();
  }

  Future<void> remove(String id) async {
    _items = _items.where((i) => i.id != id).toList();
    await _save();
  }
}

/// Last-known lists for read screens, so a dropped connection does not blank the board.
class OfflineCache {
  OfflineCache({this._prefs});

  SharedPreferences? _prefs;

  Future<SharedPreferences?> _instance() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      return _prefs;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> read(String key) async {
    final prefs = await _instance();
    final raw = prefs?.getString(key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, List<Map<String, dynamic>> rows) async {
    final prefs = await _instance();
    await prefs?.setString(key, jsonEncode(rows));
  }
}

/// The last signed-in session, kept so the app can open without a connection.
class SessionCache {
  SessionCache({this.prefs});

  static const _key = 'cutx.session.v1';

  final SharedPreferences? prefs;

  Future<SharedPreferences?> _instance() async {
    try {
      return prefs ?? await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> read() async {
    final p = await _instance();
    final raw = p?.getString(_key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> session) async {
    final p = await _instance();
    await p?.setString(_key, jsonEncode(session));
  }

  Future<void> clear() async {
    final p = await _instance();
    await p?.remove(_key);
  }
}
