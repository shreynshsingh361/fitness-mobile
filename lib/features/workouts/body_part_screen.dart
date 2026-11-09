import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/palette.dart';
import '../../core/widgets.dart';
import 'exercise_motion.dart';
import 'workouts_api.dart';

void openBodyPart(BuildContext context, String part) => context.push('/workouts/part/$part');
void openPlanExercise(BuildContext context, String part, String id) => context.push('/workouts/part/$part/$id');

/// The body parts on the Workout tab, two to a row. Each shows how many exercises its plan
/// has, and a figure doing a typical exercise for it.
class BodyPartGrid extends ConsumerWidget {
  const BodyPartGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(planSummariesProvider).value ?? const {};
    final parts = bodyParts.keys.toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final half = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < parts.length; i++)
              SizedBox(
                // An odd one out at the end takes the whole row.
                width: i == parts.length - 1 && parts.length.isOdd ? constraints.maxWidth : half,
                height: 128,
                child: _BodyPartCard(part: parts[i], count: counts[parts[i]]),
              ),
          ],
        );
      },
    );
  }
}

class _BodyPartCard extends StatelessWidget {
  const _BodyPartCard({required this.part, required this.count});

  final String part;
  final int? count; // null while loading

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (motion, equipment) = bodyPartLook[part]!;
    final n = count;
    return GlowCard(
      child: InkWell(
        onTap: () => openBodyPart(context, part),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 6,
              bottom: 6,
              width: 96,
              child: ExcludeSemantics(
                child: ExerciseAnimation(motion: motion, equipment: equipment, still: true),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 14,
              right: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bodyParts[part]!, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    n == null
                        ? ' '
                        : n == 0
                        ? 'No plan yet'
                        : '$n ${n == 1 ? 'exercise' : 'exercises'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Hxvy.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One body part's plan: the exercises someone picked, each with its sets.
class BodyPartScreen extends ConsumerWidget {
  const BodyPartScreen({super.key, required this.part});

  final String part;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = bodyParts[part];
    if (name == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('That body part does not exist.')),
      );
    }
    final plan = ref.watch(planProvider(part));
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      floatingActionButton: AboveBar(
        child: FloatingActionButton.extended(
          onPressed: () => showExercisePicker(context, part),
          icon: const Icon(Icons.add),
          label: const Text('Add exercise'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(planProvider(part)),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pagePadding(context, bottom: 88),
          children: [
            AsyncBody(
              value: plan,
              onRetry: () => ref.invalidate(planProvider(part)),
              builder: (items) {
                if (items.isEmpty) {
                  return SectionCard(
                    child: Muted(
                      'Your ${name.toLowerCase()} plan is empty. Add the exercises you do, '
                      'then set the weight and reps of each set.',
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in items) ...[_PlanTile(part: part, item: item), const SizedBox(height: 12)],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.part, required this.item});

  final String part;
  final PlanExercise item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercise = item.exercise;
    return GlowCard(
      child: InkWell(
        onTap: () => openPlanExercise(context, part, item.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 64,
                child: ExcludeSemantics(
                  child: ExerciseAnimation(motion: exercise.motion, equipment: exercise.equipment, still: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(setsSummary(item), style: theme.textTheme.bodyMedium),
                    Text(exercise.muscles, style: theme.textTheme.bodySmall?.copyWith(color: Hxvy.textMuted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Hxvy.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ready-made exercises for a body part. Tapping one adds it to the plan; the sheet
/// stays open so several can be added in a row.
Future<void> showExercisePicker(BuildContext context, String part) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  useRootNavigator: true, // covers the glass bottom bar too
  builder: (_) => _ExercisePicker(part: part),
);

class _ExercisePicker extends ConsumerStatefulWidget {
  const _ExercisePicker({required this.part});

  final String part;

  @override
  ConsumerState<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends ConsumerState<_ExercisePicker> {
  final _adding = <String>{};
  String _search = '';

  Future<void> _add(Exercise exercise) async {
    setState(() => _adding.add(exercise.id));
    final part = widget.part;
    final worked = await runAction(
      context,
      () => ref.read(apiProvider).post('/plans/$part/exercises', body: {'exercise_id': exercise.id}),
      done: '${exercise.name} added.',
    );
    if (worked) {
      ref.invalidate(planProvider(part));
      ref.invalidate(planSummariesProvider);
    }
    if (mounted) setState(() => _adding.remove(exercise.id));
  }

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    final theme = Theme.of(context);
    final library = ref.watch(libraryProvider(part));
    final inPlan = {for (final p in ref.watch(planProvider(part)).value ?? const <PlanExercise>[]) p.exercise.id};

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Choose exercises', style: theme.textTheme.titleMedium),
                      Muted('Tap to add to your ${bodyParts[part]!.toLowerCase()} plan.'),
                    ],
                  ),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                onChanged: (text) => setState(() => _search = text.trim().toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Search exercises, equipment or muscles',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncBody(
                value: library,
                onRetry: () => ref.invalidate(libraryProvider(part)),
                builder: (all) {
                  // Only this card's exercises, even if a list ever came back mixed.
                  final items = all.where((e) => e.bodyPart == part && matchesSearch(e, _search)).toList();
                  if (items.isEmpty) {
                    return Padding(padding: const EdgeInsets.all(16), child: Muted('No exercise matches "$_search".'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final exercise = items[i];
                      final added = inPlan.contains(exercise.id);
                      final busy = _adding.contains(exercise.id);
                      return ListTile(
                        contentPadding: const EdgeInsets.only(right: 8),
                        onTap: added || busy ? null : () => _add(exercise),
                        leading: SizedBox.square(
                          dimension: 52,
                          child: ExcludeSemantics(
                            child: ExerciseAnimation(
                              motion: exercise.motion,
                              equipment: exercise.equipment,
                              still: true,
                            ),
                          ),
                        ),
                        title: Text(exercise.name),
                        subtitle: Text(
                          '${_capitalised(exercise.equipment)} · ${exercise.muscles}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: busy
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(
                                added ? Icons.check_circle : Icons.add_circle_outline,
                                semanticLabel: added ? 'In your plan' : 'Add',
                                color: added ? Hxvy.accent : Hxvy.textMuted,
                              ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether an exercise fits what was typed: every word has to appear in its name,
/// equipment or muscles, so "dumbbell row" finds the dumbbell rows.
bool matchesSearch(Exercise e, String search) {
  if (search.isEmpty) return true;
  final text = '${e.name} ${e.equipment} ${e.muscles}'.toLowerCase();
  return search.toLowerCase().split(RegExp(r'\s+')).every(text.contains);
}

String _capitalised(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
