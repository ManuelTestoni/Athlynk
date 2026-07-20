import 'dart:async';

/// In-app remote-change bus — port of iOS `PushBridge`'s
/// `athlynkRemoteChange` NotificationCenter bridge.
///
/// A push notification carries a `type` string (`MESSAGE`,
/// `WORKOUT_ASSIGNED`, `CHECK_REVIEWED`, …). Screens subscribe to the types
/// they care about and refetch just their own data slice — pushes never
/// navigate anywhere.
///
/// Server-side today only APNs is wired (iOS). This bridge is transport-
/// agnostic: when FCM lands (add firebase_messaging + google-services.json,
/// call [emit] from the message handler), every subscribed screen starts
/// reacting with zero further changes. Until then the app stays fully
/// functional on its pull-based refresh paths.
class PushBridge {
  final _controller = StreamController<String>.broadcast();

  /// All remote-change events (`type` strings).
  Stream<String> get changes => _controller.stream;

  /// Events filtered to [types]; empty set = everything.
  Stream<String> onTypes(Set<String> types) => types.isEmpty
      ? changes
      : changes.where((t) => types.contains(t.toUpperCase()));

  /// Called by the push transport (or tests) when a remote change arrives.
  void emit(String type) {
    if (!_controller.isClosed) _controller.add(type.toUpperCase());
  }

  void dispose() => _controller.close();
}

/// Known notification `type` values (server `Notification.notification_type`).
class RemoteChangeType {
  RemoteChangeType._();
  static const message = 'MESSAGE';
  static const appointmentRequest = 'APPOINTMENT_REQUEST';
  static const appointmentAccepted = 'APPOINTMENT_ACCEPTED';
  static const appointmentRejected = 'APPOINTMENT_REJECTED';
  static const checkSubmitted = 'CHECK_SUBMITTED';
  static const checkReviewed = 'CHECK_REVIEWED';
  static const workoutAssigned = 'WORKOUT_ASSIGNED';
  static const nutritionAssigned = 'NUTRITION_ASSIGNED';
  static const supplementAssigned = 'SUPPLEMENT_ASSIGNED';
  static const macroReminder = 'MACRO_REMINDER';
  static const coachFeedback = 'COACH_FEEDBACK';
}
