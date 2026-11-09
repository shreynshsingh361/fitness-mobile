import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_widgets.dart';
import '../../core/widgets.dart';
import 'body_part_screen.dart';
import 'workouts_api.dart';

/// The Workout tab: one card per body part, each opening that part's plan.
class WorkoutsScreen extends ConsumerWidget {
  const WorkoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: tabBar(),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(planSummariesProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(), // pull-to-refresh works on a short list too
          padding: pagePadding(context),
          children: const [BodyPartGrid()],
        ),
      ),
    );
  }
}
