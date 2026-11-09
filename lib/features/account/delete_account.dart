import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';
import '../auth/firebase_sign_in.dart';

/// Deletes the account and everything in it, after two confirmations and proof that it is
/// really the owner (Google again, or the password).
class DeleteAccountButton extends ConsumerWidget {
  const DeleteAccountButton({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final sessions = ref.read(sessionStoreProvider);
    final api = ref.read(apiProvider);

    final sure = await confirm(
      context,
      title: 'Delete your account?',
      body:
          'This permanently deletes your login, steps, workouts, food diary, friends, group memberships and chat '
          'messages. It cannot be undone.',
      action: 'Continue',
    );
    if (!sure || !context.mounted) return;

    // Prove it is really them: Google asks to pick the account again, email asks for the
    // password, and an account from before Firebase sends its password to our backend.
    final firebase = ref.read(firebaseSignInProvider);
    final body = <String, dynamic>{};
    String? password;
    if (firebase.provider != 'google.com') {
      password = await askText(
        context,
        title: 'Confirm with your password',
        label: 'Your password',
        action: 'Delete everything',
        obscure: true,
      );
      if (password == null || !context.mounted) return;
    }
    if (firebase.provider == null) {
      body['password'] = password;
    } else {
      try {
        body['firebase_id_token'] = await firebase.confirmItIsYou(password: password);
      } on SignInCancelled {
        return;
      } on SignInFailed catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
        return;
      }
      if (!context.mounted) return;
    }

    final worked = await runAction(context, () => api.post('/account/delete', body: body));
    if (worked) await firebase.signOut();
    // Signing out sends the router back to the login screen.
    if (worked) await sessions.save(null);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError),
      onPressed: () => _delete(context, ref),
      child: const Text('Delete my account'),
    );
  }
}
