import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import 'groups_api.dart';

/// The periods a board can show, in the order of the switch above it.
const boardPeriods = {'day': 'Today', 'yesterday': 'Yesterday', 'week': 'Week', 'month': 'Month'};

/// Everyone in the group ranked by their steps over one period.
class GroupBoard extends ConsumerStatefulWidget {
  const GroupBoard({super.key, required this.group});

  final Group group;

  @override
  ConsumerState<GroupBoard> createState() => _GroupBoardState();
}

class _GroupBoardState extends ConsumerState<GroupBoard> {
  String _period = 'day';
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final BoardKey key = (group: group.id, period: _period, date: todayKey(), page: _page);
    final board = ref.watch(leaderboardProvider(key));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(leaderboardProvider(key)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(), // pull-to-refresh works on a short list too
        padding: pagePadding(context),
        children: [
          PeriodSwitch(
            period: _period,
            onChanged: (period) => setState(() {
              _period = period;
              _page = 1;
            }),
          ),
          const SizedBox(height: 12),
          AsyncBody(
            value: board,
            onRetry: () => ref.invalidate(leaderboardProvider(key)),
            builder: (data) => _Board(data: data, page: _page, onPage: (page) => setState(() => _page = page)),
          ),
        ],
      ),
    );
  }
}

/// Today, Yesterday, Week and Month, for the group and friends boards alike.
class PeriodSwitch extends StatelessWidget {
  const PeriodSwitch({super.key, required this.period, required this.onChanged});

  final String period;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    segments: [for (final p in boardPeriods.entries) ButtonSegment(value: p.key, label: Text(p.value))],
    selected: {period},
    showSelectedIcon: false,
    style: const ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
    ),
    onSelectionChanged: (selection) => onChanged(selection.first),
  );
}

class _Board extends StatelessWidget {
  const _Board({required this.data, required this.page, required this.onPage});

  final Leaderboard data;
  final int page;
  final void Function(int page) onPage;

  @override
  Widget build(BuildContext context) {
    final revealed = data.revealedThrough;
    final me = data.me;
    final meOnPage = data.items.any((row) => row.isMe);
    final title = shortDate(data.from) + (data.from == data.to ? '' : ' to ${shortDate(data.to)}');

    return SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data.mysteryActive) ...[
            Notice(
              '🎭 Mystery mode is on: ranks show, but other people\'s steps stay hidden until the day has ended '
              'everywhere${revealed == null ? '' : ' (counts shown up to ${shortDate(revealed)})'}.',
            ),
            const SizedBox(height: 8),
          ],
          if (data.items.isEmpty) const Muted('Nobody to show yet.'),
          for (final row in data.items) _Row(row: row),
          if (me != null && !meOnPage) ...[const Divider(thickness: 2), _Row(row: me)],
          if (data.pages > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(onPressed: page > 1 ? () => onPage(page - 1) : null, child: const Text('Previous')),
                Muted('Page $page of ${data.pages}'),
                OutlinedButton(onPressed: page < data.pages ? () => onPage(page + 1) : null, child: const Text('Next')),
              ],
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row});

  final LeaderboardRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${row.rank}',
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              row.isMe ? '${row.name} (you)' : row.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: row.isMe ? FontWeight.bold : FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Text(row.stepsText, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}
