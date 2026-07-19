from django.core.cache import cache
from django.http import JsonResponse
from django.shortcuts import get_object_or_404
from django.views.decorators.http import require_http_methods

from domain.chat.models import Notification

from .services import cachekeys
from .session_utils import get_session_user


def api_notifications_list(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    qs = Notification.objects.filter(target_user=user).order_by('-created_at')[:30]
    notifications = [{
        'id': n.id,
        'type': n.notification_type,
        'title': n.title,
        'body': n.body or '',
        'link_url': n.link_url or '',
        'is_read': n.is_read,
        'created_at': n.created_at.isoformat(),
    } for n in qs]
    return JsonResponse({'notifications': notifications})


def api_notifications_unread_count(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'count': 0})
    # Polled every 15s per open tab (static/js/notifications.js): cache for the
    # poll interval so N tabs cost at most one COUNT per 15s. Mark-read deletes
    # the key, so the badge clears instantly.
    _key = cachekeys.unread_count(user.id)
    count = cache.get(_key)
    if count is None:
        count = Notification.objects.filter(target_user=user, is_read=False).count()
        cache.set(_key, count, 15)
    return JsonResponse({'count': count})


@require_http_methods(["POST"])
def api_notification_mark_read(request, notification_id):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    n = get_object_or_404(Notification, id=notification_id, target_user=user)
    n.is_read = True
    n.save(update_fields=['is_read'])
    cachekeys.invalidate_unread(user.id)
    return JsonResponse({'status': 'ok'})


@require_http_methods(["POST"])
def api_notifications_mark_all_read(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    Notification.objects.filter(target_user=user, is_read=False).update(is_read=True)
    cachekeys.invalidate_unread(user.id)
    return JsonResponse({'status': 'ok'})
