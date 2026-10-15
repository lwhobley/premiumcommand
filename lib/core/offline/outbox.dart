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
    this.venueId = '',
    this.attempts = 0,
    this.needsReview = false,
    this.lastError = '',
  });

  final String id;
  final String kind;

  /// Who made the change. Only this user's session may send it, so a shared device cannot
  /// send one person's queued work under another person's account.
  final String userId;
  final String venueId;
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
        venueId: venueId,
        attempts: attempts ?? this.attempts,
        needsReview: needsReview ?? this.needsReview,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'payload': payload,
        'user_id': userId,
        'venue_id': venueId,
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
        venueId: (json['venue_id'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        needsReview: (json['needs_review'] as bool? ?? false) ||
            (json['venue_id'] as String? ?? '').isEmpty,
        lastError: (json['venue_id'] as String? ?? '').isEmpty
            ? 'Venue identity missing. Review this saved change before retrying.'
            : (json['last_error'] as String?) ?? '',
      );
}

/// Persistent queue. Storage problems never block the app: if preferences fail, the queue
/// stays in memory for this session.
class OutboxStore {
  OutboxStore({this._prefs});

  static const _key = 'cutx.outbox.v1';

  SharedPreferences? _prefs;
  List<OutboxItem> _items = [];
  Future<void>? _loadFuture;
  Future<void> _writeTail = Future.value();

  List<OutboxItem> get items => List.unmodifiable(_items);

  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final recovered = <OutboxItem>[];
      for (final value in decoded) {
        try {
          recovered.add(OutboxItem.fromJson((value as Map).cast<String, dynamic>()));
        } catch (_) {
          // Keep the other queued writes when one saved record is corrupt.
        }
      }
      _items = recovered;
    } catch (_) {
      // A storage failure must not erase writes already held in memory.
    }
  }

  Future<void> _save() {
    final snapshot = jsonEncode([for (final i in _items) i.toJson()]);
    return _writeTail = _writeTail.then((_) async {
      try {
        _prefs ??= await SharedPreferences.getInstance();
        await _prefs!.setString(_key, snapshot);
      } catch (_) {
        // Keep the in-memory queue; persistence is best-effort.
      }
    });
  }

  /// Adds an item unless one with the same id already exists, so enqueueing twice is harmless.
  Future<void> add(OutboxItem item) async {
    await load();
    if (_items.any((i) => i.id == item.id)) return;
    _items = [..._items, item];
    await _save();
  }

  Future<void> replace(OutboxItem item) async {
    await load();
    _items = [for (final i in _items) i.id == item.id ? item : i];
    await _save();
  }

  Future<void> remove(String id) async {
    await load();
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
