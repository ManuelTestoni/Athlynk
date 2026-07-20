import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/push/local_notifications.dart';

/// Rest-timer state — port of iOS `RestTimerManager` (singleton
/// ObservableObject + Live Activity). On Android the out-of-app surface is an
/// ongoing chronometer notification instead of a Live Activity.
@immutable
class RestTimerState {
  const RestTimerState({
    this.secondsLeft = 0,
    this.totalSeconds = 0,
    this.exerciseName = '',
    this.isRunning = false,
  });

  final int secondsLeft;
  final int totalSeconds;
  final String exerciseName;
  final bool isRunning;

  double get progress =>
      totalSeconds == 0 ? 0 : 1 - secondsLeft / totalSeconds;
}

final restTimerProvider =
    NotifierProvider<RestTimerController, RestTimerState>(
        RestTimerController.new);

class RestTimerController extends Notifier<RestTimerState> {
  Timer? _timer;

  @override
  RestTimerState build() {
    ref.onDispose(_cancelInternals);
    return const RestTimerState();
  }

  /// Starts a countdown (cancelling any in-flight one, like iOS).
  void start({required int seconds, required String exerciseName}) {
    _cancelInternals();
    if (seconds <= 0) return;
    state = RestTimerState(
      secondsLeft: seconds,
      totalSeconds: seconds,
      exerciseName: exerciseName,
      isRunning: true,
    );
    LocalNotifications.shared.showRestTimer(
      exerciseName: exerciseName,
      endAt: DateTime.now().add(Duration(seconds: seconds)),
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = state.secondsLeft - 1;
      if (left <= 0) {
        cancel();
      } else {
        state = RestTimerState(
          secondsLeft: left,
          totalSeconds: state.totalSeconds,
          exerciseName: state.exerciseName,
          isRunning: true,
        );
      }
    });
  }

  void cancel() {
    _cancelInternals();
    state = const RestTimerState();
  }

  void _cancelInternals() {
    _timer?.cancel();
    _timer = null;
    LocalNotifications.shared.cancelRestTimer();
  }
}
