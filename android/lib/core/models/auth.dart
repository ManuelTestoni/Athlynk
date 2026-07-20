import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth.freezed.dart';
part 'auth.g.dart';

/// DTOs mirroring the Django `/api/v1` JSON shapes — ported from the iOS
/// ground truth (`Shared/Core/Models.swift`). Wire format is snake_case
/// (global `field_rename: snake` in build.yaml).

@freezed
abstract class AuthUser with _$AuthUser {
  const AuthUser._();
  const factory AuthUser({
    required int id,
    required String email,
    required String role,
    required String firstName,
    required String lastName,
    required String displayName,
    /// Optional for back-compat with servers that predate the field.
    bool? chironSeen,
    /// nil is treated as "already accepted" so older servers don't trap
    /// users behind the consent gate.
    bool? termsAccepted,
  }) = _AuthUser;

  factory AuthUser.fromJson(Map<String, dynamic> json) =>
      _$AuthUserFromJson(json);

  bool get isClient => role.toUpperCase() == 'CLIENT';

  /// First-login mascot tutorial runs only for clients who haven't met Chiron.
  bool get needsChironIntro => isClient && chironSeen != true;

  /// Gate the app only when the server explicitly said false.
  bool get needsTermsConsent => termsAccepted == false;
}

@freezed
abstract class LoginResponse with _$LoginResponse {
  const factory LoginResponse({
    required String token,
    required AuthUser user,
  }) = _LoginResponse;

  factory LoginResponse.fromJson(Map<String, dynamic> json) =>
      _$LoginResponseFromJson(json);
}

@freezed
abstract class Coach with _$Coach {
  const Coach._();
  const factory Coach({
    required int id,
    required String firstName,
    required String lastName,
    String? professionalType,
    String? specialization,
    String? city,
    String? profileImageUrl,
  }) = _Coach;

  factory Coach.fromJson(Map<String, dynamic> json) => _$CoachFromJson(json);

  String get fullName => '$firstName $lastName'.trim();
}

@freezed
abstract class MeProfile with _$MeProfile {
  const factory MeProfile({
    String? profileImageUrl,
    String? brandPrimary,
    String? brandAccent,
  }) = _MeProfile;

  factory MeProfile.fromJson(Map<String, dynamic> json) =>
      _$MeProfileFromJson(json);
}

@freezed
abstract class MeResponse with _$MeResponse {
  const factory MeResponse({
    required AuthUser user,
    Coach? coach,
    Coach? trainer,
    Coach? nutritionist,
    MeProfile? profile,
  }) = _MeResponse;

  factory MeResponse.fromJson(Map<String, dynamic> json) =>
      _$MeResponseFromJson(json);
}
