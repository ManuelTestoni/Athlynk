from django.contrib import admin
from .models import Subscriber, SubscriptionEvent


@admin.register(Subscriber)
class SubscriberAdmin(admin.ModelAdmin):
    list_display = ('email', 'status', 'consent_version', 'created_at', 'confirmed_at', 'unsubscribed_at')
    list_filter = ('status', 'consent_version')
    search_fields = ('email',)
    readonly_fields = ('created_at', 'confirmed_at', 'unsubscribed_at',
                       'subscribed_ip', 'subscribed_user_agent',
                       'confirm_token', 'unsubscribe_token')


@admin.register(SubscriptionEvent)
class SubscriptionEventAdmin(admin.ModelAdmin):
    list_display = ('subscriber', 'event_type', 'created_at', 'ip')
    list_filter = ('event_type',)
    readonly_fields = ('subscriber', 'event_type', 'ip', 'user_agent', 'created_at')
