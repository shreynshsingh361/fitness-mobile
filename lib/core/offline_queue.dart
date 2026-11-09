import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

/// What to tell someone whose change was kept for later instead of saved.
const savedOffline = 'No internet. Saved on your phone, it will be sent when you are back online.';

/// One change waiting for the internet: a food added to a meal, or water added or taken off.
class PendingOp {
  const PendingOp({
    required this.id,
    required this.kind,
    required this.method,
    required this.path,
    required this.label,
    required this.date,
    this.body,
    this.query,
    this.deltaMl = 0,
  });

  /// Made once per tap. It is also sent to the server (client_op_id), which applies a request
  /// it has seen twice only once, so a retry can never double an entry.
  final String id;
  final String kind; // 'food' or 'water'
  final String method; // 'post' or 'delete'
  final String path;
  final String label; // what to call it on screen: "Idli (breakfast)", "+250 ml water"
  final String date; // the day it belongs to
  final Map<String, dynamic>? body;
  final Map<String, dynamic>? query;
  final int deltaMl; // water only: +250 or -250

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'method': method,
    'path': path,
    'label': label,
    'date': date,
    'body': body,
    'query': query,
    'delta_ml': deltaMl,
  };

  factory PendingOp.fromJson(Map<String, dynamic> j) => PendingOp(
    id: j['id'] as String,
    kind: j['kind'] as String,
    method: j['method'] as String,
    path: j['path'] as String,
    label: j['label'] as String,
    date: j['date'] as String,
    body: (j['body'] as Map?)?.cast<String, dynamic>(),
    query: (j['query'] as Map?)?.cast<String, dynamic>(),
    deltaMl: (j['delta_ml'] as int?) ?? 0,
  );
}

/// A server answer that means "try again later" rather than "no".
bool isRetryable(Object error) {
  if (error is! ApiException) return false;
  final s = error.status;
  // 0 = could not reach the server at all. 401 is kept too: the session may be refreshed, and
  // someone's entry must not be thrown away because their login had expired.
  return s == 0 || s == 401 || s == 408 || s == 429 || s == 502 || s == 503 || s == 504;
}

/// Changes made without internet. They are kept on the phone and sent, in order, as soon as the
/// server can be reached again.
///
/// Only changes that are safe to send twice are queued: each carries a client_op_id that the
/// server applies once. Deleting a food or resetting a day's water is never queued: it asks for
/// a confirmation and needs the server's answer.
class OfflineQueue extends ChangeNotifier {
  OfflineQueue(this._api, this._userId, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'fitness.offline_queue';

  final ApiClient _api;
  final String? Function() _userId;
  final FlutterSecureStorage _storage;

  final _ops = <PendingOp>[];
  final _problems = <String>[];
  String? _loadedFor;
  bool _flushing = false;

  List<PendingOp> get pending => List.unmodifiable(_ops);
  bool get hasPending => _ops.isNotEmpty;

  /// Changes the server refused for good (the food no longer exists, say). Shown once.
  List<String> get problems => List.unmodifiable(_problems);

  void clearProblems() {
    if (_problems.isEmpty) return;
    _problems.clear();
    notifyListeners();
  }

  /// Food waiting to be saved to [date].
  List<PendingOp> pendingFood(String date) => [
    for (final op in _ops)
      if (op.kind == 'food' && op.date == date) op,
  ];

  /// What the water waiting for [date] adds up to, so the screen can show it right away.
  int pendingWaterMl(String date) =>
      _ops.where((o) => o.kind == 'water' && o.date == date).fold(0, (a, o) => a + o.deltaMl);

  /// Reads what was saved last time. Call when the app starts; the other methods do it too.
  Future<void> load() => _ensureLoaded();

  Future<void> _ensureLoaded() async {
    final user = _userId();
    if (user == null || _loadedFor == user) return;
    _loadedFor = user;
    _ops.clear();
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      // Changes made by someone else on this phone are not this person's to send.
      if (json['user'] != user) return;
      _ops.addAll((json['ops'] as List).map((o) => PendingOp.fromJson(o as Map<String, dynamic>)));
      notifyListeners();
    } catch (_) {
      // Unreadable: nothing to send.
    }
  }

  Future<void> _save() async {
    try {
      if (_ops.isEmpty) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(
          key: _key,
          value: jsonEncode({'user': _loadedFor, 'ops': _ops.map((o) => o.toJson()).toList()}),
        );
      }
    } catch (_) {
      // Not saved: it still gets sent while the app is open.
    }
  }

  Future<void> _run(PendingOp op) => switch (op.method) {
    'post' => _api.post(op.path, body: op.body),
    'delete' => _api.delete(op.path, query: op.query),
    _ => throw StateError('unknown method ${op.method}'),
  };

  /// Sends [op] now. Without internet it is kept and sent later: returns false then, true when
  /// it went through. A real refusal from the server (not a connection problem) is thrown.
  Future<bool> send(PendingOp op) async {
    await _ensureLoaded();
    // Earlier changes go first, so adding and then removing water cannot swap places.
    if (_ops.isNotEmpty) await flush();
    if (_ops.isEmpty) {
      try {
        await _run(op);
        return true;
      } catch (error) {
        if (!isRetryable(error)) rethrow;
      }
    }
    _ops.add(op);
    notifyListeners();
    await _save();
    return false;
  }

  /// Sends what is waiting, oldest first, and stops at the first connection problem. Returns
  /// how many changes went through.
  Future<int> flush() async {
    await _ensureLoaded();
    if (_flushing || _ops.isEmpty) return 0;
    _flushing = true;
    var done = 0;
    try {
      while (_ops.isNotEmpty) {
        final op = _ops.first;
        try {
          await _run(op);
          done++;
        } catch (error) {
          if (isRetryable(error)) break; // still offline: try again later
          _problems.add('${op.label}: ${messageOf(error)}');
        }
        _ops.removeAt(0);
        await _save();
        notifyListeners();
      }
    } finally {
      _flushing = false;
    }
    return done;
  }
}

/// One queue for the whole app. Screens listen to it (ListenableBuilder) to show what is waiting.
final offlineQueueProvider = Provider<OfflineQueue>((ref) {
  final sessions = ref.watch(sessionStoreProvider);
  final queue = OfflineQueue(ref.watch(apiProvider), () => sessions.session?.user.id);
  ref.onDispose(queue.dispose);
  return queue;
});
