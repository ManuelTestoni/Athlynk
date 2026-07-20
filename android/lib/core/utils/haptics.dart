import 'package:flutter/services.dart';

/// Haptic vocabulary — port of iOS `Haptics.swift`, mapped onto Android
/// feedback constants with equivalent intensity.
class Haptics {
  Haptics._();

  /// Light impact — virtually every button/press.
  static void tap() => HapticFeedback.lightImpact();

  /// Heavy impact — meaningful state change (set logged, exercise added).
  static void thud() => HapticFeedback.heavyImpact();

  /// Soft impact — slider drags, chart scrubbing, shake feedback.
  static void soft() => HapticFeedback.selectionClick();

  /// Success notification — session finished, check submitted, confetti.
  static void success() => HapticFeedback.mediumImpact();

  /// Warning notification.
  static void warning() => HapticFeedback.mediumImpact();

  /// Error notification — login failure, consent failure.
  static void error() => HapticFeedback.vibrate();
}
