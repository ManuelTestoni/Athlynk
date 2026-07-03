"""Small shared helpers for parsing request query params."""


def safe_int(params, key, default):
    """int(params.get(key, default)), falling back to default on garbage input."""
    try:
        return int(params.get(key, default))
    except (TypeError, ValueError):
        return default
