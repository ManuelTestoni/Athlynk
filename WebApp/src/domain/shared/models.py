"""Durable record of a background import job.

Nutrition/workout PDF/Excel imports run in a daemon thread while the browser
polls for status. That status used to live *only* in a 600 s Redis key: a Redis
blip (cache is fail-open, `IGNORE_EXCEPTIONS: True`) or a recycled gunicorn
worker silently lost the terminal `done`/`error` write, so the wizard hung until
the key TTL'd out and then showed "Sessione scaduta".

This table is the source of truth. The cache is a fast read-through mirror on
top of it — see `domain.shared.import_jobs.JobStore`. Rows are short-lived
(pruned after ~1 day by the analytics cron).
"""

from django.db import models


class ImportJob(models.Model):
    STATUS_QUEUED = 'queued'
    STATUS_RUNNING = 'running'
    STATUS_DONE = 'done'
    STATUS_ERROR = 'error'
    STATUS_CHOICES = [
        (STATUS_QUEUED, 'Queued'),
        (STATUS_RUNNING, 'Running'),
        (STATUS_DONE, 'Done'),
        (STATUS_ERROR, 'Error'),
    ]

    # uuid4().hex — the exact job_id string handed to the frontend as the poll key.
    id = models.CharField(primary_key=True, max_length=32)
    # 'nutrition' | 'workout' (which import domain produced this job).
    domain = models.CharField(max_length=32, blank=True, default='')
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default=STATUS_QUEUED)
    phase = models.CharField(max_length=32, blank=True, default='')
    percent = models.PositiveSmallIntegerField(default=0)
    result = models.JSONField(null=True, blank=True)
    error_code = models.CharField(max_length=64, blank=True, default='')
    detail = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'shared_import_job'
        indexes = [models.Index(fields=['created_at'])]  # cleanup by age

    def __str__(self):
        return f'{self.domain}:{self.id}:{self.status}'
