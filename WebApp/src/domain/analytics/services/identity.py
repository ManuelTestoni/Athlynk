"""Governance helpers: who is an internal/test user, and which environment are
we in. Used by the PostHog wrappers (super-properties), the feature store
(exclude/segregate), and the ML dataset boundary (never train on dirty data).
"""

from django.conf import settings


def current_environment():
    """development | staging | production (whatever ANALYTICS_ENVIRONMENT says)."""
    return getattr(settings, 'ANALYTICS_ENVIRONMENT', 'development')


def _email_domain(email):
    return (email or '').rsplit('@', 1)[-1].lower().strip()


def resolve_flags(user):
    """Return ``{'is_internal_user': bool, 'is_test_account': bool}`` for a User.

    OR of the persisted ``User`` flags with the env allowlists
    (``TEST_ACCOUNT_EMAILS``, ``INTERNAL_EMAIL_DOMAINS``). Either source flipping
    a flag is enough — the env lists are the quick lever, the DB fields the
    durable per-user toggle.
    """
    if user is None:
        return {'is_internal_user': False, 'is_test_account': False}

    email = (getattr(user, 'email', '') or '').lower().strip()
    test_emails = {e.lower().strip() for e in getattr(settings, 'TEST_ACCOUNT_EMAILS', []) if e}
    internal_domains = {d.lower().strip() for d in getattr(settings, 'INTERNAL_EMAIL_DOMAINS', []) if d}

    is_test = bool(getattr(user, 'is_test_account', False)) or (email in test_emails)
    is_internal = bool(getattr(user, 'is_internal_user', False)) or (_email_domain(email) in internal_domains)
    return {'is_internal_user': is_internal, 'is_test_account': is_test}


def is_excluded(user):
    """True if the user must be kept out of production analytics (test or internal)."""
    f = resolve_flags(user)
    return f['is_internal_user'] or f['is_test_account']
