import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The id used for the phone's own step sensor next to the apps that write steps.
const phoneSensorId = 'phone';

/// How many days back the apps are compared over.
const compareDays = 7;

/// Which of the apps that hold steps to use: the one with the most.
///
/// [totals] is each source's steps over the comparison days (an app's package name, or
/// [phoneSensorId]). Once a source was chosen, it stays chosen for as long as it still
/// has steps: another app passing it by a few steps must not make the count jump between
/// apps. It only moves when the chosen one has gone quiet. Null when no source has steps.
String? pickSource(Map<String, int> totals, {String? current}) {
  if (current != null && (totals[current] ?? 0) > 0) return current;
  String? best;
  for (final e in totals.entries) {
    if (e.value <= 0) continue;
    // Ties go to the name that sorts first, so the same phone always picks the same app.
    if (best == null || e.value > totals[best]! || (e.value == totals[best] && e.key.compareTo(best) < 0)) {
      best = e.key;
    }
  }
  return best;
}

const _names = {
  'com.sec.android.app.shealth': 'Samsung Health',
  'com.google.android.apps.fitness': 'Google Fit',
  'com.google.android.apps.healthdata': 'Health Connect',
  'com.fitbit.FitbitMobile': 'Fitbit',
  'com.garmin.android.apps.connectmobile': 'Garmin Connect',
  'com.xiaomi.hm.health': 'Zepp',
  'com.mi.health': 'Mi Fitness',
  'com.huawei.health': 'Huawei Health',
  'com.heytap.health': 'HeyTap Health',
  'com.oppo.health': 'HeyTap Health',
  'com.coros.coros': 'COROS',
  'com.strava': 'Strava',
  'com.withings.wiscale2': 'Withings',
  'com.ouraring.oura': 'Oura',
  'com.google.android.gms': 'Google Play services',
  'android': 'Your phone',
  'com.android.healthconnect.controller': 'Your phone',
  phoneSensorId: "the phone's step sensor",
};

/// A name to show for a source: "Samsung Health" instead of com.sec.android.app.shealth.
String sourceName(String id) {
  final known = _names[id];
  if (known != null) return known;
  if (id == 'unknown' || id.isEmpty) return 'Health Connect';
  final last = id.split('.').last;
  if (last.isEmpty) return id;
  return last[0].toUpperCase() + last.substring(1);
}

/// The source label the backend accepts for steps read from [id].
String backendSource(String id) => switch (id) {
  phoneSensorId => 'phone',
  'com.sec.android.app.shealth' => 'samsung',
  'com.fitbit.FitbitMobile' => 'fitbit',
  'com.garmin.android.apps.connectmobile' => 'garmin',
  _ => 'health_connect',
};

/// Remembers which source was chosen, for whom.
class SourceChoice {
  SourceChoice([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'fitness.step_source';

  final FlutterSecureStorage _storage;

  /// The source chosen for [userId], or null if none yet (or it was chosen for someone else).
  Future<String?> read(String userId) async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final source = json['user'] == userId ? json['source'] as String? : null;
      return source == null || source.isEmpty ? null : source; // an old blank choice is no choice
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String userId, String source) async {
    try {
      await _storage.write(key: _key, value: jsonEncode({'user': userId, 'source': source}));
    } catch (_) {
      // Not saved: it is worked out again the next time the app opens.
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
