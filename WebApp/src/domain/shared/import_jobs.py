"""Background import job store (Django cache + thread spawner).

Generic primitives reused by nutrition and workouts AI-import features.

Job payload shape:
  {
    'status': 'queued' | 'running' | 'done' | 'error',
    'phase': str,                 # named pipeline phase
    'percent': int,               # 0..100
    'result': dict | None,        # filled when status == 'done'
    'error_code': str | None,
    'detail': str | None,
  }

TODO Fase 2: replace threading with Celery (single broker for both domains)
when the deployment moves to multi-worker.
"""

from __future__ import annotations

import threading
import uuid
from typing import Callable, Optional

from django.core.cache import cache


DEFAULT_TTL = 600  # 10 minutes


class JobStore:
    """Namespaced cache wrapper. One instance per import domain (nutrition, workouts)."""

    def __init__(self, prefix: str, ttl: int = DEFAULT_TTL):
        if not prefix or not prefix.endswith(':'):
            raise ValueError("prefix must be non-empty and end with ':'")
        self.prefix = prefix
        self.ttl = ttl

    def key(self, job_id: str) -> str:
        return f'{self.prefix}{job_id}'

    def new_id(self) -> str:
        return uuid.uuid4().hex

    def set(self, job_id: str, payload: dict) -> None:
        cache.set(self.key(job_id), payload, self.ttl)

    def get(self, job_id: str) -> Optional[dict]:
        return cache.get(self.key(job_id))

    def update(self, job_id: str, patch: dict) -> dict:
        existing = self.get(job_id) or {}
        existing.update(patch)
        self.set(job_id, existing)
        return existing

    def progress_cb(self, job_id: str) -> Callable[[str, int], None]:
        """Return a callback compatible with pipeline progress reporting."""
        def _cb(phase: str, percent: int) -> None:
            self.update(job_id, {
                'status': 'running',
                'phase': phase,
                'percent': max(0, min(100, int(percent))),
            })
        return _cb

    def spawn(self, target: Callable, args: tuple = (), kwargs: Optional[dict] = None,
              initial_phase: str = 'queued') -> str:
        """Allocate a job_id, mark it queued, start a daemon thread on `target`.

        `target` signature: target(job_id, *args, **kwargs). Worker is responsible
        for calling set('done'/'error', ...) at the end.
        """
        job_id = self.new_id()
        self.set(job_id, {'status': 'queued', 'phase': initial_phase, 'percent': 0})
        thread = threading.Thread(
            target=target,
            args=(job_id, *args),
            kwargs=kwargs or {},
            daemon=True,
        )
        thread.start()
        return job_id


def serialize_status(job_id: str, job: Optional[dict]) -> dict:
    """Flatten a job payload for the polling endpoint."""
    if not job:
        return {'job_id': job_id, 'status': 'not_found'}
    payload = {
        'job_id': job_id,
        'status': job.get('status'),
        'phase': job.get('phase'),
        'percent': job.get('percent', 0),
    }
    if job.get('status') == 'done':
        payload['result'] = job.get('result')
    elif job.get('status') == 'error':
        payload['error_code'] = job.get('error_code')
        payload['detail'] = job.get('detail')
    return payload
