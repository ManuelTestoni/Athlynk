from django.db import models


class Conversation(models.Model):
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='conversations_as_coach')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='conversations_as_client')
    last_message_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = [('coach', 'client')]
        ordering = ['-last_message_at', '-created_at']
        indexes = [
            models.Index(fields=['-last_message_at']),
        ]

    def __str__(self):
        return f"Chat {self.coach} ↔ {self.client}"


class Message(models.Model):
    MESSAGE_TYPES = [
        ('TEXT', 'Text'),
        ('IMAGE', 'Image'),
        ('VIDEO', 'Video'),
        ('APPOINTMENT_REQUEST', 'Appointment Request'),
        ('APPOINTMENT_RESPONSE', 'Appointment Response'),
    ]

    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name='messages')
    sender_user = models.ForeignKey('accounts.User', on_delete=models.CASCADE, related_name='sent_messages')
    body = models.TextField(blank=True)
    message_type = models.CharField(max_length=30, choices=MESSAGE_TYPES, default='TEXT')
    attachment = models.FileField(upload_to='chat_attachments/', null=True, blank=True)
    appointment = models.ForeignKey('calendar.Appointment', on_delete=models.SET_NULL, null=True, blank=True, related_name='chat_messages')
    sent_at = models.DateTimeField(auto_now_add=True)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['sent_at']
        indexes = [
            models.Index(fields=['conversation', '-sent_at']),
            models.Index(fields=['conversation', 'read_at']),
        ]

    def __str__(self):
        return f"Message #{self.id} from {self.sender_user_id} at {self.sent_at}"


class Notification(models.Model):
    NOTIFICATION_TYPES = [
        ('MESSAGE', 'New Message'),
        ('APPOINTMENT_REQUEST', 'Appointment Request'),
        ('APPOINTMENT_ACCEPTED', 'Appointment Accepted'),
        ('APPOINTMENT_REJECTED', 'Appointment Rejected'),
        ('CHECK_SUBMITTED', 'Check Submitted'),
        ('CHECK_REVIEWED', 'Check Reviewed'),
        ('WORKOUT_ASSIGNED', 'Workout Assigned'),
        ('NUTRITION_ASSIGNED', 'Nutrition Plan Assigned'),
        ('SUPPLEMENT_ASSIGNED', 'Supplement Sheet Assigned'),
        ('MACRO_REMINDER', 'Macro Log Reminder'),
    ]

    target_user = models.ForeignKey('accounts.User', on_delete=models.CASCADE, related_name='notifications')
    notification_type = models.CharField(max_length=50, choices=NOTIFICATION_TYPES)
    title = models.CharField(max_length=200)
    body = models.TextField(null=True, blank=True)
    link_url = models.CharField(max_length=500, null=True, blank=True)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['target_user', 'is_read', '-created_at']),
        ]

    def __str__(self):
        return f"Notif to {self.target_user_id}: {self.title}"


class AutomaticMessageTemplate(models.Model):
    EVENT_TYPES = [
        ('WELCOME', 'Benvenuto'),
        ('GOODBYE', 'Arrivederci'),
        ('SUBSCRIPTION_EXPIRING', 'Abbonamento in scadenza'),
    ]

    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='automatic_message_templates')
    event_type = models.CharField(max_length=30, choices=EVENT_TYPES)
    body = models.TextField(blank=True)
    attachment = models.FileField(upload_to='automatic_messages/', null=True, blank=True)
    is_enabled = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = [('coach', 'event_type')]

    def __str__(self):
        return f"AutoMsg {self.event_type} for coach {self.coach_id}"
