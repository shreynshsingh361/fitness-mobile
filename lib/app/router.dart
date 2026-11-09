import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../features/account/account_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/friends/friends_screen.dart';
import '../features/groups/group_screen.dart';
import '../features/groups/groups_screen.dart';
import '../features/nutrition/meals_screen.dart';
import '../features/nutrition/nutrition_screen.dart';
import '../features/nutrition/recipe_editor.dart';
import '../features/nutrition/recipes_screen.dart';
import '../features/steps/steps_screen.dart';
import '../features/workouts/body_part_screen.dart';
import '../features/workouts/plan_exercise_screen.dart';
import '../features/workouts/workouts_screen.dart';
import 'app_shell.dart';

const _firstTab = '/workouts';

/// Every screen and its address. Signing in or out re-runs the redirect, because the
/// router listens to the session store.
final routerProvider = Provider<GoRouter>((ref) {
  final sessions = ref.watch(sessionStoreProvider);

  return GoRouter(
    initialLocation: _firstTab,
    refreshListenable: sessions,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      if (!sessions.signedIn) return atLogin ? null : '/login';
      return atLogin || state.matchedLocation == '/' ? _firstTab : null;
    },
    routes: [
      GoRoute(path: '/', redirect: (context, state) => _firstTab),
      GoRoute(path: '/login', builder: (context, state) => const AuthScreen()),

      // Opened from the account button. It covers the whole screen, bottom bar included.
      GoRoute(path: '/account', builder: (context, state) => const AccountScreen()),

      // The three bottom-bar tabs. Each remembers where you were inside it.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/workouts',
                builder: (context, state) => const WorkoutsScreen(),
                routes: [
                  GoRoute(
                    path: 'part/:part',
                    builder: (context, state) => BodyPartScreen(part: state.pathParameters['part']!),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            PlanExerciseScreen(part: state.pathParameters['part']!, id: state.pathParameters['id']!),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/food',
                builder: (context, state) => const NutritionScreen(),
                routes: [
                  GoRoute(
                    path: 'meals',
                    builder: (context, state) => MealsScreen(date: state.uri.queryParameters['date'] ?? todayKey()),
                  ),
                  GoRoute(
                    path: 'recipes',
                    builder: (context, state) => const RecipesScreen(),
                    routes: [
                      // Before ':id', so "new" is not taken for a recipe's id.
                      GoRoute(path: 'new', builder: (context, state) => const RecipeEditor()),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) => RecipeEditor(id: state.pathParameters['id']),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/steps',
                builder: (context, state) => const StepsScreen(),
                routes: [
                  GoRoute(path: 'friends', builder: (context, state) => const FriendsScreen()),
                  GoRoute(
                    path: 'groups',
                    builder: (context, state) => const GroupsScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (context, state) => GroupScreen(id: state.pathParameters['id']!),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: const Center(child: Text('That page does not exist.')),
    ),
  );
});
