import 'package:freezed_annotation/freezed_annotation.dart';

import 'auth.dart';

part 'billing.freezed.dart';
part 'billing.g.dart';

/// included_services is a free-form JSON field: tolerate non-string arrays.
List<String> _lenientStringList(Object? raw) {
  if (raw is List) return raw.whereType<String>().toList();
  return const [];
}

@freezed
abstract class SubscriptionPlanDto with _$SubscriptionPlanDto {
  const factory SubscriptionPlanDto({
    required int id,
    required String name,
    String? planType,
    /// subscription | one_time
    String? kind,
    String? description,
    @Default(0) double price,
    @Default('EUR') String currency,
    int? durationDays,
    String? billingInterval,
    @JsonKey(fromJson: _lenientStringList)
    @Default([])
    List<String> includedServices,
    @Default(false) bool isOnlinePurchasable,
    Coach? coach,
  }) = _SubscriptionPlanDto;

  factory SubscriptionPlanDto.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionPlanDtoFromJson(json);
}

@freezed
abstract class SubscriptionDto with _$SubscriptionDto {
  const factory SubscriptionDto({
    required int id,
    required String status,
    String? paymentStatus,
    String? startDate,
    String? endDate,
    @Default(false) bool autoRenew,
    @Default(false) bool manageable,
    required SubscriptionPlanDto plan,
  }) = _SubscriptionDto;

  factory SubscriptionDto.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionDtoFromJson(json);
}

@freezed
abstract class SubscriptionListResponse with _$SubscriptionListResponse {
  const factory SubscriptionListResponse({
    @Default([]) List<SubscriptionDto> subscriptions,
  }) = _SubscriptionListResponse;

  factory SubscriptionListResponse.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionListResponseFromJson(json);
}

@freezed
abstract class PlansResponse with _$PlansResponse {
  const factory PlansResponse({
    @Default([]) List<SubscriptionPlanDto> plans,
  }) = _PlansResponse;

  factory PlansResponse.fromJson(Map<String, dynamic> json) =>
      _$PlansResponseFromJson(json);
}

@freezed
abstract class CheckoutStartResponse with _$CheckoutStartResponse {
  const factory CheckoutStartResponse({
    required String checkoutUrl,
  }) = _CheckoutStartResponse;

  factory CheckoutStartResponse.fromJson(Map<String, dynamic> json) =>
      _$CheckoutStartResponseFromJson(json);
}

/// `{url}` — Stripe Billing Portal / Connect link responses.
@freezed
abstract class UrlResponse with _$UrlResponse {
  const factory UrlResponse({
    required String url,
  }) = _UrlResponse;

  factory UrlResponse.fromJson(Map<String, dynamic> json) =>
      _$UrlResponseFromJson(json);
}
