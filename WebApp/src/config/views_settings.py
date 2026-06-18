from django.shortcuts import render, redirect
from django.contrib.auth.hashers import check_password
from django.views.decorators.http import require_POST
from django.db import transaction

from .session_utils import get_session_user, get_session_coach, get_session_client
from .services.images import to_webp, is_image
from domain.chat.services import DEFAULT_PLAN_DELETED_BODY


def _newsletter_status(email):
    try:
        from domain.newsletter.models import Subscriber
        sub = Subscriber.objects.filter(email=email).first()
        return sub.status if sub else 'NONE'
    except Exception:
        return 'NONE'


def impostazioni_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    error = None
    active_tab = 'profilo'

    if user.role == 'CLIENT':
        client = get_session_client(request)
        if not client:
            return redirect('login')

        if request.method == 'POST':
            action = request.POST.get('action')

            if action == 'profilo':
                client.first_name = request.POST.get('first_name', '').strip() or client.first_name
                client.last_name = request.POST.get('last_name', '').strip() or client.last_name
                client.phone = request.POST.get('phone', '').strip() or None
                birth = request.POST.get('birth_date', '').strip()
                client.birth_date = birth if birth else client.birth_date
                client.gender = request.POST.get('gender', '').strip() or None
                height = request.POST.get('height_cm', '').strip()
                client.height_cm = int(height) if height.isdigit() else client.height_cm
                client.primary_goal = request.POST.get('primary_goal', '').strip() or None
                if 'profile_image' in request.FILES:
                    raw = request.FILES['profile_image']
                    if is_image(raw):
                        client.profile_image = to_webp(raw)
                client.save()
                return redirect(f"{request.path}?saved=profilo")

            if action == 'nutrizione':
                mode = request.POST.get('food_search_mode', 'alimento')
                if mode not in ('alimento', 'media'):
                    mode = 'alimento'
                prefs = dict(user.email_prefs or {})
                prefs['food_search_mode'] = mode
                user.email_prefs = prefs
                user.save(update_fields=['email_prefs', 'updated_at'])
                return redirect(f"{request.path}?saved=nutrizione")

        saved = request.GET.get('saved')
        if saved and not error:
            active_tab = saved

        reset_request_sent = request.session.pop('reset_request_sent', False)
        if reset_request_sent:
            active_tab = 'sicurezza'

        return render(request, 'pages/impostazioni/dashboard.html', {
            'client': client,
            'auth_user': user,
            'is_client': True,
            'active_tab': active_tab,
            'error': error,
            'saved': saved,
            'newsletter_status': _newsletter_status(user.email),
            'reset_request_sent': reset_request_sent,
            'food_search_mode': (user.email_prefs or {}).get('food_search_mode', 'alimento'),
        })

    # COACH
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    if request.method == 'POST':
        action = request.POST.get('action')

        if action == 'profilo':
            coach.first_name = request.POST.get('first_name', '').strip() or coach.first_name
            coach.last_name = request.POST.get('last_name', '').strip() or coach.last_name
            coach.phone = request.POST.get('phone', '').strip() or None
            coach.city = request.POST.get('city', '').strip() or None
            coach.bio = request.POST.get('bio', '').strip() or None
            coach.specialization = request.POST.get('specialization', '').strip() or None
            coach.certifications = request.POST.get('certifications', '').strip() or None
            years = request.POST.get('years_experience', '').strip()
            coach.years_experience = int(years) if years.isdigit() else None
            if 'profile_image' in request.FILES:
                raw = request.FILES['profile_image']
                if is_image(raw):
                    coach.profile_image = to_webp(raw)
            coach.social_instagram = request.POST.get('social_instagram', '').strip() or None
            coach.social_youtube = request.POST.get('social_youtube', '').strip() or None
            coach.social_tiktok = request.POST.get('social_tiktok', '').strip() or None
            coach.social_facebook = request.POST.get('social_facebook', '').strip() or None
            coach.social_website = request.POST.get('social_website', '').strip() or None
            videos_raw = request.POST.get('professional_videos', '').strip()
            coach.professional_videos = videos_raw or None
            coach.save()
            return redirect(f"{request.path}?saved=profilo")

        if action == 'nutrizione':
            mode = request.POST.get('food_search_mode', 'alimento')
            if mode not in ('alimento', 'media'):
                mode = 'alimento'
            prefs = dict(user.email_prefs or {})
            prefs['food_search_mode'] = mode
            user.email_prefs = prefs
            user.save(update_fields=['email_prefs', 'updated_at'])
            return redirect(f"{request.path}?saved=nutrizione")

    saved = request.GET.get('saved')
    if saved and not error:
        active_tab = saved
    tab = request.GET.get('tab')
    if tab:
        active_tab = tab

    reset_request_sent = request.session.pop('reset_request_sent', False)
    if reset_request_sent:
        active_tab = 'sicurezza'

    return render(request, 'pages/impostazioni/dashboard.html', {
        'coach': coach,
        'auth_user': user,
        'is_coach': True,
        'active_tab': active_tab,
        'error': error,
        'saved': saved,
        'newsletter_status': _newsletter_status(user.email),
        'reset_request_sent': reset_request_sent,
        'food_search_mode': (user.email_prefs or {}).get('food_search_mode', 'alimento'),
        'auto_msg_rows': _auto_msg_rows(coach),
    })


def my_profile_view(request):
    """Self-view: show coach/client their own profile in public-style layout."""
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'COACH':
        coach = get_session_coach(request)
        if not coach:
            return redirect('login')
        return render(request, 'pages/profilo/me_coach.html', {
            'coach': coach,
            'coach_name': f'{coach.first_name} {coach.last_name}'.strip(),
            'auth_user': user,
            'is_self': True,
        })

    client = get_session_client(request)
    if not client:
        return redirect('login')
    return render(request, 'pages/profilo/me_client.html', {
        'client': client,
        'auth_user': user,
        'is_self': True,
    })


@require_POST
def delete_account_view(request):
    """Hard delete the currently logged-in user account.

    Requires the current password as confirmation. Cascades to profile and
    all related domain rows via Django FK CASCADE. Flushes the session.
    """
    user = get_session_user(request)
    if not user:
        return redirect('login')

    password = request.POST.get('confirm_password', '')
    confirm_text = request.POST.get('confirm_text', '').strip().upper()

    error = None
    if not check_password(password, user.password_hash):
        error = 'Password non corretta.'
    elif confirm_text != 'ELIMINA':
        error = 'Digita ELIMINA per confermare.'

    if error:
        active_tab = 'elimina'
        ctx = {
            'auth_user': user,
            'active_tab': active_tab,
            'error': error,
            'newsletter_status': _newsletter_status(user.email),
        }
        if user.role == 'COACH':
            ctx['coach'] = get_session_coach(request)
            ctx['is_coach'] = True
        else:
            ctx['client'] = get_session_client(request)
            ctx['is_client'] = True
        return render(request, 'pages/impostazioni/dashboard.html', ctx)

    from domain.accounts.services import hard_delete_user
    hard_delete_user(user)

    request.session.flush()
    return redirect('login')



_EMAIL_NOTIF_KEYS = [
    ('workout_assigned',    'Nuovo piano di allenamento', 'Ricevi una mail quando il tuo coach ti assegna una nuova scheda.'),
    ('nutrition_assigned',  'Nuovo piano nutrizionale',   'Ricevi una mail quando ti viene assegnato un piano alimentare.'),
]


def notifications_view(request):
    """Per-user email notification preferences (opt-out per category)."""
    user = get_session_user(request)
    if not user:
        return redirect('login')

    saved = False
    if request.method == 'POST':
        prefs = dict(user.email_prefs or {})
        for key, _label, _desc in _EMAIL_NOTIF_KEYS:
            prefs[key] = (request.POST.get(f'pref_{key}') == 'on')
        user.email_prefs = prefs
        user.save(update_fields=['email_prefs', 'updated_at'])
        saved = True

    rows = [
        {
            'key': key,
            'label': label,
            'desc': desc,
            'enabled': (user.email_prefs or {}).get(key, True),
        }
        for key, label, desc in _EMAIL_NOTIF_KEYS
    ]
    ctx = {
        'auth_user': user,
        'notif_rows': rows,
        'saved': saved,
        'active_tab': 'notifiche',
    }
    if user.role == 'COACH':
        ctx['coach'] = get_session_coach(request)
        ctx['is_coach'] = True
    else:
        ctx['client'] = get_session_client(request)
        ctx['is_client'] = True
    return render(request, 'pages/impostazioni/notifications.html', ctx)


_AUTO_MSG_EVENTS = [
    ('WELCOME', '01', 'Benvenuto', 'Inviato automaticamente quando aggiungi un nuovo atleta.',
     'Ciao {nome}, benvenuto/a! 🎉 Sono felice di iniziare questo percorso insieme.'),
    ('GOODBYE', '02', 'Arrivederci', 'Inviato quando un atleta interrompe il percorso con te.',
     'Grazie di tutto {nome} 🙏 È stato un piacere allenarti. Le porte restano sempre aperte!'),
    ('SUBSCRIPTION_EXPIRING', '03', 'Abbonamento in scadenza',
     'Inviato qualche giorno prima della scadenza dell’abbonamento.',
     'Ciao {nome}, il tuo abbonamento sta per scadere ⏳ Rinnova per non perdere i progressi!'),
    ('PLAN_DELETED', '04', 'Scheda eliminata',
     'Inviato quando elimini una scheda o un piano assegnato a un atleta. Attivo di default: '
     'se non scrivi nulla viene inviato il testo predefinito.',
     DEFAULT_PLAN_DELETED_BODY),
]

_AUTO_MSG_BODY_MAX = 2000


def _auto_msg_rows(coach):
    """Rows for the automatic-messages panel, one per configurable event."""
    from domain.chat.models import AutomaticMessageTemplate
    templates = {t.event_type: t for t in AutomaticMessageTemplate.objects.filter(coach=coach)}
    rows = []
    for event_type, num, label, desc, placeholder in _AUTO_MSG_EVENTS:
        tpl = templates.get(event_type)
        rows.append({
            'event_type': event_type,
            'num': num,
            'label': label,
            'desc': desc,
            'placeholder': placeholder,
            'body': tpl.body if tpl else '',
            # PLAN_DELETED è opt-out: senza riga salvata parte il default.
            'is_enabled': tpl.is_enabled if tpl else (event_type == 'PLAN_DELETED'),
            'attachment_url': tpl.attachment.url if (tpl and tpl.attachment) else '',
        })
    return rows


def automatic_messages_view(request):
    """Coach-only: save the per-event automatic chat messages sent to athletes.

    The form lives inside the settings dashboard (tab «Messaggi automatici»);
    this endpoint handles the POST and redirects back to that tab.
    """
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('impostazioni_dashboard')

    from django.urls import reverse
    from domain.chat.models import AutomaticMessageTemplate

    dashboard_url = reverse('impostazioni_dashboard')
    if request.method != 'POST':
        return redirect(f"{dashboard_url}?tab=messaggi_auto")

    error = None
    for event_type, *_rest in _AUTO_MSG_EVENTS:
        tpl, _created = AutomaticMessageTemplate.objects.get_or_create(coach=coach, event_type=event_type)
        tpl.body = (request.POST.get(f'body_{event_type}', '') or '')[:_AUTO_MSG_BODY_MAX]
        tpl.is_enabled = request.POST.get(f'enabled_{event_type}') == 'on'
        if request.POST.get(f'remove_attachment_{event_type}') == '1':
            tpl.attachment = None
        elif f'attachment_{event_type}' in request.FILES:
            raw = request.FILES[f'attachment_{event_type}']
            if is_image(raw):
                tpl.attachment = to_webp(raw)
            else:
                error = 'Il file allegato deve essere un’immagine valida.'
        tpl.save()

    if error:
        return render(request, 'pages/impostazioni/dashboard.html', {
            'coach': coach,
            'auth_user': user,
            'is_coach': True,
            'active_tab': 'messaggi_auto',
            'error': error,
            'newsletter_status': _newsletter_status(user.email),
            'food_search_mode': (user.email_prefs or {}).get('food_search_mode', 'alimento'),
            'auto_msg_rows': _auto_msg_rows(coach),
        })
    return redirect(f"{dashboard_url}?saved=messaggi_auto")


def calendar_view(request):
    """Coach calendar subscription page — Google Calendar / Apple Calendar."""
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('impostazioni_dashboard')

    if request.method == 'POST' and request.POST.get('action') == 'rotate':
        import secrets as _secrets
        coach.calendar_feed_token = _secrets.token_urlsafe(24)
        coach.save(update_fields=['calendar_feed_token', 'updated_at'])

    if not coach.calendar_feed_token:
        import secrets as _secrets
        coach.calendar_feed_token = _secrets.token_urlsafe(24)
        coach.save(update_fields=['calendar_feed_token', 'updated_at'])

    from django.urls import reverse
    feed_path = reverse('coach_calendar_feed', args=[coach.calendar_feed_token])
    abs_url = request.build_absolute_uri(feed_path)
    webcal_url = abs_url.replace('https://', 'webcal://').replace('http://', 'webcal://')
    google_subscribe = 'https://calendar.google.com/calendar/r?cid=' + abs_url

    ctx = {
        'auth_user': user,
        'coach': coach,
        'is_coach': True,
        'feed_url': abs_url,
        'webcal_url': webcal_url,
        'google_subscribe': google_subscribe,
        'active_tab': 'calendario',
    }
    return render(request, 'pages/impostazioni/calendar.html', ctx)
