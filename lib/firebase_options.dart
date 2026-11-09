// Firebase settings for the Hxvy project (hxvy-32756), made from
// android/app/google-services.json and ios/Runner/GoogleService-Info.plist.
//
// None of this is secret: it only names the Firebase project and the app. What
// protects accounts is Firebase itself and the backend checking every ID token.
// ignore_for_file: lines_longer_than_80_chars
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Firebase is not set up for the web build');
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => throw UnsupportedError('Firebase is not set up for $defaultTargetPlatform'),
    };
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyAeTJQEpPx57mO1eLEkMCYfj6qVmXvtt4Y',
    appId: '1:1063947532781:android:07a15f01223e5e24a54fe4',
    messagingSenderId: '1063947532781',
    projectId: 'hxvy-32756',
    storageBucket: 'hxvy-32756.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyBb7cXGm7ehYxnDZtDkHcMh2pCBFj3QovU',
    appId: '1:1063947532781:ios:1ff8a48ce4a0d558a54fe4',
    messagingSenderId: '1063947532781',
    projectId: 'hxvy-32756',
    storageBucket: 'hxvy-32756.firebasestorage.app',
    iosClientId: '1063947532781-idkbh2eckkr69ghhbtbrchlvgbnc5eak.apps.googleusercontent.com',
    iosBundleId: 'com.fittrack.fitnessMobile',
  );

  /// The project's web OAuth client. Google Sign-In on Android needs it to hand out
  /// an ID token that Firebase accepts.
  static const googleServerClientId = '1063947532781-b2vngo3ncrqc7o5m5vgpplaje7rknh6u.apps.googleusercontent.com';

  /// The iOS OAuth client, for Google Sign-In on iPhone.
  static const googleIosClientId = '1063947532781-idkbh2eckkr69ghhbtbrchlvgbnc5eak.apps.googleusercontent.com';
}
