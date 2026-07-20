import 'package:freezed_annotation/freezed_annotation.dart';

import 'auth.dart';

part 'checks.freezed.dart';
part 'checks.g.dart';

// ── Pending checks (compilazione) ──

/// One section of a multi-step check.
@freezed
abstract class CheckStep with _$CheckStep {
  const factory CheckStep({
    required String id,
    required String label,
  }) = _CheckStep;

  factory CheckStep.fromJson(Map<String, dynamic> json) =>
      _$CheckStepFromJson(json);
}

/// One selectable anthropometry measure (circonferenza / plica). `key` is the
/// stored key (with `_l`/`_r` for limbs); `label` is the resolved ISAK name.
@freezed
abstract class AntroItem with _$AntroItem {
  const factory AntroItem({
    required String key,
    required String label,
  }) = _AntroItem;

  factory AntroItem.fromJson(Map<String, dynamic> json) =>
      _$AntroItemFromJson(json);
}

/// A single question. `type` mirrors the web builder: antropometria | metrica
/// | media | si_no | radio | checkbox | aperta | allegato.
@freezed
abstract class CheckQuestion with _$CheckQuestion {
  const factory CheckQuestion({
    required String id,
    @Default('aperta') String type,
    @Default('') String label,
    @JsonKey(name: 'required') @Default(false) bool isRequired,
    String? unit,
    @Default([]) List<String> options,
    double? min,
    double? max,
    String? minLabel,
    String? maxLabel,
    String? placeholder,
    String? stepId,
    // antropometria-only
    @Default(true) bool weight,
    @Default([]) List<AntroItem> circumferences,
    @Default([]) List<AntroItem> skinfolds,
  }) = _CheckQuestion;

  factory CheckQuestion.fromJson(Map<String, dynamic> json) =>
      _$CheckQuestionFromJson(json);
}

@freezed
abstract class CheckDto with _$CheckDto {
  const factory CheckDto({
    required int id,
    required String title,
    String? dueDate,
    String? expiresAt,
    Coach? coach,
    @Default([]) List<CheckStep> steps,
    @Default([]) List<CheckQuestion> questions,
  }) = _CheckDto;

  factory CheckDto.fromJson(Map<String, dynamic> json) =>
      _$CheckDtoFromJson(json);
}

@freezed
abstract class ChecksResponse with _$ChecksResponse {
  const factory ChecksResponse({
    @Default([]) List<CheckDto> pending,
  }) = _ChecksResponse;

  factory ChecksResponse.fromJson(Map<String, dynamic> json) =>
      _$ChecksResponseFromJson(json);
}

// ── Check detail (storico) — GET /api/v1/checks/<id> ──

/// A scalar answer value of unknown shape: numbers stay numbers so "80" vs
/// "80.5" render as sent; anything else is text.
sealed class CheckValue {
  const CheckValue();

  factory CheckValue.fromRaw(Object? raw) {
    if (raw == null) return const CheckValueNone();
    if (raw is num) return CheckValueNumber(raw.toDouble());
    if (raw is String) return CheckValueText(raw);
    if (raw is bool) return CheckValueText(raw ? 'Sì' : 'No');
    return const CheckValueNone();
  }

  Object? toRaw() => switch (this) {
        CheckValueNumber(:final value) => value,
        CheckValueText(:final value) => value,
        CheckValueNone() => null,
      };

  String? get display => switch (this) {
        CheckValueNumber(:final value) => value == value.roundToDouble()
            ? value.toInt().toString()
            : value.toString(),
        CheckValueText(:final value) => value.isEmpty ? null : value,
        CheckValueNone() => null,
      };
}

class CheckValueNumber extends CheckValue {
  const CheckValueNumber(this.value);
  final double value;
}

class CheckValueText extends CheckValue {
  const CheckValueText(this.value);
  final String value;
}

class CheckValueNone extends CheckValue {
  const CheckValueNone();
}

class CheckValueConverter implements JsonConverter<CheckValue?, Object?> {
  const CheckValueConverter();

  @override
  CheckValue? fromJson(Object? json) =>
      json == null ? null : CheckValue.fromRaw(json);

  @override
  Object? toJson(CheckValue? value) => value?.toRaw();
}

@freezed
abstract class CheckAttachmentFile with _$CheckAttachmentFile {
  const factory CheckAttachmentFile({
    required int id,
    required String url,
    @Default('') String fileName,
    String? mimeType,
  }) = _CheckAttachmentFile;

  factory CheckAttachmentFile.fromJson(Map<String, dynamic> json) =>
      _$CheckAttachmentFileFromJson(json);
}

/// One side (DX/SX) of a paired limb measurement.
@freezed
abstract class CheckMeasureSide with _$CheckMeasureSide {
  const factory CheckMeasureSide({
    required String label,
    String? unit,
    @CheckValueConverter() CheckValue? value,
    @CheckValueConverter() CheckValue? previous,
    double? delta,
    String? tag,
  }) = _CheckMeasureSide;

  factory CheckMeasureSide.fromJson(Map<String, dynamic> json) =>
      _$CheckMeasureSideFromJson(json);
}

@freezed
abstract class CheckFabbisogniMacro with _$CheckFabbisogniMacro {
  const factory CheckFabbisogniMacro({
    required String label,
    @CheckValueConverter() CheckValue? gkg,
    int? g,
    int? kcal,
    @CheckValueConverter() CheckValue? note,
  }) = _CheckFabbisogniMacro;

  factory CheckFabbisogniMacro.fromJson(Map<String, dynamic> json) =>
      _$CheckFabbisogniMacroFromJson(json);
}

/// Read-only summary of the coach-only «Calcolo Fabbisogni» tool.
@freezed
abstract class CheckFabbisogni with _$CheckFabbisogni {
  const factory CheckFabbisogni({
    @CheckValueConverter() CheckValue? altezza,
    @CheckValueConverter() CheckValue? peso,
    @CheckValueConverter() CheckValue? eta,
    @CheckValueConverter() CheckValue? sesso,
    @CheckValueConverter() CheckValue? formula,
    int? mb,
    @CheckValueConverter() CheckValue? pal,
    @CheckValueConverter() CheckValue? palDesc,
    int? detBase,
    @Default(0) int detAdjust,
    int? detFinale,
    @CheckValueConverter() CheckValue? detNote,
    @Default([]) List<CheckFabbisogniMacro> macros,
    @CheckValueConverter() CheckValue? fibra,
    @CheckValueConverter() CheckValue? fibraNote,
    @CheckValueConverter() CheckValue? idrico,
    @CheckValueConverter() CheckValue? idricoNote,
    @CheckValueConverter() CheckValue? micro,
    @CheckValueConverter() CheckValue? noteOp,
  }) = _CheckFabbisogni;

  factory CheckFabbisogni.fromJson(Map<String, dynamic> json) =>
      _$CheckFabbisogniFromJson(json);
}

/// One rendered question inside a check-history section. Populated fields
/// depend on `type`: `strumento_fabbisogni` uses `fb`, `metrica_pair` uses
/// `sides`, `allegato` uses `files`, everything else `value`/`previous`/`delta`.
@freezed
abstract class CheckSectionQuestion with _$CheckSectionQuestion {
  const factory CheckSectionQuestion({
    @Default('') String id,
    @Default('aperta') String type,
    @Default('') String label,
    String? unit,
    @CheckValueConverter() CheckValue? value,
    @CheckValueConverter() CheckValue? previous,
    double? delta,
    List<CheckAttachmentFile>? files,
    List<CheckMeasureSide>? sides,
    CheckFabbisogni? fb,
  }) = _CheckSectionQuestion;

  factory CheckSectionQuestion.fromJson(Map<String, dynamic> json) =>
      _$CheckSectionQuestionFromJson(json);
}

@freezed
abstract class CheckSection with _$CheckSection {
  const factory CheckSection({
    @Default('') String id,
    @Default('Sezione') String label,
    String? icon,
    @Default([]) List<CheckSectionQuestion> questions,
  }) = _CheckSection;

  factory CheckSection.fromJson(Map<String, dynamic> json) =>
      _$CheckSectionFromJson(json);
}

@freezed
abstract class CheckDetailPhoto with _$CheckDetailPhoto {
  const factory CheckDetailPhoto({
    required int id,
    required String url,
    String? type,
    String? capturedAt,
  }) = _CheckDetailPhoto;

  factory CheckDetailPhoto.fromJson(Map<String, dynamic> json) =>
      _$CheckDetailPhotoFromJson(json);
}

@freezed
abstract class CheckDetailDto with _$CheckDetailDto {
  const factory CheckDetailDto({
    required int id,
    @Default('Check') String title,
    String? submittedAt,
    @Default([]) List<CheckSection> sections,
    @Default([]) List<CheckDetailPhoto> photos,
    String? notes,
    String? injuries,
    String? limitations,
    @Default('') String coachFeedback,
  }) = _CheckDetailDto;

  factory CheckDetailDto.fromJson(Map<String, dynamic> json) =>
      _$CheckDetailDtoFromJson(json);
}
