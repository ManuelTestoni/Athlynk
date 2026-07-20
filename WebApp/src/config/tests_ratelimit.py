"""Regression test for the django-redis IGNORE_EXCEPTIONS fail-open gap.

See [[reference_ratelimit_redis_incr_none]] — cache.incr() returns None (not a
raised ValueError) when Redis is unreachable and IGNORE_EXCEPTIONS is set,
which used to crash `hit()` with a TypeError on `limit - None`.
"""
from unittest.mock import patch

from django.test import TestCase

from config.services import ratelimit


class RatelimitHitTests(TestCase):
    def test_normal_increment(self):
        allowed, remaining = ratelimit.hit('t_normal', 'user1', 5, 60)
        self.assertTrue(allowed)
        self.assertEqual(remaining, 4)

    def test_incr_returning_none_fails_open(self):
        """django-redis + IGNORE_EXCEPTIONS returns None on a dead connection
        instead of raising — hit() must not crash on `limit - count`."""
        with patch.object(ratelimit.cache, 'incr', return_value=None):
            allowed, remaining = ratelimit.hit('t_none', 'user2', 5, 60)
        self.assertTrue(allowed)
        self.assertEqual(remaining, 5)
