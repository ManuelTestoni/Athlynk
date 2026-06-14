from django.db import models

from domain.accounts.models import User


class ChironMessage(models.Model):
    ROLE_CHOICES = [
        ('user', 'User'),
        ('assistant', 'Assistant'),
    ]

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='chiron_messages',
    )
    role = models.CharField(max_length=16, choices=ROLE_CHOICES)
    content = models.TextField()
    sources = models.JSONField(default=list, blank=True)
    # Link/azioni app cliccabili prodotti dai coach tool (label + url).
    actions = models.JSONField(default=list, blank=True)
    used_web_search = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ['created_at']
        indexes = [
            models.Index(fields=['user', 'created_at']),
        ]

    def __str__(self):
        return f"CHIRON[{self.role}] {self.user_id} @ {self.created_at:%Y-%m-%d %H:%M}"


class ChironSummary(models.Model):
    """Memoria a riassunto rotante per utente.

    I messaggi fino a `summary_up_to_id` sono compressi in `summary`; i più recenti
    restano integrali. Tiene il contesto del modello bounded (meno token, meno
    allucinazioni sulle conversazioni lunghe). Vedi chiron.memory.
    """
    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name='chiron_summary',
    )
    summary = models.TextField(blank=True, default='')
    summary_up_to_id = models.BigIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"CHIRONSummary {self.user_id} (up_to={self.summary_up_to_id})"
