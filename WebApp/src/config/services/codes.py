"""Human-friendly access codes for platform purchases.

Format ATHLYNK-XXXX-XXXX over an unambiguous alphabet (no O/0/I/1), generated
with `secrets` (same crypto source as services.tokens). Emailed after a platform
purchase; redeemed later by the app login.
"""
import secrets

# No O/0/I/1 — avoids read-aloud / typing ambiguity.
_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'


def _segment(n: int = 4) -> str:
    return ''.join(secrets.choice(_ALPHABET) for _ in range(n))


def generate_platform_code() -> str:
    """Return a unique ATHLYNK-XXXX-XXXX code (checked against existing rows)."""
    from domain.billing.models import PlatformPurchase
    while True:
        code = f'ATHLYNK-{_segment()}-{_segment()}'
        if not PlatformPurchase.objects.filter(code=code).exists():
            return code
