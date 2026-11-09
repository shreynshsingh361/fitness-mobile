import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/api.dart';
import 'core/session.dart';
import 'features/auth/firebase_sign_in.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await startFirebase();

  // Read the saved login before the first frame, so a signed-in person never sees the
  // login screen flash.
  final sessions = SessionStore();
  await sessions.load();

  // Flutter on the web draws on a canvas, which browser tools cannot read. This also
  // builds the accessibility tree from the start, which makes the app testable there.
  if (kIsWeb && kDebugMode) SemanticsBinding.instance.ensureSemantics();

  runApp(
    ProviderScope(
      // By default Riverpod quietly retries a failed request many times, with a spinner
      // on screen all that while. Showing the error with a "Try again" button is clearer.
      retry: (retryCount, error) => null,
      overrides: [sessionStoreProvider.overrideWithValue(sessions)],
      child: const HxvyApp(),
    ),
  );
}
