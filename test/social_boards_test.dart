import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:fitness_mobile/features/friends/friends_screen.dart';
import 'package:fitness_mobile/features/groups/group_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the group and friends boards, with different steps for each period, and
/// remembers which periods were asked for.
class _FakeApi extends ApiClient {
  _FakeApi(super.sessions);

  final periods = <String>[];
  static const _steps = {'day': 4000, 'yesterday': 9000, 'week': 41000, 'month': 150000};

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    switch (path) {
      case '/groups/g1':
        return {
          'id': 'g1',
          'name': 'Office walkers',
          'description': '',
          'invite_code': 'ABC123',
          'mystery_mode': false,
          'chat_enabled': true,
          'taunts_enabled': true,
          'challenge_start': null,
          'challenge_end': null,
          'member_count': 2,
          'my_role': 'admin',
        };
      case '/groups/g1/leaderboard':
        final period = query!['period'] as String;
        periods.add(period);
        return {
          'from': '2026-11-09',
          'to': '2026-11-09',
          'mystery_active': false,
          'revealed_through': null,
          'limit': 50,
          'total': 2,
          'items': [
            {
              'rank': 1,
              'user_id': 'u2',
              'name': 'Ravi',
              'steps': _steps[period]! + 1,
              'steps_hidden': false,
              'is_me': false,
            },
            {'rank': 2, 'user_id': 'u1', 'name': 'Asha', 'steps': _steps[period], 'steps_hidden': false, 'is_me': true},
          ],
          'me': null,
        };
      case '/friends':
        final period = query!['period'] as String;
        periods.add(period);
        return {
          'steps_available': true,
          'items': [
            {'rank': 1, 'user_id': 'u2', 'name': 'Ravi', 'steps': _steps[period]! + 1, 'is_me': false},
            {'rank': 2, 'user_id': 'u1', 'name': 'Asha', 'steps': _steps[period], 'is_me': true},
          ],
        };
      case '/friends/invite':
        return {'code': 'FRIEND1'};
    }
    throw StateError('No fake answer for $path');
  }
}

void main() {
  late SessionStore sessions;
  late _FakeApi api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SessionStore();
    api = _FakeApi(sessions);
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [sessionStoreProvider.overrideWithValue(sessions), apiProvider.overrideWithValue(api)],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('a group is one simple board: no chat, members or settings tabs', (tester) async {
    await show(tester, const GroupScreen(id: 'g1'));
    expect(find.text('Office walkers'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    for (final gone in ['Board', 'Chat', 'Members', 'Settings']) {
      expect(find.text(gone), findsNothing);
    }
    for (final period in ['Today', 'Yesterday', 'Week', 'Month']) {
      expect(find.text(period), findsOneWidget);
    }
    expect(find.text('4,000'), findsOneWidget, reason: "today's steps first");
    expect(find.byTooltip('Cheer Ravi'), findsNothing);
    expect(find.byTooltip('Taunt Ravi'), findsNothing);
    expect(find.byTooltip('Invite people'), findsOneWidget);
  });

  testWidgets('the group board switches between today, yesterday, week and month', (tester) async {
    await show(tester, const GroupScreen(id: 'g1'));
    await pick(tester, 'Yesterday');
    expect(find.text('9,000'), findsOneWidget);
    await pick(tester, 'Week');
    expect(find.text('41,000'), findsOneWidget);
    await pick(tester, 'Month');
    expect(find.text('150,000'), findsOneWidget);
    expect(api.periods, ['day', 'yesterday', 'week', 'month']);
  });

  testWidgets('leaving and, for the admin, deleting sit in the menu', (tester) async {
    await show(tester, const GroupScreen(id: 'g1'));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Leave group'), findsOneWidget);
    expect(find.text('Delete group'), findsOneWidget);
  });

  testWidgets('Friends has no cheers and taunts, and the same four periods', (tester) async {
    await show(tester, const FriendsScreen());
    expect(find.text('CHEERS AND TAUNTS', skipOffstage: false), findsNothing);
    expect(find.text('INVITE A FRIEND', skipOffstage: false), findsOneWidget, reason: 'inviting stays');

    await tester.tap(find.byTooltip('Actions for Ravi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cheer'), findsNothing);
    expect(find.textContaining('Taunt'), findsNothing);
    expect(find.text('Remove friend'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await pick(tester, 'Yesterday');
    expect(find.text('9,000'), findsOneWidget);
    await pick(tester, 'Month');
    expect(find.text('150,000'), findsOneWidget);
    expect(api.periods, ['day', 'yesterday', 'month']);
  });
}
