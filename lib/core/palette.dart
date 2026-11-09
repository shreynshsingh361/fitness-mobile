import 'package:flutter/material.dart';

/// Hxvy's colours, in one place. Black like a premium card, with white as the only accent.
abstract final class Hxvy {
  static const black = Color(0xFF000000);

  /// A card at rest, and while it is hovered or pressed.
  static const card = Color(0xFF151515);
  static const cardActive = Color(0xFF222222);

  static const border = Color(0xFF303030);
  static const accent = Color(0xFFFFFFFF);

  /// Buttons are white with black text on them.
  static const button = Color(0xFFFFFFFF);
  static const onButton = Color(0xFF000000);

  static const text = Color(0xFFF2F2F2);
  static const textMuted = Color(0xFFA1A1A1);

  /// Over the day's calorie goal: the one place the app uses colour.
  static const over = Color(0xFFFF4D4F);

  /// How long a card takes to lift, matching `transition: 0.35s ease`.
  static const lift = Duration(milliseconds: 350);
}
