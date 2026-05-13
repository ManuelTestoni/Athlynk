from django.db import models


class Subscriber(models.Model):
    STATUS_PENDING = 'PENDING'
    STATUS_CONFIRMED = 'CONFIRMED'
    STATUS_UNSUBSCRIBED = 'UNSUBSCRIBED'
    STATUS_CHOICES = [
        (STATUS_PENDING, 'In attesa'),
        (STATUS_CONFIRMED, 'Iscritto'),
        (STATUS_UNSUBSCRIBED, 'Disiscritto'),
    ]

    email = models.EmailField(unique=True)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default=STATUS_PENDING)
    confirm_token = models.CharField(max_length=128, blank=True, default='')
    unsubscribe_token = models.CharField(max_length=128, unique=True)
    consent_version = models.CharField(max_length=64)
    consent_text_snapshot = models.TextField()
    subscribed_ip = models.GenericIPAddressField(null=True, blank=True)
    subscribed_user_agent = models.CharField(max_length=512, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    confirmed_at = models.DateTimeField(null=True, blank=True)
    unsubscribed_at = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f'{self.email} ({self.status})'


class SubscriptionEvent(models.Model):
    EVENT_SIGNUP = 'SIGNUP'
    EVENT_CONFIRM = 'CONFIRM'
    EVENT_UNSUBSCRIBE = 'UNSUBSCRIBE'
    EVENT_RESEND = 'RESEND'
    EVENT_RESUBSCRIBE = 'RESUBSCRIBE'

    subscriber = models.ForeignKey(Subscriber, on_delete=models.CASCADE, related_name='events')
    event_type = models.CharField(max_length=32)
    ip = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.CharField(max_length=512, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f'{self.subscriber.email} {self.event_type} @ {self.created_at:%Y-%m-%d}'
