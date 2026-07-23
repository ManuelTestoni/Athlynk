"""Background import job store + thread spawner.

Generic primitives reused by nutrition and workouts AI-import features.

Durability: the job status/result is the source of truth in the DB
(`domain.shared.models.ImportJob`); the Django cache is only a fast read-through
mirror. Every write goes to the DB first, then mirrors to cache. Reads hit the
cache and fall back to the DB on a miss (Redis blip, evicted key, worker that
recycled). This is what stops the wizard from hanging when a terminal
`done`/`error` write is dropped by the fail-open Redis cache.

Job payload shape (flat dict returned by `get`):
  {
    'status': 'queued' | 'running' | 'done' | 'error',
    'phase': str, 'percent': int,
    'result': dict | None,          # filled when status == 'done'
    'error_code': str | None, 'detail': str | None,
  }

TODO Fase 2: replace threading with Celery (single broker for both domains)
when the deployment moves to multi-worker.
"""

from __future__ import annotations

import threading
import uuid
from typing import Callable, Literal, Optional, TypedDict

from django.core.cache import cache
from django.db import close_old_connections


DEFAULT_TTL = 600  # 10 minutes (cache mirror only; DB row lives ~1 day)

JobStatus = Literal['queued', 'running', 'done', 'error']

# Payload keys that map 1:1 to ImportJob columns.
_COLUMNS = ('status', 'phase', 'percent', 'result', 'error_code', 'detail')


class JobPayload(TypedDict, total=False):
    """Job payload. Partial by design: each pipeline phase writes the subset of
    keys it knows about (total=False)."""
    status: JobStatus
    phase: str
    percent: int
    result: dict[str, object] | None      # filled when status == 'done'
    error_code: str | None
    detail: str | None


class JobStore:
    """Namespaced, DB-backed job store. One instance per import domain."""

    def __init__(self, prefix: str, ttl: int = DEFAULT_TTL, domain: str = ''):
        if not prefix or not prefix.endswith(':'):
            raise ValueError("prefix must be non-empty and end with ':'")
        self.prefix = prefix
        self.ttl = ttl
        self.domain = domain

    def key(self, job_id: str) -> str:
        return f'{self.prefix}{job_id}'

    def new_id(self) -> str:
        return uuid.uuid4().hex

    # --- persistence -------------------------------------------------------

    def _row_payload(self, row) -> JobPayload:
        return {
            'status': row.status,
            'phase': row.phase,
            'percent': row.percent,
            'result': row.result,
            'error_code': row.error_code or None,
            'detail': row.detail or None,
        }

    def set(self, job_id: str, payload: JobPayload) -> None:
        """Merge-upsert the provided fields into the DB row, then mirror to cache.

        Only keys present in `payload` are written, so a progress `set` never
        clobbers a `result` and vice-versa. The DB write is the durable one; the
        cache mirror is best-effort (fail-open Redis may drop it)."""
        from domain.shared.models import ImportJob

        defaults = {k: payload[k] for k in _COLUMNS if k in payload}
        if self.domain:
            defaults['domain'] = self.domain
        try:
            row, _ = ImportJob.objects.update_or_create(id=job_id, defaults=defaults)
            self._mirror(job_id, self._row_payload(row))
        except Exception:
            # DB unavailable: fall back to a cache-only write so we degrade to the
            # old behavior rather than raising inside a background thread.
            self._mirror(job_id, dict(payload))

    def _mirror(self, job_id: str, payload: JobPayload) -> None:
        cache.set(self.key(job_id), payload, self.ttl)

    def get(self, job_id: str) -> Optional[JobPayload]:
        cached = cache.get(self.key(job_id))
        if cached is not None:
            return cached
        # Cache miss (blip / eviction / TTL / other worker): read the source of truth.
        from domain.shared.models import ImportJob
        try:
            row = ImportJob.objects.filter(pk=job_id).first()
        except Exception:
            return None
        if row is None:
            return None
        payload = self._row_payload(row)
        self._mirror(job_id, payload)  # re-warm the mirror
        return payload

    def update(self, job_id: str, patch: JobPayload) -> JobPayload:
        # set() already merges at the DB level.
        self.set(job_id, patch)
        return self.get(job_id) or dict(patch)

    def progress_cb(self, job_id: str) -> Callable[[str, int], None]:
        """Return a callback compatible with pipeline progress reporting."""
        def _cb(phase: str, percent: int) -> None:
            self.set(job_id, {
                'status': 'running',
                'phase': phase,
                'percent': max(0, min(100, int(percent))),
            })
        return _cb

    def spawn(self, target: Callable[..., object], args: tuple[object, ...] = (),
              kwargs: Optional[dict[str, object]] = None,
              initial_phase: str = 'queued') -> str:
        """Allocate a job_id, mark it queued (DB + cache), start a daemon thread.

        `target` signature: target(job_id, *args, **kwargs). Worker is responsible
        for writing a terminal set('done'/'error', ...) — see `run_bounded`.
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


def serialize_status(job_id: str, job: Optional[JobPayload]) -> dict[str, object]:
    """Flatten a job payload for the polling endpoint."""
    if not job:
        return {'job_id': job_id, 'status': 'not_found'}
    payload: dict[str, object] = {
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


BudgetOutcome = Literal['done', 'error', 'timeout']


def run_bounded(fn: Callable[[], object], budget_seconds: float
                ) -> tuple[BudgetOutcome, object]:
    """Run `fn()` in a daemon thread and wait at most `budget_seconds`.

    Returns ('done', result) | ('error', exception) | ('timeout', None).

    Guarantees the caller can always write a terminal job status within the
    budget, no matter what `fn` does — even a networked call that never honors
    its own timeout. A timed-out `fn` is left running orphaned (CPython can't
    kill a thread); the caller marks the job errored so the wizard never hangs.
    """
    box: dict[str, object] = {}

    def _run() -> None:
        try:
            box['ok'] = fn()
        except BaseException as exc:  # noqa: BLE001 — surfaced to the caller verbatim
            box['err'] = exc
        finally:
            close_old_connections()  # don't leak this thread's DB connection

    t = threading.Thread(target=_run, daemon=True)
    t.start()
    t.join(budget_seconds)
    if t.is_alive():
        return 'timeout', None
    if 'err' in box:
        return 'error', box['err']
    return 'done', box.get('ok')
