import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/offline_queue.dart';
import '../core/widgets.dart';
import '../features/friends/friends_screen.dart';
import '../features/groups/groups_api.dart';
import '../features/nutrition/nutrition_screen.dart';
import '../features/nutrition/recipes_api.dart';
import '../features/steps/steps_api.dart';
import '../features/workouts/workouts_api.dart';
import '../services/health/health_sync.dart';

/// The bottom bar around the signed-in screens. It also keeps what they show up to date:
///  - Steps sync by themselves: two weeks of them whenever the app opens or comes back to
///    the front, and today's every second while it is open, so the count moves as you
///    walk. Only a changed count is sent and reloaded. There is no button.
///  - A tab stays alive in the background once it has been opened, so what it shows can
///    be old by the time someone comes back to it. Returning to a tab reloads it.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  final _openedTabs = <int>{};

  /// How often today's steps are read again while the app stays open.
  static const syncEvery = Duration(seconds: 1);
  static const _stepsTab = 2;

  Timer? _syncTimer;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _openedTabs.add(widget.shell.currentIndex);
    WidgetsBinding.instance.addObserver(this);
    _startSyncing();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Syncs now, then again every few minutes until the app goes to the background.
  void _startSyncing() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(syncEvery, (_) {
      _syncSteps(days: 1);
      _sendWaiting();
    });
    _syncSteps(); // the full two weeks first: the phone kept counting while the app was shut
    _backfillSteps(); // and the earlier months, once
    _sendWaiting(force: true); // food and water added without internet, if any are waiting
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tab = widget.shell.currentIndex;
    if (tab == oldWidget.shell.currentIndex) return;
    if (tab == _stepsTab) _syncSteps(days: 1); // the newest count, without asking for it

    // A tab opened for the first time is loading by itself already.
    if (!_openedTabs.add(tab)) {
      // Data cannot be changed in the middle of building the screen, so wait for it to end.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reloadTab(tab);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _syncTimer?.cancel(); // nothing to show while nobody looks; it syncs again on return
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    _reloadTab(widget.shell.currentIndex);
    _startSyncing();
  }

  void _reloadTab(int tab) {
    switch (tab) {
      case 0: // Workout
        ref.invalidate(planSummariesProvider);
      case 1: // Food
        ref.invalidate(diaryProvider);
        ref.invalidate(goalProvider);
        ref.invalidate(waterProvider);
        ref.invalidate(recipesProvider);
      case 2: // Steps, with Friends and Groups inside it
        _reloadSteps();
        ref.invalidate(friendsBoardProvider);
        ref.invalidate(groupsProvider);
        ref.invalidate(groupProvider);
        ref.invalidate(leaderboardProvider);
    }
  }

  void _reloadSteps() {
    ref.invalidate(stepsDayProvider);
    ref.invalidate(stepsHistoryProvider);
    ref.invalidate(stepsStatsProvider);
    ref.invalidate(stepsMonthProvider);
  }

  DateTime _lastSendTry = DateTime.fromMillisecondsSinceEpoch(0);

  /// Sends the food and water that were added without internet. Tried again every few seconds
  /// while something is waiting; the food tab reloads once something went through.
  Future<void> _sendWaiting({bool force = false}) async {
    final queue = ref.read(offlineQueueProvider);
    await queue.load();
    if (!queue.hasPending) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastSendTry) < const Duration(seconds: 5)) return;
    _lastSendTry = now;
    try {
      if (await queue.flush() > 0 && mounted) _reloadTab(1);
    } catch (_) {
      // Still offline: the next try is in a few seconds.
    }
  }

  /// Saves the steps of earlier months to the account, once. It runs in the background and
  /// the Steps tab reloads when it brought something in.
  Future<void> _backfillSteps() async {
    try {
      final sent = await ref.read(healthSyncProvider).backfill();
      if (sent > 0 && mounted) _reloadSteps();
    } catch (_) {
      // No connection or the health app is busy: it tries again the next time the app opens.
    }
  }

  Future<void> _syncSteps({int? days}) async {
    if (_syncing) return; // one at a time: a slow read must not pile up behind the timer
    _syncing = true;
    try {
      final health = ref.read(healthSyncProvider);
      if (!await health.isConnected()) return;
      final sent = days == null ? await health.sync() : await health.sync(days: days);
      if (sent == 0) return; // nothing moved, so nothing to reload
    } catch (_) {
      return; // No connection right now: the next sync tries again.
    } finally {
      _syncing = false;
    }
    if (!mounted) return;
    _reloadSteps();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    return Scaffold(
      body: shell,
      // The pages run on under the glass bar, so it has something to blur.
      extendBody: true,
      bottomNavigationBar: GlassBar(
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          // Tapping the tab you are already on goes back to the top of that tab.
          onDestinationSelected: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: 'Workout',
            ),
            NavigationDestination(
              icon: Icon(Icons.restaurant_outlined),
              selectedIcon: Icon(Icons.restaurant),
              label: 'Food',
            ),
            NavigationDestination(
              icon: Icon(Icons.directions_walk_outlined),
              selectedIcon: Icon(Icons.directions_walk),
              label: 'Steps',
            ),
          ],
        ),
      ),
    );
  }
}
