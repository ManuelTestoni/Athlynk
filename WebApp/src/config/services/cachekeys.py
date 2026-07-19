"""Central cache-key builders + invalidation helpers.

Every server-side cache entry goes through a builder here — never build key
strings inline in views. Builders *require* the owning id in their signature,
so a personalized payload can't accidentally be cached under a shared key
(cross-user leakage by construction impossible).

Key format: athlynk:{VERSION}:{scope}:{ident}:{resource}[:...parts]
Bump VERSION to invalidate everything after a payload-shape change.

Catalog searches use a *generation* counter instead of pattern deletes:
the generation number is part of the key, and invalidating means bumping
the counter — O(1), works identically on Redis and LocMem (dev/tests),
no django-redis-only delete_pattern.
"""

import hashlib

from django.core.cache import cache

VERSION = 1


def _k(scope, ident, resource, *parts):
    return ':'.join(['athlynk', str(VERSION), scope, str(ident), resource]
                    + [str(p) for p in parts])


def _h(*parts):
    """Hash free-text key parts (search queries, filter combos): keeps keys
    short and safe regardless of user input."""
    raw = '\x1f'.join(str(p) for p in parts)
    return hashlib.md5(raw.encode('utf-8', errors='ignore')).hexdigest()


# --- generation counters (for keys that can't be enumerated for deletion) ---

def _gen(name):
    key = _k('gen', 'global', name)
    val = cache.get(key)
    if val is None:
        cache.add(key, 1, None)
        val = 1
    return val


def _bump(name):
    key = _k('gen', 'global', name)
    try:
        cache.incr(key)
    except ValueError:
        cache.set(key, 2, None)


# --- key builders -----------------------------------------------------------

def coach_workout_plans(coach_id):
    return _k('coach', coach_id, 'workout_plans')


def coach_nutrition_plans(coach_id):
    return _k('coach', coach_id, 'nutrition_plans')


def coach_dashboard(coach_id, surface):
    # surface: 'web' | 'api' — the two dashboards serialize different payloads.
    return _k('coach', coach_id, 'dashboard', surface)


def client_dashboard(client_id):
    return _k('client', client_id, 'dashboard')


def unread_count(user_id):
    return _k('user', user_id, 'unread')


def dashboard_layout(user_id):
    return _k('user', user_id, 'dashlayout')


def exercise_search(scope, *filters):
    # scope identifies whose customs may appear in the results: 'coach:{id}',
    # 'client:{id}' (athlete app: customs of their active coaches) or 'anon'.
    # Generation bump on any exercise-catalog write invalidates every cached
    # combination at once.
    return _k('catalog', scope or 'anon', 'exsearch', _gen('excat'), _h(*filters))


def food_search(*filters):
    return _k('catalog', 'global', 'foodsearch', _gen('foodcat'), _h(*filters))


def exercise_filters():
    # Muscles/equipment/categories taxonomy: global.
    return _k('catalog', 'global', 'exfilters', _gen('excat'))


def media_url(name):
    return _k('media', 'global', 'url', _h(name))


# --- invalidation -----------------------------------------------------------

def invalidate_coach_plans(coach_id):
    """Call from EVERY workout/nutrition plan, folder or assignment write
    (web views AND api_coach mobile handlers)."""
    cache.delete_many([coach_workout_plans(coach_id),
                       coach_nutrition_plans(coach_id)])


def invalidate_exercise_catalog():
    """Custom-exercise create/update/delete or catalog import."""
    _bump('excat')


def invalidate_food_catalog():
    """Food catalog import scripts."""
    _bump('foodcat')


def invalidate_unread(user_id):
    """Mark-read / mark-all-read: badge must drop to the true count now."""
    cache.delete(unread_count(user_id))


def invalidate_dashboard_layout(user_id):
    """Call from EVERY layout write (web session endpoint AND mobile Bearer
    endpoint) — single path so web and iOS caches can never diverge."""
    cache.delete(dashboard_layout(user_id))
