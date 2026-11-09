import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import 'groups_api.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final details = await showDialog<({String name, String description})>(
      context: context,
      builder: (_) => const _CreateGroupDialog(),
    );
    if (details == null || !context.mounted) return;

    String? newId;
    final worked = await runAction(context, () async {
      final json = await ref
          .read(apiProvider)
          .post('/groups', body: {'name': details.name, 'description': details.description});
      newId = json['id'] as String;
    });
    if (!worked || !context.mounted) return;
    ref.invalidate(groupsProvider);
    context.go('/steps/groups/$newId');
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final text = await askText(context, title: 'Join a group', label: 'Invite code or link', action: 'Continue');
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    final code = codeFromPaste(text);
    final api = ref.read(apiProvider);

    // Show which group it is first, so a wrong code does not join the wrong one.
    Map<String, dynamic>? invite;
    await runAction(
      context,
      () async => invite = await api.get('/groups/invite/${Uri.encodeComponent(code)}') as Map<String, dynamic>,
    );
    final preview = invite;
    if (preview == null || !context.mounted) return;

    final id = preview['id'] as String;
    if (preview['is_member'] == true) {
      context.go('/steps/groups/$id');
      return;
    }

    final members = preview['member_count'] as int;
    final sure = await confirm(
      context,
      title: 'Join ${preview['name']}?',
      body: '${number(members)} ${members == 1 ? 'member' : 'members'}. They will see your steps on the group board.',
      action: 'Join',
    );
    if (!sure || !context.mounted) return;

    final worked = await runAction(context, () => api.post('/groups/join', body: {'code': code}));
    if (!worked || !context.mounted) return;
    ref.invalidate(groupsProvider);
    context.go('/steps/groups/$id');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            tooltip: 'Join with an invite',
            icon: const Icon(Icons.group_add),
            onPressed: () => _join(context, ref),
          ),
        ],
      ),
      floatingActionButton: AboveBar(
        child: FloatingActionButton.extended(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('New group'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(groupsProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(), // pull-to-refresh works on a short list too
          padding: pagePadding(context, bottom: 88),
          children: [
            AsyncBody(
              value: groups,
              onRetry: () => ref.invalidate(groupsProvider),
              builder: (items) => items.isEmpty
                  ? const SectionCard(
                      child: Muted(
                        'You are not in a group yet. Create one for your office, family or gym, or join with an '
                        'invite. There is nothing to start or stop: the leaderboards just run.',
                      ),
                    )
                  : Column(
                      children: [
                        for (final group in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GlowCard(
                              child: ListTile(
                                title: Text(group.name, overflow: TextOverflow.ellipsis),
                                subtitle: Text(_summary(group)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.go('/steps/groups/${group.id}'),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _summary(Group group) {
    final start = group.challengeStart;
    final end = group.challengeEnd;
    return [
      '${number(group.memberCount)} ${group.memberCount == 1 ? 'member' : 'members'}',
      if (group.isAdmin) 'you are an admin',
      if (group.mysteryMode) 'mystery mode',
      if (start != null && end != null) 'challenge ${shortDate(start)} to ${shortDate(end)}',
    ].join(' · ');
  }
}

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog();

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, (name: _name.text.trim(), description: _description.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create a group'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            maxLength: 80,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'Office walkers'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Give the group a name' : null,
          ),
          TextFormField(
            controller: _description,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Description (optional)'),
            onFieldSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _submit, child: const Text('Create')),
    ],
  );
}
