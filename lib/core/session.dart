import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class User {
  const User({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  factory User.fromJson(Map<String, dynamic> json) =>
      User(id: json['id'] as String, name: json['name'] as String, email: json['email'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

class Session {
  const Session({required this.access, required this.refresh, required this.user});

  final String access;
  final String refresh;
  final User user;

  /// The shape the auth endpoints answer with.
  factory Session.fromAuthResponse(Map<String, dynamic> json) => Session(
    access: json['access_token'] as String,
    refresh: json['refresh_token'] as String,
    user: User.fromJson(json['user'] as Map<String, dynamic>),
  );
}

/// Who is signed in. Tokens are kept in the phone's secure storage (the iOS Keychain
/// or Android's encrypted storage), so other apps cannot read them. It is a
/// [ChangeNotifier] so the router can react the moment someone signs in or out.
class SessionStore extends ChangeNotifier {
  SessionStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'fitness.session';

  final FlutterSecureStorage _storage;
  Session? _session;

  Session? get session => _session;
  bool get signedIn => _session != null;

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _session = Session(
        access: json['access'] as String,
        refresh: json['refresh'] as String,
        user: User.fromJson(json['user'] as Map<String, dynamic>),
      );
    } catch (_) {
      // Unreadable or corrupt storage: behave as signed out.
      _session = null;
    }
  }

  Future<void> save(Session? session) async {
    _session = session;
    notifyListeners();
    try {
      if (session == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(
          key: _key,
          value: jsonEncode({'access': session.access, 'refresh': session.refresh, 'user': session.user.toJson()}),
        );
      }
    } catch (_) {
      // Could not persist: the session still works until the app is closed.
    }
  }
}
