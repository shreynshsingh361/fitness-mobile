# Hxvy mobile

The Flutter app for Hxvy (the project folders still carry the old name, FitTrack). It is a project of its own: it shares no code with
`fitness-backend` (the Go microservices) or `fitness-frontend` (the Next.js web app) and
talks to the backend only over HTTP, through the gateway.

```
fitness-backend    Go gateway + 5 services + PostgreSQL     http://localhost:8080
fitness-frontend   Next.js web app                          http://localhost:3000
fitness-mobile     this app (iPhone, Android, browser)      http://localhost:3100 in a browser
```

## Run it

Start the backend first (`docker compose up -d` in `fitness-backend`). Then:

```bash
flutter pub get
flutter run -d web-server --web-port=3100 --web-hostname=localhost
```

Open <http://localhost:3100>. The gateway only accepts browser requests from addresses it
knows, so keep port 3100: it is on the `CORS_ORIGINS` list in `fitness-backend`.

### On a simulator or a phone

A browser needs nothing more. Xcode is only needed for iPhone builds, because Apple allows
iOS apps to be built only with it. Android needs the Android SDK instead, not Xcode.

| Target | What you need | Command |
| --- | --- | --- |
| iPhone simulator | Xcode and CocoaPods | `flutter run -d "iPhone 17"` |
| Android emulator | Android Studio or the command line tools | `flutter run -d emulator-5554` |
| A real phone | The same, plus your Mac's Wi-Fi address | `flutter run --dart-define=API_URL=http://192.168.1.5:8080` |

A real phone cannot reach your Mac at `localhost`, which is why it needs the address. The
Android emulator reaches the Mac at `10.0.2.2`, and the app already uses that by default.

What is set up on this Mac (2026-11-08): Flutter 3.47, Java 17 and the Android SDK in
`~/Library/Android/sdk`, an emulator called `FitTrack_Pixel` (Android 16), Xcode 27.2 with the
iOS 27.2 simulator, and CocoaPods. The app has been opened on both the emulator and the
"iPhone 18 Pro" simulator, and signing in reached the backend from both.

The simplest way to reach the backend from Android, emulator or a phone on a USB cable:

```bash
~/Library/Android/sdk/emulator/emulator -avd FitTrack_Pixel
~/Library/Android/sdk/platform-tools/adb reverse tcp:8080 tcp:8080
flutter run --dart-define=API_URL=http://localhost:8080
```

`adb reverse` makes the device's own `localhost:8080` lead to the Mac. It has to be run again
each time the device reconnects. For the iPhone simulator, `localhost` already works:

```bash
open -a Simulator
flutter run -d "iPhone 18 Pro"
```

If the first Android build fails with "Operation timed out" while downloading Gradle, it is the
slow GitHub download host: fetch `gradle-9.3.1-all.zip` with curl, check it against the
`.sha256` file next to it on services.gradle.org, and put it in the folder under
`~/.gradle/wrapper/dists/gradle-9.3.1-all/`.

## Automatic step counting

A phone keeps counting steps by itself, in Apple Health or Health Connect. This app asks
permission once, when you press **Connect** on the Steps tab, and from then on reads the
last 14 days whenever it opens or comes back to the front. Sending the same day twice is
harmless, because the backend keeps the highest count.

Steps cannot be typed in, not even in the phone's Health app: only what a phone or watch
measured counts. A browser cannot read a step sensor, so it only shows steps.

Two things that can look like bugs on a device:

- A simulator or emulator has no step sensor, and steps added by hand in its Health app do not
  count, so it shows 0 steps. Try step counting on a real phone.
- Apple never tells an app whether it may read steps. If someone says no, the app still shows
  "connected" and simply finds no steps. They can change it under Health > Sharing > Apps.

**Not tested yet:** the app builds and runs on Android and iOS, but reading real steps from
Apple Health or Health Connect has not been tried on a phone with a step sensor. Try that
before relying on it. Older Android phones also need the Health Connect app installed.

Native settings this depends on:

- iOS: `ios/Runner/Runner.entitlements` (HealthKit) and the `NSHealth…UsageDescription` texts in `Info.plist`
- Android: the `READ_STEPS` permission, the permission-rationale entries in `AndroidManifest.xml`,
  `FlutterFragmentActivity` in `MainActivity.kt`, and `minSdk 26`

## How the code is laid out

```
lib/
  main.dart             loads the saved login, then starts the app
  app/                  theme, routes, the bottom bar
  core/                 API client, login storage, date and number formats, shared widgets
  services/health/      reading steps from the phone (and a stub for browsers)
  features/             one folder per screen. The bottom bar has three tabs: workouts,
                        nutrition ("Food") and steps, with friends and groups inside Steps.
                        account/ is the small button at the top right (settings, sign out)
test/                   run with: flutter test
```

Things worth knowing when you read it:

- **`core/api.dart`** is the only place that knows about HTTP. It adds the access token and,
  when a token has expired, quietly gets a new one and repeats the request. Several requests
  can fail at once, so they share one refresh: refresh tokens work only once.
- **Riverpod providers** (`FutureProvider`) fetch data and remember it while a screen uses it.
  After a change, a screen calls `ref.invalidate(...)` and the data is fetched again.
- **Logins are stored in secure storage** (the iOS Keychain or Android's encrypted storage),
  not in plain preferences. In a browser the same package uses encrypted local storage, which is weaker.
- **Dates are the person's local date.** Each person's day ends at their own midnight, and the
  server cannot know where they are.
- **`client_op_id`** makes saving a workout safe to retry. If the network drops mid-save, the
  retry sends the same id and the server returns the workout it already saved.

## Differences from the web app

- CSV group reports can only be downloaded on the web.
- There are no tappable invite links yet. People paste a code or a web invite link instead.
- Data is not stored for offline use yet. The blueprint suggests Drift for this, and it can be
  added later. Without a connection, screens show an error and a retry button.
- JSON is parsed with small hand-written `fromJson` constructors, without code generation,
  so that the code reads straightforwardly while learning.
