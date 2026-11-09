import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';
import 'group_board.dart';
import 'groups_api.dart';

/// One group: nothing but its board of everyone's steps, for today, yesterday, this week or
/// this month. Inviting people, leaving and (for its admin) deleting sit in the top bar.
class GroupScreen extends ConsumerWidget {
  const GroupScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(groupProvider(id))
      .when(
        data: (group) => _Group(group: group),
        loading: () => Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Scaffold(
          appBar: AppBar(),
          body: Center(
            child: ErrorRetry(error: error, onRetry: () => ref.invalidate(groupProvider(id))),
          ),
        ),
      );
}

class _Group extends ConsumerWidget {
  const _Group({required this.group});

  final Group group;

  void _showInvite(BuildContext context) {
    final code = group.inviteCode;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invite people'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(code, style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 8),
            const Muted('Anyone with this code can join and see the group board. A group holds up to 100 people.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (context.mounted) showMessage(context, 'Invite code copied.');
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final sure = await confirm(
      context,
      title: 'Leave ${group.name}?',
      body: 'You can join again later with an invite.',
      action: 'Leave',
    );
    if (!sure || !context.mounted) return;
    final worked = await runAction(context, () => ref.read(apiProvider).post('/groups/${group.id}/leave'));
    if (!worked || !context.mounted) return;
    ref.invalidate(groupsProvider);
    context.go('/steps/groups');
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final sure = await confirm(
      context,
      title: 'Delete ${group.name}?',
      body: 'This deletes the group for everyone. It cannot be undone.',
      action: 'Delete',
    );
    if (!sure || !context.mounted) return;
    final worked = await runAction(context, () => ref.read(apiProvider).delete('/groups/${group.id}'));
    if (!worked || !context.mounted) return;
    ref.invalidate(groupsProvider);
    context.go('/steps/groups');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: Text(group.name, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(tooltip: 'Invite people', icon: const Icon(Icons.person_add), onPressed: () => _showInvite(context)),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (action) => action == 'delete' ? _delete(context, ref) : _leave(context, ref),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'leave', child: Text('Leave group')),
            if (group.isAdmin) const PopupMenuItem(value: 'delete', child: Text('Delete group')),
          ],
        ),
      ],
    ),
    body: GroupBoard(group: group),
  );
}
