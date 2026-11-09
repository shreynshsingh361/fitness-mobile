import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api.dart';
import '../../core/session.dart';
// A browser build cannot even compile the phone health plugin, so the stub is used
// unless the platform has dart:io (a real phone or a simulator).
import 'health_stub.dart' if (dart.library.io) 'health_device.dart';
import 'health_types.dart';

const _connectedKey = 'fitness.health_connected';
const _backfillKey = 'fitness.step_backfill';

/// How many days to read on each sync. The phone keeps counting while the app is
/// closed, so opening it even once in a while loses nothing.
const _syncDays = 14;

/// Reads steps from the phone and sends them to the backend's /steps/sync.
/// Sending the same day twice is harmless: the backend keeps the highest count.
class HealthSync {
  HealthSync(this._api, this._sessions, this.source);

  final ApiClient _api;
  final SessionStore _sessions;
  final HealthSource source;
  final _storage = const FlutterSecureStorage();

  // What was last sent for each day, and for whom. Syncing every couple of seconds would
  // otherwise post the same counts over and over; only a day whose count moved is sent.
  final _sent = <String, int>{};
  String? _sentFor;

  /// True when the last full read (two weeks) found no steps at all. That is not "I walked
  /// nothing": it means the health app holds no steps from any step counter, so the
  /// screen can say what to check instead of showing a silent 0.
  final emptyHealth = ValueNotifier<bool>(false);

  /// The choice is remembered per person. If someone else signs in on this phone, their
  /// account must not silently receive the steps of the phone's owner.
  Future<bool> isConnected() async {
    final userId = _sessions.session?.user.id;
    if (!source.available || userId == null) return false;
    try {
      return await _storage.read(key: _connectedKey) == userId;
    } catch (_) {
      return false;
    }
  }

  /// Turning the feature on is the only moment we ask for permission.
  Future<bool> connect() async {
    final userId = _sessions.session?.user.id;
    if (userId == null || !await source.requestAccess()) return false;
    await _storage.write(key: _connectedKey, value: userId);
    await sync();
    return true;
  }

  Future<void> disconnect() => _storage.delete(key: _connectedKey);

  bool _backfilling = false;

  /// Saves the steps of earlier months to the account, once: every app's history, so the
  /// calendar shows the whole past. Safe to call often: it does nothing when done, and picks
  /// up again if an earlier run was cut short. Sending a day twice is harmless (the backend
  /// keeps the highest count). Returns how many days were sent.
  Future<int> backfill() async {
    final userId = _sessions.session?.user.id;
    final history = source is StepHistory ? source as StepHistory : null;
    if (userId == null || history == null || _backfilling || !await isConnected()) return 0;
    _backfilling = true;
    try {
      final allowed = await history.historyAllowed();
      final done = await _readBackfill(userId);
      // Finished before. It runs again only when the permission for older steps has been given
      // since, because then more of the past can be read.
      if (done != null && (done || !allowed)) return 0;

      final today = DateTime.now();
      var sent = 0;
      var empty = 0;
      for (var i = 0; i < _historyChunks && empty < _emptyChunksToStop; i++) {
        final end = DateTime(today.year, today.month, today.day - i * _chunkDays);
        final start = DateTime(end.year, end.month, end.day - (_chunkDays - 1));
        final found = await history.readHistory(start, i == 0 ? today : end.add(const Duration(days: 1)));
        var any = false;
        for (final entry in found.entries) {
          if (entry.value.isEmpty) continue;
          any = true;
          await _api.post(
            '/steps/sync',
            body: {'source': entry.key, 'days': entry.value.map((d) => d.toJson()).toList()},
          );
          sent += entry.value.length;
        }
        empty = any ? 0 : empty + 1;
      }
      await _writeBackfill(userId, allowed);
      return sent;
    } finally {
      _backfilling = false;
    }
  }

  // null = never done; true = done with the permission for older steps; false = done without it.
  Future<bool?> _readBackfill(String userId) async {
    try {
      final raw = await _storage.read(key: _backfillKey);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return json['user'] == userId ? json['with_history'] as bool? : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeBackfill(String userId, bool withHistory) async {
    try {
      await _storage.write(key: _backfillKey, value: jsonEncode({'user': userId, 'with_history': withHistory}));
    } catch (_) {
      // Not saved: it is done again the next time the app opens, which only repeats days.
    }
  }

  /// Reads the last [days] days (two weeks unless told otherwise) and sends the ones whose
  /// count changed since the last sync. Returns the number of days sent, 0 when nothing moved.
  Future<int> sync({int days = _syncDays}) async {
    final userId = _sessions.session?.user.id;
    if (userId != _sentFor) {
      _sent.clear(); // another person's counts say nothing about this one's
      _sentFor = userId;
    }
    final read = await source.readDays(days);
    if (days >= _syncDays) emptyHealth.value = read.isEmpty;
    final changed = [
      for (final d in read)
        if (_sent[d.date] != d.steps) d,
    ];
    if (changed.isEmpty) return 0;
    await _api.post('/steps/sync', body: {'source': source.sourceId, 'days': changed.map((d) => d.toJson()).toList()});
    for (final d in changed) {
      _sent[d.date] = d.steps;
    }
    return changed.length;
  }
}

/// Past steps are saved to the account in chunks of this many days, newest first.
const _chunkDays = 30;

/// How far back the history goes at most (three years), and how many empty chunks in a row
/// mean there is nothing older.
const _historyChunks = 36;
const _emptyChunksToStop = 4;

final healthSyncProvider = Provider<HealthSync>((ref) {
  final sessions = ref.watch(sessionStoreProvider);
  return HealthSync(ref.watch(apiProvider), sessions, createHealthSource(() => sessions.session?.user.id));
});

/// Whether the phone's step sensor may be used (Android's "Physical activity" permission).
/// True where there is nothing to ask for.
/// True when the phone can give older steps but has not been allowed to yet.
final stepHistoryMissingProvider = FutureProvider.autoDispose<bool>((ref) async {
  final source = ref.watch(healthSyncProvider).source;
  if (source is! StepHistory) return false;
  final history = source as StepHistory;
  return await history.historyNeedsPermission() && !await history.historyAllowed();
});

final stepSensorAllowedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final source = ref.watch(healthSyncProvider).source;
  return source is StepSensorAccess ? await (source as StepSensorAccess).sensorAllowed() : true;
});

final healthConnectedProvider = FutureProvider.autoDispose<bool>((ref) => ref.watch(healthSyncProvider).isConnected());
