import 'package:freezed_annotation/freezed_annotation.dart';

import 'auth.dart';

part 'chat.freezed.dart';
part 'chat.g.dart';

@freezed
abstract class NotificationDto with _$NotificationDto {
  const factory NotificationDto({
    required int id,
    required String type,
    required String title,
    String? body,
    @Default(false) bool isRead,
    String? createdAt,
  }) = _NotificationDto;

  factory NotificationDto.fromJson(Map<String, dynamic> json) =>
      _$NotificationDtoFromJson(json);
}

@freezed
abstract class NotificationsResponse with _$NotificationsResponse {
  const factory NotificationsResponse({
    @Default([]) List<NotificationDto> notifications,
    bool? hasMore,
  }) = _NotificationsResponse;

  factory NotificationsResponse.fromJson(Map<String, dynamic> json) =>
      _$NotificationsResponseFromJson(json);
}

@freezed
abstract class ConversationDto with _$ConversationDto {
  const factory ConversationDto({
    required int id,
    Coach? coach,
    String? lastMessage,
    String? lastMessageAt,
  }) = _ConversationDto;

  factory ConversationDto.fromJson(Map<String, dynamic> json) =>
      _$ConversationDtoFromJson(json);
}

@freezed
abstract class ConversationsResponse with _$ConversationsResponse {
  const factory ConversationsResponse({
    @Default([]) List<ConversationDto> conversations,
  }) = _ConversationsResponse;

  factory ConversationsResponse.fromJson(Map<String, dynamic> json) =>
      _$ConversationsResponseFromJson(json);
}

/// Google/Apple Calendar subscription feed — shared shape for both roles.
@freezed
abstract class CalendarFeedDto with _$CalendarFeedDto {
  const factory CalendarFeedDto({
    required String feedUrl,
    required String webcalUrl,
    required String googleSubscribeUrl,
  }) = _CalendarFeedDto;

  factory CalendarFeedDto.fromJson(Map<String, dynamic> json) =>
      _$CalendarFeedDtoFromJson(json);
}

/// message_type: TEXT | APPOINTMENT_REQUEST | APPOINTMENT_RESPONSE.
@freezed
abstract class MessageDto with _$MessageDto {
  const factory MessageDto({
    required int id,
    @Default('') String body,
    @Default('TEXT') String messageType,
    @Default(false) bool isMine,
    String? sentAt,
    String? attachmentUrl,
    int? appointmentId,
    String? appointmentStatus,
    String? appointmentTitle,
    String? appointmentStart,
    bool? appointmentExpired,
    String? readAt,
  }) = _MessageDto;

  factory MessageDto.fromJson(Map<String, dynamic> json) =>
      _$MessageDtoFromJson(json);
}

@freezed
abstract class MessagesResponse with _$MessagesResponse {
  const factory MessagesResponse({
    @Default([]) List<MessageDto> messages,
    bool? hasMore,
  }) = _MessagesResponse;

  factory MessagesResponse.fromJson(Map<String, dynamic> json) =>
      _$MessagesResponseFromJson(json);
}

// ── Appointments (Agenda) ──

@freezed
abstract class AppointmentDto with _$AppointmentDto {
  const factory AppointmentDto({
    required int id,
    String? type,
    required String title,
    String? description,
    String? start,
    String? end,
    int? durationMinutes,
    String? location,
    String? meetingUrl,
    String? status,
    Coach? coach,
  }) = _AppointmentDto;

  factory AppointmentDto.fromJson(Map<String, dynamic> json) =>
      _$AppointmentDtoFromJson(json);
}

@freezed
abstract class AppointmentsResponse with _$AppointmentsResponse {
  const factory AppointmentsResponse({
    @Default([]) List<AppointmentDto> appointments,
    @Default(false) bool hasMore,
  }) = _AppointmentsResponse;

  factory AppointmentsResponse.fromJson(Map<String, dynamic> json) =>
      _$AppointmentsResponseFromJson(json);
}
