from django.contrib import admin
from .models import CookieConsentRecord


@admin.register(CookieConsentRecord)
class CookieConsentRecordAdmin(admin.ModelAdmin):
    list_display = ('consent_id', 'user', 'consent_version', 'preferences', 'analytics', 'marketing', 'created_at')
    list_filter = ('consent_version', 'preferences', 'analytics', 'marketing')
    search_fields = ('consent_id', 'user__email', 'ip')
    readonly_fields = tuple(f.name for f in CookieConsentRecord._meta.fields)
