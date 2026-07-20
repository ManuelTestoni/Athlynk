import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

@freezed
abstract class ClientProfileDto with _$ClientProfileDto {
  const factory ClientProfileDto({
    @Default('') String firstName,
    @Default('') String lastName,
    String? phone,
    double? weightKg,
    String? sport,
    String? gender,
    String? birthDate,
    String? profileImageUrl,
    String? brandName,
    String? brandPrimary,
    String? brandAccent,
  }) = _ClientProfileDto;

  factory ClientProfileDto.fromJson(Map<String, dynamic> json) =>
      _$ClientProfileDtoFromJson(json);
}

@freezed
abstract class ProfileResponse with _$ProfileResponse {
  const factory ProfileResponse({
    required ClientProfileDto profile,
  }) = _ProfileResponse;

  factory ProfileResponse.fromJson(Map<String, dynamic> json) =>
      _$ProfileResponseFromJson(json);
}

@freezed
abstract class ProfilePhotoResponse with _$ProfilePhotoResponse {
  const factory ProfilePhotoResponse({
    required String profileImageUrl,
  }) = _ProfilePhotoResponse;

  factory ProfilePhotoResponse.fromJson(Map<String, dynamic> json) =>
      _$ProfilePhotoResponseFromJson(json);
}

// ── Coach detail (Profilo Coach, as seen by the athlete) ──

@freezed
abstract class CoachDetailDto with _$CoachDetailDto {
  const CoachDetailDto._();
  const factory CoachDetailDto({
    required int id,
    @Default('') String firstName,
    @Default('') String lastName,
    String? professionalType,
    String? specialization,
    String? city,
    String? profileImageUrl,
    String? bio,
    String? description,
    String? certifications,
    int? yearsExperience,
    String? socialInstagram,
    String? socialYoutube,
    String? socialWebsite,
  }) = _CoachDetailDto;

  factory CoachDetailDto.fromJson(Map<String, dynamic> json) =>
      _$CoachDetailDtoFromJson(json);

  String get fullName => '$firstName $lastName'.trim();
}

@freezed
abstract class CoachDetailResponse with _$CoachDetailResponse {
  const factory CoachDetailResponse({
    required CoachDetailDto coach,
  }) = _CoachDetailResponse;

  factory CoachDetailResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachDetailResponseFromJson(json);
}

// ── Settings (Impostazioni) ──

@freezed
abstract class SettingToggleDto with _$SettingToggleDto {
  const factory SettingToggleDto({
    required String key,
    required String label,
    @Default('') String desc,
    @Default(false) bool enabled,
  }) = _SettingToggleDto;

  factory SettingToggleDto.fromJson(Map<String, dynamic> json) =>
      _$SettingToggleDtoFromJson(json);
}

@freezed
abstract class SettingsDto with _$SettingsDto {
  const factory SettingsDto({
    required String email,
    @Default([]) List<SettingToggleDto> notifications,
    @Default('alimento') String foodSearchMode,
  }) = _SettingsDto;

  factory SettingsDto.fromJson(Map<String, dynamic> json) =>
      _$SettingsDtoFromJson(json);
}

@freezed
abstract class SettingsResponse with _$SettingsResponse {
  const factory SettingsResponse({
    required SettingsDto settings,
  }) = _SettingsResponse;

  factory SettingsResponse.fromJson(Map<String, dynamic> json) =>
      _$SettingsResponseFromJson(json);
}

// ── Prima Valutazione (intake form read-back) ──

@freezed
abstract class PvStoria with _$PvStoria {
  const factory PvStoria({
    String? patologie,
    String? allergie,
    String? interventi,
    String? familiarita,
    String? farmaci,
    List<String>? professionistiSeguiti,
  }) = _PvStoria;

  factory PvStoria.fromJson(Map<String, dynamic> json) =>
      _$PvStoriaFromJson(json);
}

@freezed
abstract class PvAntropometria with _$PvAntropometria {
  const factory PvAntropometria({
    double? altezzaCm,
    double? pesoKg,
    double? pesoAbitualeKg,
  }) = _PvAntropometria;

  factory PvAntropometria.fromJson(Map<String, dynamic> json) =>
      _$PvAntropometriaFromJson(json);
}

@freezed
abstract class PvAllenamento with _$PvAllenamento {
  const factory PvAllenamento({
    List<String>? discipline,
    int? anniEsperienza,
    int? seduteSettimana,
    @JsonKey(name: 'durata_media_min') int? durataMedMin,
  }) = _PvAllenamento;

  factory PvAllenamento.fromJson(Map<String, dynamic> json) =>
      _$PvAllenamentoFromJson(json);
}

@freezed
abstract class PvFabbisogni with _$PvFabbisogni {
  const factory PvFabbisogni({
    int? detKcal,
    int? proteineG,
    int? carboidratiG,
    int? lipidiG,
    int? fibraG,
    int? idricoMl,
  }) = _PvFabbisogni;

  factory PvFabbisogni.fromJson(Map<String, dynamic> json) =>
      _$PvFabbisogniFromJson(json);
}

@freezed
abstract class PvObiettivi with _$PvObiettivi {
  const factory PvObiettivi({
    String? obiettivoPrincipale,
    String? motivazione,
    String? scadenza,
  }) = _PvObiettivi;

  factory PvObiettivi.fromJson(Map<String, dynamic> json) =>
      _$PvObiettiviFromJson(json);
}

@freezed
abstract class PvDataPayload with _$PvDataPayload {
  const factory PvDataPayload({
    PvStoria? storia,
    PvAntropometria? antropometria,
    PvAllenamento? allenamento,
    PvFabbisogni? fabbisogni,
    PvObiettivi? obiettivi,
  }) = _PvDataPayload;

  factory PvDataPayload.fromJson(Map<String, dynamic> json) =>
      _$PvDataPayloadFromJson(json);
}

@freezed
abstract class PrimaValutazioneDto with _$PrimaValutazioneDto {
  const PrimaValutazioneDto._();
  const factory PrimaValutazioneDto({
    String? submittedAt,
    PvDataPayload? data,
  }) = _PrimaValutazioneDto;

  factory PrimaValutazioneDto.fromJson(Map<String, dynamic> json) =>
      _$PrimaValutazioneDtoFromJson(json);

  bool get hasData => submittedAt != null && data != null;
}
