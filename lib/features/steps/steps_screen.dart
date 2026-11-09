import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/account_widgets.dart';
import '../../core/api.dart';
import '../../core/day_calendar.dart';
import '../../core/format.dart';
import '../../core/palette.dart';
import '../../core/widgets.dart';
import '../../services/health/health_sync.dart';
import '../../services/health/health_types.dart';
import 'steps_api.dart';
import 'week_chart.dart';

class StepsScreen extends ConsumerStatefulWidget {
  const StepsScreen({super.key});

  @override
  ConsumerState<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends ConsumerState<StepsScreen> {
  // The day the top card shows: today, or one picked from the calendar.
  String? _picked;

  void _reload(String date, String today) {
    ref.invalidate(stepsDayProvider(date));
    ref.invalidate(stepsHistoryProvider(today));
    ref.invalidate(stepsStatsProvider(today));
  }

  // A calendar with the steps walked written under each day; a day with the goal met is bold.
  Future<void> _pickDay(String date, int goal) async {
    final picked = await pickDay(
      context,
      selected: date,
      calendar: DayCalendar(
        figures: (ref, month) => ref.watch(stepsMonthProvider(month)),
        unit: 'steps',
        nothing: 'no steps',
        legend: 'Steps walked each day · bold is a day you reached your ${number(goal)} step goal',
        standsOut: (steps) => steps >= goal,
      ),
    );
    if (picked != null && mounted) setState(() => _picked = picked);
  }

  @override
  Widget build(BuildContext context) {
    final today = todayKey();
    final date = _picked ?? today;
    final day = ref.watch(stepsDayProvider(date));
    final history = ref.watch(stepsHistoryProvider(today));
    final stats = ref.watch(stepsStatsProvider(today));
    final settings = ref.watch(stepSettingsProvider);
    const gap = SizedBox(height: 12);

    return Scaffold(
      appBar: tabBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          // Pulling down also reads fresh counts from the phone, if connected.
          final health = ref.read(healthSyncProvider);
          if (await health.isConnected()) {
            try {
              await health.sync();
            } catch (_) {
              // Still show what the server has.
            }
          }
          if (mounted) _reload(date, today);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(), // pull-to-refresh works on a short list too
          padding: pagePadding(context, bottom: 88),
          children: [
            const _SocialCards(),
            gap,
            SectionCard(
              title: date == today ? 'Today' : shortDate(date),
              action: TextButton.icon(
                onPressed: () => _pickDay(date, day.value?.goal ?? settings.value?.dailyGoal ?? 10000),
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Calendar'),
              ),
              child: AsyncBody(
                value: day,
                onRetry: () => ref.invalidate(stepsDayProvider(date)),
                builder: (d) =>
                    _Today(day: d, isToday: date == today, onBackToToday: () => setState(() => _picked = null)),
              ),
            ),
            gap,
            SectionCard(
              title: 'Last 7 days',
              child: AsyncBody(
                value: history,
                onRetry: () => ref.invalidate(stepsHistoryProvider(today)),
                builder: (h) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WeekChart(history: h, today: today),
                    Muted('${number(h.total)} steps in total, ${number(h.average)} a day on average.'),
                  ],
                ),
              ),
            ),
            gap,
            SectionCard(
              title: 'Records',
              child: AsyncBody(
                value: stats,
                onRetry: () => ref.invalidate(stepsStatsProvider(today)),
                builder: (s) => _Records(stats: s),
              ),
            ),
            gap,
            SectionCard(
              title: 'Daily goal',
              child: AsyncBody(
                value: settings,
                onRetry: () => ref.invalidate(stepSettingsProvider),
                // Keyed by the saved goal, so the field starts over once a new one is saved.
                builder: (s) => _GoalCard(key: ValueKey(s.dailyGoal), settings: s),
              ),
            ),
            gap,
            // Set up once and then left alone, so it sits at the very bottom.
            _DeviceCard(onSynced: () => _reload(date, today)),
          ],
        ),
      ),
    );
  }
}

/// Connecting to Apple Health or Health Connect, the only places steps come from: nobody
/// can type them in. A browser has neither, so there this only explains that.
class _DeviceCard extends ConsumerWidget {
  const _DeviceCard({required this.onSynced});

  final VoidCallback onSynced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthSyncProvider);
    if (!health.source.available) {
      return const SectionCard(
        title: 'Automatic counting',
        child: Muted(
          'A browser cannot read a step sensor. Open Hxvy on your iPhone or Android phone: it counts '
          'your steps from Apple Health or Health Connect.',
        ),
      );
    }

    final name = health.source.displayName;
    final connected = ref.watch(healthConnectedProvider).value ?? false;
    final sensor = health.source is StepSensorAccess ? health.source as StepSensorAccess : null;
    final sensorAllowed = ref.watch(stepSensorAllowedProvider).value ?? true;
    final historyMissing = ref.watch(stepHistoryMissingProvider).value ?? false;
    // Once connected, steps sync by themselves (see AppShell), so there is nothing to press.
    return SectionCard(
      title: 'Automatic counting',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Muted(
                  connected
                      ? 'Your steps sync from $name by themselves while Hxvy is open.'
                      : 'Count steps automatically with $name.',
                ),
              ),
              if (!connected) ...[
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () async {
                    var allowed = false;
                    final worked = await runAction(context, () async => allowed = await health.connect());
                    if (!worked || !context.mounted) return;
                    showMessage(context, allowed ? 'Connected to $name.' : '$name permission was not given.');
                    ref.invalidate(healthConnectedProvider);
                    if (allowed) onSynced();
                  },
                  child: const Text('Connect'),
                ),
              ],
            ],
          ),
          if (connected && sensor != null)
            ValueListenableBuilder<String?>(
              valueListenable: sensor.activeSource,
              builder: (context, source, _) => source == null
                  ? const SizedBox.shrink()
                  : Padding(padding: const EdgeInsets.only(top: 8), child: Muted('Counting with $source.')),
            ),
          if (connected && historyMissing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Muted('Allow access to older steps so Hxvy can save your earlier months to your account.'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () async {
                      final allowed = await (health.source as StepHistory).requestHistory();
                      ref.invalidate(stepHistoryMissingProvider);
                      if (!context.mounted) return;
                      showMessage(
                        context,
                        allowed
                            ? 'Saving your earlier steps.'
                            : 'Permission was not given. You can allow it in Settings.',
                      );
                      if (!allowed) return;
                      final sent = await health.backfill();
                      if (sent > 0) onSynced();
                    },
                    child: const Text('Allow'),
                  ),
                ],
              ),
            ),
          if (connected && sensor != null && !sensorAllowed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Muted(
                      'Allow "Physical activity" so Hxvy can count steps with your phone\'s own step sensor, '
                      'even when $name has none.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () async {
                      final allowed = await sensor.requestSensor();
                      ref.invalidate(stepSensorAllowedProvider);
                      if (!context.mounted) return;
                      showMessage(
                        context,
                        allowed
                            ? 'Counting steps with your phone.'
                            : 'Permission was not given. You can allow it in Settings.',
                      );
                      if (allowed) onSynced();
                    },
                    child: const Text('Allow'),
                  ),
                ],
              ),
            ),
          if (connected && sensorAllowed)
            ValueListenableBuilder<bool>(
              valueListenable: health.emptyHealth,
              builder: (context, empty, _) => empty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'No steps found yet in any app on this phone. Hxvy counts from now on with the '
                        'phone\'s step sensor, so walk a little and the count appears. $name has no steps '
                        'from the last 2 weeks.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.error),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

class _Today extends StatelessWidget {
  const _Today({required this.day, required this.isToday, required this.onBackToToday});

  final StepsDay day;
  final bool isToday;
  final VoidCallback onBackToToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = day.goal - day.steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Fills as the steps add up, and is full once the goal is reached.
            ProgressRing(
              semanticLabel: '${number(day.steps)} of ${number(day.goal)} steps',
              fraction: fraction(day.steps, day.goal),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        number(day.steps),
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text('of ${number(day.goal)}', style: theme.textTheme.bodySmall?.copyWith(color: Hxvy.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stat(label: 'Distance', value: '${day.distanceKm} km', hint: 'estimated'),
                  const SizedBox(height: 12),
                  Stat(label: 'Calories', value: number(day.calories), hint: 'estimated'),
                  const SizedBox(height: 12),
                  Stat(label: 'Streak', value: '${day.streak} d', hint: 'at goal'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Muted(day.goalMet ? 'Goal reached' : '${number(left)} steps to go'),
        if (!isToday)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
              onPressed: onBackToToday,
              child: const Text('Back to today'),
            ),
          ),
      ],
    );
  }
}

/// The four records worth a glance: streak, best day, this week and all time.
class _Records extends StatelessWidget {
  const _Records({required this.stats});

  final StepsStats stats;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Line('Longest streak', days(stats.longestStreak)),
      _Line(
        'Best day',
        stats.bestDaySteps == null ? 'None yet' : '${number(stats.bestDaySteps!)} (${shortDate(stats.bestDayDate!)})',
      ),
      _Line('This week', '${number(stats.weekSteps)}, goal on ${days(stats.weekGoalDays)}'),
      _Line('All time', '${number(stats.lifetimeSteps)} (${stats.lifetimeKm} km)'),
    ],
  );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    // The value takes what room is left and wraps there, so a long one never runs off a
    // narrow phone.
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Muted(label),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

/// Sets how many steps a day count as reaching the goal: a few common goals to tap, or any
/// number typed in. The ring, calendar, streaks and week chart all follow it.
class _GoalCard extends ConsumerStatefulWidget {
  const _GoalCard({super.key, required this.settings});

  final StepSettings settings;

  @override
  ConsumerState<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends ConsumerState<_GoalCard> {
  static const _quick = [6000, 8000, 10000, 12000, 15000];
  static const _min = 1000;
  static const _max = 100000;

  late final _field = TextEditingController(text: '${widget.settings.dailyGoal}');
  bool _saving = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  int? get _typed {
    final n = int.tryParse(_field.text.trim().replaceAll(',', ''));
    return n != null && n >= _min && n <= _max ? n : null;
  }

  Future<void> _save(int goal) async {
    setState(() => _saving = true);
    final worked = await runAction(
      context,
      // The country is sent back unchanged: this card only sets the goal.
      () =>
          ref.read(apiProvider).put('/steps/settings', body: {'daily_goal': goal, 'country': widget.settings.country}),
      done: 'Daily goal set to ${number(goal)} steps.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (worked) {
      FocusScope.of(context).unfocus();
      ref.invalidate(stepSettingsProvider);
      ref.invalidate(stepsDayProvider);
      ref.invalidate(stepsHistoryProvider);
      ref.invalidate(stepsStatsProvider);
      ref.invalidate(stepsMonthProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.settings.dailyGoal;
    final typed = _typed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Muted('How many steps you want to walk each day. Right now: ${number(current)}.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final goal in _quick)
              ChoiceChip(
                label: Text(number(goal)),
                selected: typed == goal,
                onSelected: _saving ? null : (_) => setState(() => _field.text = '$goal'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _field,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Steps a day',
                  isDense: true,
                  errorText: typed == null ? '${number(_min)} to ${number(_max)}' : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _saving || typed == null || typed == current ? null : () => _save(typed),
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Friends and Groups live inside Steps: both are leaderboards of steps.
class _SocialCards extends StatelessWidget {
  const _SocialCards();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SocialCard(
            icon: const Icon(Icons.people_outline),
            label: 'Friends',
            onTap: () => context.go('/steps/friends'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SocialCard(
            icon: const Icon(Icons.groups_outlined),
            label: 'Groups',
            onTap: () => context.go('/steps/groups'),
          ),
        ),
      ],
    );
  }
}

class _SocialCard extends StatelessWidget {
  const _SocialCard({required this.icon, required this.label, required this.onTap});

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GlowCard(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    ),
  );
}
