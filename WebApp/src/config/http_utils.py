"""Small shared helpers for parsing request query params and coach-scoped JSON APIs."""

from __future__ import annotations

import json
from typing import Any, Callable

from django.http import HttpRequest, JsonResponse

from .session_utils import get_session_coach, get_session_user


def safe_int(params, key, default):
    """int(params.get(key, default)), falling back to default on garbage input."""
    try:
        return int(params.get(key, default))
    except (TypeError, ValueError):
        return default


def require_coach(
    request: HttpRequest, extra_check: Callable[[Any], bool] | None = None,
) -> tuple[Any, None] | tuple[None, JsonResponse]:
    """Resolve the logged-in coach for a JSON API view.

    Returns (coach, None) on success, or (None, error_response) — 401 if no
    session user, 403 if there's no coach profile or extra_check(coach) fails.
    """
    user = get_session_user(request)
    if not user:
        return None, JsonResponse({'error': 'Unauthenticated'}, status=401)
    coach = get_session_coach(request)
    if not coach or (extra_check and not extra_check(coach)):
        return None, JsonResponse({'error': 'forbidden'}, status=403)
    return coach, None


def parse_json_body(request: HttpRequest) -> tuple[dict, None] | tuple[None, JsonResponse]:
    """Decode a JSON request body. Returns (data, None) or (None, 400 response)."""
    try:
        body = request.body.decode('utf-8') if isinstance(request.body, bytes) else request.body
        return json.loads(body) if body else {}, None
    except Exception:
        return None, JsonResponse({'error': 'invalid json'}, status=400)


def serialize_folder(folder: Any, count_key: str, count: int) -> dict:
    """Shared shape for Check/Workout/Nutrition folder taxonomy endpoints.

    count_key is 'template_count' (checks) or 'plan_count' (workouts/nutrition).
    """
    return {
        'id': folder.id,
        'title': folder.title,
        'label_text': folder.label_text or '',
        'label_color': folder.label_color or '',
        'order': folder.order,
        count_key: count,
    }
