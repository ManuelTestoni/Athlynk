"""Tests for the durable import-job store and the wall-clock budget helper.

These cover the core stall fix: the terminal status/result must survive even when
the (fail-open) cache silently drops writes, and a misbehaving pipeline must always
resolve to a terminal status within its budget.
"""

import time
from unittest import mock

from django.test import TestCase

from domain.shared.import_jobs import JobStore, run_bounded
from domain.shared.models import ImportJob


class JobStoreDurabilityTests(TestCase):
    def setUp(self):
        self.store = JobStore(prefix='test_import:', ttl=600, domain='nutrition')

    def test_set_get_roundtrip_and_db_source_of_truth(self):
        jid = self.store.new_id()
        self.store.set(jid, {'status': 'queued', 'phase': 'analyze', 'percent': 0})
        got = self.store.get(jid)
        self.assertEqual(got['status'], 'queued')
        # DB row is the source of truth.
        row = ImportJob.objects.get(pk=jid)
        self.assertEqual(row.status, 'queued')
        self.assertEqual(row.domain, 'nutrition')

    def test_partial_set_does_not_clobber_result(self):
        jid = self.store.new_id()
        self.store.set(jid, {'status': 'done', 'percent': 100, 'result': {'a': 1}})
        # A later progress-style write must not wipe the stored result.
        self.store.set(jid, {'status': 'running', 'percent': 42})
        row = ImportJob.objects.get(pk=jid)
        self.assertEqual(row.result, {'a': 1})

    def test_terminal_write_survives_dropped_cache(self):
        """The bug: fail-open Redis silently drops the 'done' write and the wizard
        hangs. With the DB as source of truth, get() still returns 'done'."""
        jid = self.store.new_id()
        # Simulate a cache that drops every write and misses every read.
        fake = mock.MagicMock()
        fake.get.return_value = None
        with mock.patch('domain.shared.import_jobs.cache', fake):
            self.store.set(jid, {'status': 'done', 'percent': 100, 'result': {'ok': True}})
            got = self.store.get(jid)
        self.assertIsNotNone(got)
        self.assertEqual(got['status'], 'done')
        self.assertEqual(got['result'], {'ok': True})

    def test_get_unknown_job_returns_none(self):
        self.assertIsNone(self.store.get('does-not-exist'))


class RunBoundedTests(TestCase):
    def test_done(self):
        outcome, val = run_bounded(lambda: 21 * 2, budget_seconds=5)
        self.assertEqual(outcome, 'done')
        self.assertEqual(val, 42)

    def test_error_is_surfaced(self):
        def boom():
            raise ValueError('nope')
        outcome, val = run_bounded(boom, budget_seconds=5)
        self.assertEqual(outcome, 'error')
        self.assertIsInstance(val, ValueError)

    def test_timeout_returns_fast(self):
        started = time.time()
        outcome, val = run_bounded(lambda: time.sleep(30), budget_seconds=0.2)
        elapsed = time.time() - started
        self.assertEqual(outcome, 'timeout')
        self.assertIsNone(val)
        self.assertLess(elapsed, 5)  # must not wait for the full 30s sleep


class QuotaRefundTests(TestCase):
    def test_refund_undoes_a_consume(self):
        """A failed import is charged in the POST then refunded by the worker —
        net zero, so a stalling import can't burn the coach's daily allowance."""
        from config.services import import_quota

        class _Coach:
            id = 4242

        coach = _Coach()
        allowed, rem1 = import_quota.consume(coach, import_quota.DIET)
        self.assertTrue(allowed)
        import_quota.refund(coach.id, import_quota.DIET)
        allowed_again, rem2 = import_quota.consume(coach, import_quota.DIET)
        self.assertTrue(allowed_again)
        # The refund gave the slot back, so the second consume sees the same
        # remaining as the first — the failed attempt cost nothing.
        self.assertEqual(rem2, rem1)
