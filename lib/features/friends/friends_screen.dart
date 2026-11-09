import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../groups/group_board.dart';

class BoardRow {
  BoardRow.fromJson(Map<String, dynamic> j)
    : rank = j['rank'] as int,
      userId = j['user_id'] as String,
      name = j['name'] as String,
      steps = j['steps'] as int,
      isMe = j['is_me'] as bool;

  final int rank;
  final String userId;
  final String name;
  final int steps;
  final bool isMe;
}

class FriendsBoard {
  FriendsBoard.fromJson(Map<String, dynamic> j)
    : stepsAvailable = j['steps_available'] as bool,
      items = (j['items'] as List).map((r) => BoardRow.fromJson(r as Map<String, dynamic>)).toList();

  final bool stepsAvailable;
  final List<BoardRow> items;
}

final friendsBoardProvider = FutureProvider.autoDispose.family<FriendsBoard, String>((ref, period) async {
  final json = await ref.watch(apiProvider).get('/friends', query: {'period': period, 'date': todayKey()});
  return FriendsBoard.fromJson(json as Map<String, dynamic>);
});

final inviteCodeProvider = FutureProvider.autoDispose<String>((ref) async {
  final json = await ref.watch(apiProvider).get('/friends/invite');
  return json['code'] as String;
});

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  String _period = 'day';

  void _reloadBoard() {
    if (mounted) ref.invalidate(friendsBoardProvider(_period));
  }

  Future<void> _accept() async {
    final text = await askText(context, title: 'Accept an invite', label: 'Invite code or link', action: 'Continue');
    if (text == null || text.trim().isEmpty || !mounted) return;
    final code = codeFromPaste(text);
    final api = ref.read(apiProvider);

    // Show who sent it before accepting: becoming friends lets that person see your steps.
    Map<String, dynamic>? invite;
    await runAction(
      context,
      () async => invite = await api.get('/friends/invite/${Uri.encodeComponent(code)}') as Map<String, dynamic>,
    );
    final preview = invite;
    if (preview == null || !mounted) return;

    final inviter = preview['inviter_name'] as String;
    if (preview['is_self'] == true) {
      showMessage(context, 'That is your own invite. Send it to a friend.');
      return;
    }
    if (preview['already_friends'] == true) {
      showMessage(context, 'You are already friends with $inviter.');
      return;
    }

    final sure = await confirm(
      context,
      title: 'Become friends with $inviter?',
      body: 'You will see each other on the friends leaderboard.',
      action: 'Accept',
    );
    if (!sure || !mounted) return;

    final worked = await runAction(
      context,
      () => api.post('/friends/accept', body: {'code': code}),
      done: 'You are now friends with $inviter.',
    );
    if (worked) _reloadBoard();
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(friendsBoardProvider(_period));
    final invite = ref.watch(inviteCodeProvider);
    const gap = SizedBox(height: 12);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [IconButton(onPressed: _accept, tooltip: 'Accept an invite', icon: const Icon(Icons.person_add))],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reloadBoard(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(), // pull-to-refresh works on a short list too
          padding: pagePadding(context),
          children: [
            PeriodSwitch(period: _period, onChanged: (period) => setState(() => _period = period)),
            gap,
            SectionCard(
              title: 'Leaderboard',
              child: AsyncBody(
                value: board,
                onRetry: _reloadBoard,
                builder: (data) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!data.stepsAvailable) ...[
                      const Notice(
                        'Step counts are temporarily unavailable, so everyone shows 0 for now.',
                        icon: Icons.warning_amber_rounded,
                      ),
                      gap,
                    ],
                    for (final row in data.items) _Row(row: row, onChanged: _reloadBoard),
                  ],
                ),
              ),
            ),
            gap,
            SectionCard(
              title: 'Invite a friend',
              child: AsyncBody(
                value: invite,
                onRetry: () => ref.invalidate(inviteCodeProvider),
                builder: (code) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(code, style: const TextStyle(fontFamily: 'monospace')),
                        ),
                        OutlinedButton(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (context.mounted) showMessage(context, 'Invite code copied.');
                          },
                          child: const Text('Copy'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Muted(
                      'Send this code to a friend. Nobody sees your steps by default: only people who accept become '
                      'friends and can see you.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.row, required this.onChanged});

  final BoardRow row;
  final VoidCallback onChanged;

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    final api = ref.read(apiProvider);
    switch (action) {
      case 'hide':
        if (await runAction(
          context,
          () => api.post('/friends/${row.userId}/hide'),
          done: '${row.name} is hidden. Undo this in Settings.',
        )) {
          onChanged();
        }
      case 'remove':
        final sure = await confirm(
          context,
          title: 'Remove ${row.name}?',
          body: 'You will stop seeing each other.',
          action: 'Remove',
        );
        if (sure && context.mounted && await runAction(context, () => api.delete('/friends/${row.userId}'))) {
          onChanged();
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 28,
        child: Center(child: Text('${row.rank}', style: theme.textTheme.titleSmall)),
      ),
      title: Text(row.isMe ? '${row.name} (you)' : row.name, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(number(row.steps), style: theme.textTheme.titleSmall),
          if (row.isMe)
            const SizedBox(width: 12)
          else
            PopupMenuButton<String>(
              tooltip: 'Actions for ${row.name}',
              onSelected: (action) => _act(context, ref, action),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'hide', child: Text('Hide')),
                const PopupMenuItem(value: 'remove', child: Text('Remove friend')),
              ],
            ),
        ],
      ),
    );
  }
}
