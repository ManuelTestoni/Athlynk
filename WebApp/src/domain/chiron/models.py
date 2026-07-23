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


class AthleteRecap(models.Model):
    """Storico dei recap generati da CHIRON per un atleta, dal punto di vista
    di un coach (append-only — V2, era upsert singolo in V1).

    Una riga per generazione: dà per gratis lo storico/confronto ("rispetto
    al recap precedente cosa è cambiato") senza una tabella separata.
    `facts_json` è l'audit trail — insight + evidenze + forecast — dietro il
    testo narrativo, così un numero nel recap è sempre tracciabile a un dato
    reale.
    """
    coach = models.ForeignKey(
        'accounts.CoachProfile', on_delete=models.CASCADE, related_name='athlete_recaps',
    )
    client = models.ForeignKey(
        'accounts.ClientProfile', on_delete=models.CASCADE, related_name='recaps',
    )
    facts_json = models.JSONField(default=dict)
    narrative_text = models.TextField(blank=True, default='')
    # True se la riformulazione LLM è fallita/timeout e si è usato il fallback
    # a template deterministici — la UI lo segnala, non lo nasconde.
    narrative_is_fallback = models.BooleanField(default=False)
    content_hash = models.CharField(max_length=64, blank=True, default='')
    generated_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-generated_at']
        indexes = [
            models.Index(fields=['coach', 'client', '-generated_at']),
        ]

    def __str__(self):
        return f"AthleteRecap coach={self.coach_id} client={self.client_id} @ {self.generated_at:%Y-%m-%d %H:%M}"


class AthleteRecapFeedback(models.Model):
    """V3 prep: cattura SOLO il segnale d'uso reale (utile/non utile per
    insight_code), non calibra nulla ora — la calibrazione delle soglie in
    insights.py resta un passo successivo, da fare quando c'è abbastanza
    segnale accumulato, non alla cieca oggi (vedi §V3 del piano recap).
    """
    coach = models.ForeignKey(
        'accounts.CoachProfile', on_delete=models.CASCADE, related_name='recap_feedback_given',
    )
    client = models.ForeignKey(
        'accounts.ClientProfile', on_delete=models.CASCADE, related_name='recap_feedback',
    )
    recap = models.ForeignKey(
        AthleteRecap, on_delete=models.CASCADE, related_name='feedback', null=True, blank=True,
    )
    insight_code = models.CharField(max_length=64)
    useful = models.BooleanField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        # Un solo giudizio per insight per generazione di recap — ricliccare
        # aggiorna il voto invece di accumulare righe duplicate.
        unique_together = [('coach', 'client', 'recap', 'insight_code')]

    def __str__(self):
        return f"Feedback {self.insight_code}={self.useful} coach={self.coach_id} client={self.client_id}"


class CoachRecapSettings(models.Model):
    """V3 prep: override per-coach delle soglie di anomalia del motore
    insight (domain/chiron/recap/insights.py), invece di costanti globali
    fisse uguali per tutti. Solo le chiavi presenti sovrascrivono i default —
    un coach non tocca mai le soglie degli altri, e un coach senza questa riga
    usa semplicemente i default (nessuna migrazione dati necessaria)."""
    coach = models.OneToOneField(
        'accounts.CoachProfile', on_delete=models.CASCADE, related_name='recap_settings',
    )
    thresholds = models.JSONField(default=dict, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"CoachRecapSettings coach={self.coach_id}"
