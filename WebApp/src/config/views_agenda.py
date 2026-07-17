from django.shortcuts import render, redirect
from django.http import JsonResponse
from django.utils.dateparse import parse_datetime
from django.views.decorators.http import require_http_methods
import json
import datetime

from domain.accounts.models import ClientProfile
try:
    from domain.calendar.models import Appointment
except ImportError:
    from domain.appointments.models import Appointment  # type: ignore[no-redef]

from .session_utils import get_session_user, get_session_coach, get_session_client, get_active_relationship
from .views_client import _build_activity_events


TYPE_COLORS = {
    'check': '#4A5A8A',
    'prima_visita': '#4F7A6A',
    'visita': '#1E3A5F',
    'consulenza': '#8A6A1E',
}

# Athlete activity (workouts actually done, checks submitted, food logged) —
# distinct from the scheduled-appointment types above. 'check' is remapped to
# 'check_fatto' so it never collides with the appointment_type='check' color.
ACTIVITY_TYPE_COLORS = {
    'allenamento_fatto': '#3F7A5E',
    'check_fatto': '#4A5A8A',
    'macro': '#8A6A1E',
}
ACTIVITY_CALENDAR_TYPE = {'check': 'check_fatto'}

# Athlete activity only ever looks backward (a workout/check/food entry can't
# be logged for the future) — bound the trailing history so an active
# athlete's full log doesn't get re-serialized into every agenda load.
ACTIVITY_TRAILING_DAYS = 90


def _activity_to_agenda_event(ev):
    """Adapt a _build_activity_events() row into the same envelope shape
    _serialize_event() produces for Appointment, so the agenda grid/pill
    rendering doesn't need to special-case the two sources."""
    d = datetime.date.fromisoformat(ev['date'])
    start = datetime.datetime.combine(d, datetime.time(12, 0))
    cal_type = ACTIVITY_CALENDAR_TYPE.get(ev['type'], ev['type'])
    return {
        'id': f"activity-{ev['id']}",
        'title': ev['title'],
        'start': start.isoformat(),
        'end': (start + datetime.timedelta(minutes=30)).isoformat(),
        'duration_minutes': 30,
        'type': cal_type,
        'color': ACTIVITY_TYPE_COLORS.get(cal_type, '#5B6B78'),
        'client_id': None,
        'client_name': '',
        'status': 'DONE',
        'description': ev.get('subtitle', ''),
        'meeting_url': '',
        'is_recurring': False,
        'recurrence_rule': '',
        'check_url': '',
        'is_activity': True,
        'detail_url': ev.get('url', ''),
        'count': ev.get('count'),
        'items': ev.get('items'),
    }


def _client_activity_agenda_events(client):
    today = datetime.date.today()
    window_start = today - datetime.timedelta(days=ACTIVITY_TRAILING_DAYS)
    return [_activity_to_agenda_event(ev)
            for ev in _build_activity_events(client, window_start, today)]


def _parse_duration(raw):
    """Coerce a duration payload to a positive int of minutes. Returns None if invalid."""
    try:
        minutes = int(raw)
    except (TypeError, ValueError):
        return None
    return minutes if minutes >= 1 else None


def _serialize_event(evt, *, coach_view):
    title = evt.title
    if coach_view:
        title = f"{evt.title} – {evt.client.first_name} {evt.client.last_name}"
    return {
        'id': evt.id,
        'title': title,
        'start': evt.start_datetime.isoformat(),
        'end': evt.end_datetime.isoformat(),
        'duration_minutes': evt.duration_minutes,
        'type': evt.appointment_type,
        'color': TYPE_COLORS.get(evt.appointment_type.lower(), '#5B6B78'),
        'client_id': evt.client_id,
        'client_name': f"{evt.client.first_name} {evt.client.last_name}",
        'status': evt.status,
        'description': evt.description or '',
        'meeting_url': evt.meeting_url or '',
        'is_recurring': evt.is_recurring,
        'recurrence_rule': evt.recurrence_rule or '',
        'check_url': '/check/crea/' if evt.appointment_type.lower() == 'check' else '',
    }


def agenda_dashboard_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return redirect('client_blocked')

        events = Appointment.objects.filter(coach=relationship.coach, client=client).select_related('client')
        events_data = [_serialize_event(e, coach_view=False) for e in events]
        events_data += _client_activity_agenda_events(client)

        context = {
            'coach': relationship.coach,
            'client': client,
            'events_json': json.dumps(events_data),
            'can_manage_agenda': False,
            'is_client': True,
        }
        return render(request, 'pages/agenda/dashboard.html', context)

    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    events = Appointment.objects.filter(coach=coach).select_related('client')
    events_data = [_serialize_event(e, coach_view=True) for e in events]

    # Calendar subscription links (Google / Apple) — surface them in agenda header.
    abs_url, webcal_url, google_subscribe = coach_calendar_feed_urls(coach)

    context = {
        'coach': coach,
        'events_json': json.dumps(events_data),
        'can_manage_agenda': True,
        'calendar_feed_url': abs_url,
        'calendar_webcal_url': webcal_url,
        'calendar_google_url': google_subscribe,
    }
    return render(request, 'pages/agenda/dashboard.html', context)


def api_agenda_events(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    if user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return JsonResponse([], safe=False)

        if request.method != 'GET':
            return JsonResponse({'error': 'Forbidden'}, status=403)

        events = Appointment.objects.filter(coach=relationship.coach, client=client).select_related('client')
        events_data = [_serialize_event(e, coach_view=False) for e in events]
        events_data += _client_activity_agenda_events(client)
        return JsonResponse(events_data, safe=False)

    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    if request.method == 'GET':
        events = Appointment.objects.filter(coach=coach).select_related('client')
        return JsonResponse([_serialize_event(e, coach_view=True) for e in events], safe=False)

    elif request.method == 'POST':
        try:
            data = json.loads(request.body)
            client_id = data.get('client_id')
            title = (data.get('title') or '').strip()
            appointment_type = data.get('appointment_type', 'check')
            start_datetime = parse_datetime(data.get('start_datetime') or '')
            duration_minutes = _parse_duration(data.get('duration_minutes'))
            is_recurring = bool(data.get('is_recurring', False))
            recurrence_rule = data.get('recurrence_rule', '') or None

            if not title or not client_id or not start_datetime:
                return JsonResponse({'error': 'Campi obbligatori mancanti'}, status=400)

            if duration_minutes is None:
                return JsonResponse(
                    {'error': "Indica una durata valida (almeno 1 minuto)."},
                    status=400,
                )

            try:
                client = ClientProfile.objects.get(id=client_id, coaching_relationships_as_client__coach=coach)
            except ClientProfile.DoesNotExist:
                return JsonResponse({'error': 'Atleta non trovato.'}, status=400)

            RECURRENCE_DAYS = {'settimanale': 7, 'bisettimanale': 14, 'mensile': 30}
            occurrences = 1
            delta_days = 0

            if is_recurring and appointment_type == 'check' and recurrence_rule in RECURRENCE_DAYS:
                delta_days = RECURRENCE_DAYS[recurrence_rule]
                occurrences = 8

            created = []
            for i in range(occurrences):
                offset = datetime.timedelta(days=delta_days * i)
                evt = Appointment.objects.create(
                    coach=coach,
                    client=client,
                    title=title,
                    appointment_type=appointment_type,
                    start_datetime=start_datetime + offset,
                    duration_minutes=duration_minutes,
                    description=data.get('description', ''),
                    meeting_url=data.get('meeting_url', '') if appointment_type == 'consulenza' else '',
                    is_recurring=is_recurring and i == 0,
                    recurrence_rule=recurrence_rule if is_recurring else None,
                    status='SCHEDULED',
                )
                created.append(evt.id)

            return JsonResponse({'status': 'success', 'event_id': created[0], 'count': len(created)})
        except Exception as e:
            return JsonResponse({'error': str(e)}, status=500)

    return JsonResponse({'error': 'Method not allowed'}, status=405)


@require_http_methods(['PUT', 'DELETE'])
def api_agenda_event_detail(request, event_id):
    """Edit or delete an appointment. Coach-only (any professional type)."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    if user.role == 'CLIENT':
        return JsonResponse({'error': 'Solo i professionisti possono modificare gli appuntamenti.'}, status=403)

    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)

    try:
        evt = Appointment.objects.select_related('client').get(id=event_id, coach=coach)
    except Appointment.DoesNotExist:
        return JsonResponse({'error': 'Appuntamento non trovato.'}, status=404)

    if request.method == 'DELETE':
        evt.delete()
        return JsonResponse({'status': 'deleted'})

    # PUT
    try:
        data = json.loads(request.body)
    except json.JSONDecodeError:
        return JsonResponse({'error': 'Payload non valido.'}, status=400)

    title = (data.get('title') or '').strip()
    appointment_type = data.get('appointment_type', evt.appointment_type)
    start_datetime = parse_datetime(data.get('start_datetime') or '')
    duration_minutes = _parse_duration(data.get('duration_minutes'))
    client_id = data.get('client_id')

    if not title or not start_datetime or not client_id:
        return JsonResponse({'error': 'Campi obbligatori mancanti.'}, status=400)

    if duration_minutes is None:
        return JsonResponse(
            {'error': "Indica una durata valida (almeno 1 minuto)."},
            status=400,
        )

    try:
        client = ClientProfile.objects.get(id=client_id, coaching_relationships_as_client__coach=coach)
    except ClientProfile.DoesNotExist:
        return JsonResponse({'error': 'Atleta non trovato.'}, status=400)

    evt.client = client
    evt.title = title
    evt.appointment_type = appointment_type
    evt.start_datetime = start_datetime
    evt.duration_minutes = duration_minutes
    evt.description = data.get('description', '') or ''
    evt.meeting_url = data.get('meeting_url', '') if appointment_type == 'consulenza' else ''
    evt.save()

    return JsonResponse({'status': 'success', 'event_id': evt.id})


# ---------------------------------------------------------------------------
# Calendar feed (Google Calendar / Apple Calendar subscription)
# ---------------------------------------------------------------------------
import secrets as _secrets
from django.http import HttpResponse
from django.shortcuts import get_object_or_404 as _get_or_404
from domain.accounts.models import CoachProfile as _CoachProfile
from domain.accounts.models import ClientProfile as _ClientProfile
from domain.calendar.models import Appointment as _Appointment


def _ensure_coach_feed_token(coach):
    if not coach.calendar_feed_token:
        coach.calendar_feed_token = _secrets.token_urlsafe(24)
        coach.save(update_fields=['calendar_feed_token', 'updated_at'])
    return coach.calendar_feed_token


def _ensure_client_feed_token(client):
    if not client.calendar_feed_token:
        client.calendar_feed_token = _secrets.token_urlsafe(24)
        client.save(update_fields=['calendar_feed_token', 'updated_at'])
    return client.calendar_feed_token


def coach_calendar_feed_urls(coach):
    """Return (https_url, webcal_url, google_subscribe_url) for a coach's feed.

    Built from settings.SITE_URL (the deterministic public origin) rather than the
    request Host, which is unreliable behind the Railway proxy. Google's `cid` must
    be URL-encoded or Calendar refuses to add the subscription.
    """
    from django.conf import settings
    from django.urls import reverse
    import urllib.parse
    token = _ensure_coach_feed_token(coach)
    feed_path = reverse('coach_calendar_feed', args=[token])
    abs_url = settings.SITE_URL.rstrip('/') + feed_path
    webcal_url = abs_url.replace('https://', 'webcal://').replace('http://', 'webcal://')
    google_subscribe = 'https://calendar.google.com/calendar/r?cid=' + urllib.parse.quote(abs_url, safe='')
    return abs_url, webcal_url, google_subscribe


def client_calendar_feed_urls(client):
    """Same as coach_calendar_feed_urls, for the athlete's own feed."""
    from django.conf import settings
    from django.urls import reverse
    import urllib.parse
    token = _ensure_client_feed_token(client)
    feed_path = reverse('client_calendar_feed', args=[token])
    abs_url = settings.SITE_URL.rstrip('/') + feed_path
    webcal_url = abs_url.replace('https://', 'webcal://').replace('http://', 'webcal://')
    google_subscribe = 'https://calendar.google.com/calendar/r?cid=' + urllib.parse.quote(abs_url, safe='')
    return abs_url, webcal_url, google_subscribe


def _ics_escape(text):
    if text is None:
        return ''
    return (
        str(text)
        .replace('\\', '\\\\')
        .replace(',', '\\,')
        .replace(';', '\\;')
        .replace('\n', '\\n')
    )


def _fmt_ics_dt(dt):
    if dt is None:
        return ''
    # Naive → assume UTC; tz-aware → convert to UTC and format as Zulu time.
    if dt.tzinfo:
        dt = dt.astimezone(datetime.timezone.utc)
    else:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt.strftime('%Y%m%dT%H%M%SZ')


def _build_ics_feed(calendar_label, appts, other_party_name):
    """Shared VCALENDAR/VEVENT builder for both the coach and client feeds.
    `other_party_name(appt)` returns the counterpart's display name to append
    to the summary/description (client name for the coach feed, coach name
    for the client feed)."""
    lines = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Athlynk//Agenda//IT',
        'CALSCALE:GREGORIAN',
        'METHOD:PUBLISH',
        f'X-WR-CALNAME:Athlynk · {_ics_escape(calendar_label)}',
        'X-WR-TIMEZONE:UTC',
        'REFRESH-INTERVAL;VALUE=DURATION:PT30M',
    ]
    now = _fmt_ics_dt(datetime.datetime.now(datetime.timezone.utc))
    for a in appts:
        uid = f'athlynk-appt-{a.id}@athlynk'
        summary = a.title or 'Appuntamento'
        other_name = other_party_name(a)
        if other_name:
            summary = f'{summary} — {other_name}'
        description_parts = []
        if a.description:
            description_parts.append(a.description)
        if a.meeting_url:
            description_parts.append(f'Link: {a.meeting_url}')
        if other_name:
            description_parts.append(other_name)
        description = '\n'.join(description_parts)
        lines += [
            'BEGIN:VEVENT',
            f'UID:{uid}',
            f'DTSTAMP:{now}',
            f'DTSTART:{_fmt_ics_dt(a.start_datetime)}',
            f'DTEND:{_fmt_ics_dt(a.end_datetime)}',
            f'SUMMARY:{_ics_escape(summary)}',
            f'DESCRIPTION:{_ics_escape(description)}',
        ]
        if a.location:
            lines.append(f'LOCATION:{_ics_escape(a.location)}')
        if a.meeting_url:
            lines.append(f'URL:{_ics_escape(a.meeting_url)}')
        lines.append(f'STATUS:{ "CONFIRMED" if a.status == "SCHEDULED" else "TENTATIVE" }')
        lines.append('END:VEVENT')
    lines.append('END:VCALENDAR')

    body = '\r\n'.join(lines) + '\r\n'
    resp = HttpResponse(body, content_type='text/calendar; charset=utf-8')
    resp['Content-Disposition'] = 'inline; filename="athlynk-agenda.ics"'
    return resp


def coach_calendar_feed(request, token):
    """Public ICS feed for a coach's appointments. Token-protected URL so it can
    be subscribed in Google Calendar / Apple Calendar without login."""
    coach = _get_or_404(_CoachProfile, calendar_feed_token=token)
    appts = _Appointment.objects.filter(coach=coach).exclude(status='CANCELLED').select_related('client').order_by('start_datetime')

    def client_name(a):
        if not a.client_id:
            return ''
        try:
            return f"{a.client.first_name} {a.client.last_name}".strip()
        except Exception:
            return ''

    label = f"{coach.first_name or ''} {coach.last_name or ''}".strip()
    return _build_ics_feed(label, appts, client_name)


def client_calendar_feed(request, token):
    """Public ICS feed for an athlete's own appointments (across all their
    coaches). Same token-protected scheme as the coach feed."""
    client = _get_or_404(_ClientProfile, calendar_feed_token=token)
    appts = _Appointment.objects.filter(client=client).exclude(status='CANCELLED').select_related('coach').order_by('start_datetime')

    def coach_name(a):
        if not a.coach_id:
            return ''
        try:
            return f"{a.coach.first_name} {a.coach.last_name}".strip()
        except Exception:
            return ''

    label = f"{client.first_name or ''} {client.last_name or ''}".strip()
    return _build_ics_feed(label, appts, coach_name)


def api_coach_calendar_token(request):
    """Return (or create) the calendar feed token for the logged-in coach."""
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'forbidden'}, status=403)
    if request.method == 'POST':
        # Rotate token (invalidates existing subscriptions).
        coach.calendar_feed_token = _secrets.token_urlsafe(24)
        coach.save(update_fields=['calendar_feed_token', 'updated_at'])
    else:
        _ensure_coach_feed_token(coach)
    return JsonResponse({'token': coach.calendar_feed_token})
