import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';

const groupPageSize = 50;

class Group {
  Group.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      description = j['description'] as String,
      inviteCode = j['invite_code'] as String,
      mysteryMode = j['mystery_mode'] as bool,
      chatEnabled = j['chat_enabled'] as bool,
      tauntsEnabled = j['taunts_enabled'] as bool,
      challengeStart = j['challenge_start'] as String?,
      challengeEnd = j['challenge_end'] as String?,
      memberCount = j['member_count'] as int,
      myRole = j['my_role'] as String;

  final String id;
  final String name;
  final String description;
  final String inviteCode;
  final bool mysteryMode;
  final bool chatEnabled;
  final bool tauntsEnabled;
  final String? challengeStart;
  final String? challengeEnd;
  final int memberCount;
  final String myRole;

  bool get isAdmin => myRole == 'admin';
}

class LeaderboardRow {
  LeaderboardRow.fromJson(Map<String, dynamic> j)
    : rank = j['rank'] as int,
      userId = j['user_id'] as String,
      name = j['name'] as String,
      steps = j['steps'] as int?,
      stepsHidden = j['steps_hidden'] as bool,
      isMe = j['is_me'] as bool;

  final int rank;
  final String userId;
  final String name;
  final int? steps; // null when mystery mode hides the whole number
  final bool stepsHidden; // true when today is left out, so the count is "at least"
  final bool isMe;

  String get stepsText {
    final count = steps;
    if (count == null) return '🎭 Hidden';
    return stepsHidden ? '${number(count)}+' : number(count);
  }
}

class Leaderboard {
  Leaderboard.fromJson(Map<String, dynamic> j)
    : from = j['from'] as String,
      to = j['to'] as String,
      mysteryActive = j['mystery_active'] as bool,
      revealedThrough = j['revealed_through'] as String?,
      limit = j['limit'] as int,
      total = j['total'] as int,
      items = (j['items'] as List).map((r) => LeaderboardRow.fromJson(r as Map<String, dynamic>)).toList(),
      me = j['me'] == null ? null : LeaderboardRow.fromJson(j['me'] as Map<String, dynamic>);

  final String from;
  final String to;
  final bool mysteryActive;
  final String? revealedThrough;
  final int limit;
  final int total;
  final List<LeaderboardRow> items;
  final LeaderboardRow? me;

  int get pages => max(1, (total / limit).ceil());
}

class Member {
  Member.fromJson(Map<String, dynamic> j)
    : userId = j['user_id'] as String,
      name = j['name'] as String,
      role = j['role'] as String,
      isMe = j['is_me'] as bool;

  final String userId;
  final String name;
  final String role;
  final bool isMe;

  bool get isAdmin => role == 'admin';
}

class MembersPage {
  MembersPage.fromJson(Map<String, dynamic> j)
    : limit = j['limit'] as int,
      total = j['total'] as int,
      items = (j['items'] as List).map((m) => Member.fromJson(m as Map<String, dynamic>)).toList();

  final int limit;
  final int total;
  final List<Member> items;

  int get pages => max(1, (total / limit).ceil());
}

class ChatMessage {
  ChatMessage.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      body = j['body'] as String,
      removed = j['removed'] as bool,
      mine = j['mine'] as bool,
      createdAt = j['created_at'] as String;

  final String id;
  final String name;
  final String body;
  final bool removed;
  final bool mine;
  final String createdAt;
}

final groupsProvider = FutureProvider.autoDispose<List<Group>>((ref) async {
  final json = await ref.watch(apiProvider).get('/groups');
  return (json['items'] as List).map((g) => Group.fromJson(g as Map<String, dynamic>)).toList();
});

final groupProvider = FutureProvider.autoDispose.family<Group, String>((ref, id) async {
  final json = await ref.watch(apiProvider).get('/groups/$id');
  return Group.fromJson(json as Map<String, dynamic>);
});

typedef BoardKey = ({String group, String period, String date, int page});

final leaderboardProvider = FutureProvider.autoDispose.family<Leaderboard, BoardKey>((ref, key) async {
  final json = await ref
      .watch(apiProvider)
      .get(
        '/groups/${key.group}/leaderboard',
        query: {'period': key.period, 'date': key.date, 'page': key.page, 'limit': groupPageSize},
      );
  return Leaderboard.fromJson(json as Map<String, dynamic>);
});

typedef MembersKey = ({String group, int page});

final membersProvider = FutureProvider.autoDispose.family<MembersPage, MembersKey>((ref, key) async {
  final json = await ref
      .watch(apiProvider)
      .get('/groups/${key.group}/members', query: {'page': key.page, 'limit': groupPageSize});
  return MembersPage.fromJson(json as Map<String, dynamic>);
});
