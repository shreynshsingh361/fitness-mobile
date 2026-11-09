import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/palette.dart';

/// "Afternoon, Shre": the title at the top of each tab.
class Greeting extends ConsumerWidget {
  const Greeting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The session store is one object that tells its listeners when it changes (a new name,
    // for example); watching the provider alone would not rebuild this.
    final store = ref.watch(sessionStoreProvider);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final name = firstName(store.session?.user.name ?? '');
        return Text('${greeting(DateTime.now())}, $name', overflow: TextOverflow.ellipsis);
      },
    );
  }
}

/// The small round account button in the top right corner of each tab.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: IconButton(
      tooltip: 'Account',
      onPressed: () => context.push('/account'),
      icon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Hxvy.card,
          border: Border.all(color: Hxvy.border),
        ),
        child: const Icon(Icons.person_outline, size: 18),
      ),
    ),
  );
}

/// The top bar every tab shares: the greeting on the left, the account button on the right.
AppBar tabBar() => AppBar(title: const Greeting(), actions: const [AccountButton()]);
