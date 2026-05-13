from django.db import models


class CookieConsentRecord(models.Model):
    """One row per consent submission. Acts as audit log."""
    consent_id = models.CharField(max_length=64, db_index=True)
    user = models.ForeignKey(
        'accounts.User', null=True, blank=True,
        on_delete=models.SET_NULL, related_name='cookie_consents',
    )
    necessary = models.BooleanField(default=True)
    preferences = models.BooleanField(default=False)
    analytics = models.BooleanField(default=False)
    marketing = models.BooleanField(default=False)
    consent_version = models.CharField(max_length=64)
    ip = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.CharField(max_length=512, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.consent_id} {self.consent_version} @ {self.created_at:%Y-%m-%d}'
