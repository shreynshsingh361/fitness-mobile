import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api.dart';
import '../../core/palette.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../../services/health/health_sync.dart';
import '../auth/firebase_sign_in.dart';
import 'delete_account.dart';

/// Opened from the small account button at the top right of each tab. Everything about the
/// account is on this one page: who you are, how steps are counted, privacy, help.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  Future<void> _signOut(WidgetRef ref) async {
    final store = ref.read(sessionStoreProvider);
    final refresh = store.session?.refresh;
    try {
      if (refresh != null) {
        await ref.read(apiProvider).post('/auth/logout', body: {'refresh_token': refresh});
      }
    } catch (_) {
      // Signing out on this device must work even without a connection.
    }
    try {
      await ref.read(firebaseSignInProvider).signOut();
    } catch (_) {
      // Same: leaving must never fail.
    }
    await store.save(null);
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, User user) async {
    final name = await askText(context, title: 'Your name', label: 'Name', initial: user.name);
    if (name == null || !context.mounted) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      showMessage(context, 'Enter a name.');
      return;
    }
    if (trimmed.length > 80) {
      showMessage(context, 'Use at most 80 characters.');
      return;
    }
    if (trimmed == user.name) return;
    final store = ref.read(sessionStoreProvider);
    final api = ref.read(apiProvider);
    dynamic updated;
    final worked = await runAction(context, () async => updated = await api.patch('/auth/me', body: {'name': trimmed}));
    final session = store.session;
    if (worked && session != null) {
      // Saving the session makes the greeting at the top of every tab show the new name.
      await store.save(
        Session(access: session.access, refresh: session.refresh, user: User.fromJson(updated as Map<String, dynamic>)),
      );
    }
  }

  String _signInMethod(String? provider) => switch (provider) {
    'google.com' => 'Google',
    'password' => 'Email and password',
    _ => 'Email and password (older account)',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(sessionStoreProvider);
    // The store tells its listeners when the name changes; watching the provider would not.
    return ListenableBuilder(listenable: store, builder: (context, _) => _page(context, ref, store.session?.user));
  }

  Widget _page(BuildContext context, WidgetRef ref, User? user) {
    final theme = Theme.of(context);
    final health = ref.watch(healthSyncProvider);
    final connected = ref.watch(healthConnectedProvider).value ?? false;
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: pagePadding(context),
        children: [
          if (user != null) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Hxvy.card,
                  child: Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase(), style: theme.textTheme.titleLarge),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                      Muted(user.email),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SectionCard(
              title: 'Profile',
              action: TextButton.icon(
                onPressed: () => _rename(context, ref, user),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit name'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Line(label: 'Name', value: user.name),
                  _Line(label: 'Email', value: user.email),
                  _Line(label: 'Signed in with', value: _signInMethod(ref.watch(firebaseSignInProvider).provider)),
                ],
              ),
            ),
            gap,
          ],
          if (health.source.available) ...[
            SectionCard(
              title: 'Step counting',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Muted(
                    connected
                        ? 'Counting your steps from ${health.source.displayName} and your phone.'
                        : 'Step counting is off. Turn it on from the Steps tab.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (connected)
                        OutlinedButton(
                          onPressed: () async {
                            await health.disconnect();
                            if (context.mounted) ref.invalidate(healthConnectedProvider);
                          },
                          child: const Text('Stop counting'),
                        ),
                      TextButton(onPressed: openAppSettings, child: const Text('Phone permissions')),
                    ],
                  ),
                ],
              ),
            ),
            gap,
          ],
          const SectionCard(
            title: 'Privacy',
            child: Muted(
              'Friends and group members see your name and your steps. Your workouts, food diary and water '
              'are private to you, and nobody sees your email.',
            ),
          ),
          gap,
          const SectionCard(
            title: 'How steps are counted',
            child: Muted(
              'Hxvy reads the steps saved by the apps on your phone, such as Samsung Health or Google Fit, '
              'and your phone\'s own step sensor. It uses the one with the most steps. Steps typed in by '
              'hand are never counted. Your past steps are saved to your account, so the calendar keeps '
              'every month.',
            ),
          ),
          gap,
          const SectionCard(title: 'About', child: Muted('Hxvy keeps your workouts, food and steps in one place.')),
          gap,
          GlowCard(
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () => _signOut(ref),
            ),
          ),
          gap,
          const SectionCard(
            title: 'Delete account',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Muted('Removes your account and everything in it for good.'),
                SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: DeleteAccountButton()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Muted(label)),
        Expanded(child: Text(value, textAlign: TextAlign.right)),
      ],
    ),
  );
}
