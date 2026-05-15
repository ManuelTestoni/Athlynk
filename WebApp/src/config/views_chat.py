from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from django.utils import timezone
from django.db.models import Q, Max, Count
import json

from domain.chat.models import Conversation, Message, Notification
from domain.accounts.models import CoachProfile, ClientProfile, User
from domain.coaching.models import CoachingRelationship
from domain.calendar.models import Appointment

from .session_utils import get_session_user, get_session_coach, get_session_client


def _get_or_create_conversation(coach, client):
    """Get or create a conversation between coach and client."""
    conv, _ = Conversation.objects.get_or_create(coach=coach, client=client)
    return conv


def _user_has_access_to_conversation(user, conversation):
    """Check if user can access this conversation (must be either coach or client side)."""
    if user.role == 'COACH':
        coach = CoachProfile.objects.filter(user=user).first()
        return coach and conversation.coach_id == coach.id
    elif user.role == 'CLIENT':
        client = ClientProfile.objects.filter(user=user).first()
        return client and conversation.client_id == client.id
    return False


def _recipient_user_for_message(conversation, sender_user):
    """Return the User who should receive a notification for a message in this conversation."""
    if sender_user.role == 'COACH':
        return conversation.client.user
    return conversation.coach.user


def chat_list_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'COACH':
        coach = get_session_coach(request)
        if not coach:
            return redirect('login')

        # Auto-create conversations for all active clients (so coach can initiate)
        active_rels = CoachingRelationship.objects.filter(coach=coach, status='ACTIVE').select_related('client')
        for rel in active_rels:
            Conversation.objects.get_or_create(coach=coach, client=rel.client)

        conversations = (
            Conversation.objects.filter(coach=coach)
            .select_related('client', 'client__user')
            .order_by('-last_message_at', '-created_at')
        )

        partners = []
        for conv in conversations:
            last_msg = conv.messages.order_by('-sent_at').first()
            unread = conv.messages.filter(read_at__isnull=True).exclude(sender_user=user).count()
            partners.append({
                'conversation': conv,
                'partner_name': f"{conv.client.first_name} {conv.client.last_name}".strip(),
                'partner_avatar': '',
                'last_message': last_msg,
                'unread_count': unread,
            })

        return render(request, 'pages/chat/list.html', {
            'partners': partners,
            'is_coach': True,
        })

    if user.role == 'CLIENT':
        client = get_session_client(request)
        if not client:
            return redirect('login')

        # Auto-create conversations for all active coach relationships
        active_rels = CoachingRelationship.objects.filter(client=client, status='ACTIVE').select_related('coach')
        for rel in active_rels:
            Conversation.objects.get_or_create(coach=rel.coach, client=client)

        conversations = (
            Conversation.objects.filter(client=client)
            .select_related('coach', 'coach__user')
            .order_by('-last_message_at', '-created_at')
        )

        partners = []
        for conv in conversations:
            last_msg = conv.messages.order_by('-sent_at').first()
            unread = conv.messages.filter(read_at__isnull=True).exclude(sender_user=user).count()
            partners.append({
                'conversation': conv,
                'partner_name': f"{conv.coach.first_name} {conv.coach.last_name}".strip(),
                'partner_avatar': conv.coach.profile_image_url or '',
                'partner_role': conv.coach.professional_type,
                'last_message': last_msg,
                'unread_count': unread,
            })

        return render(request, 'pages/chat/list.html', {
            'partners': partners,
            'is_client': True,
        })

    return redirect('dashboard')


def chat_detail_view(request, conversation_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    conversation = get_object_or_404(Conversation, id=conversation_id)
    if not _user_has_access_to_conversation(user, conversation):
        return redirect('chat_list')

    PAGE_SIZE = 20
    total_messages = conversation.messages.count()
    messages = conversation.messages.select_related('sender_user', 'appointment').order_by('-sent_at')[:PAGE_SIZE]
    messages = list(reversed(messages))
    has_older = total_messages > PAGE_SIZE
    oldest_id = messages[0].id if messages else 0

    # Mark unread messages as read
    now = timezone.now()
    conversation.messages.filter(read_at__isnull=True).exclude(sender_user=user).update(read_at=now)
    # Mark related notifications as read
    Notification.objects.filter(
        target_user=user,
        notification_type__in=['MESSAGE', 'APPOINTMENT_REQUEST', 'APPOINTMENT_ACCEPTED', 'APPOINTMENT_REJECTED'],
        link_url__contains=f'/chat/{conversation.id}/',
        is_read=False,
    ).update(is_read=True)

    if user.role == 'COACH':
        partner_name = f"{conversation.client.first_name} {conversation.client.last_name}".strip()
        partner_avatar = ''
        partner_role = 'CLIENT'
    else:
        partner_name = f"{conversation.coach.first_name} {conversation.coach.last_name}".strip()
        partner_avatar = conversation.coach.profile_image_url or ''
        partner_role = conversation.coach.professional_type

    return render(request, 'pages/chat/detail.html', {
        'conversation': conversation,
        'chat_messages': messages,
        'partner_name': partner_name,
        'partner_avatar': partner_avatar,
        'partner_role': partner_role,
        'current_user_id': user.id,
        'has_older': has_older,
        'oldest_id': oldest_id,
    })


@require_http_methods(["POST"])
def api_send_message(request, conversation_id):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    conversation = get_object_or_404(Conversation, id=conversation_id)
    if not _user_has_access_to_conversation(user, conversation):
        return JsonResponse({'error': 'Forbidden'}, status=403)

    body = request.POST.get('body', '').strip()
    attachment = request.FILES.get('attachment')

    if not body and not attachment:
        return JsonResponse({'error': 'Message empty'}, status=400)

    msg_type = 'TEXT'
    if attachment:
        ct = (attachment.content_type or '').lower()
        if ct.startswith('image/'):
            msg_type = 'IMAGE'
        elif ct.startswith('video/'):
            msg_type = 'VIDEO'
        else:
            return JsonResponse({'error': 'Tipo file non supportato. Solo immagini o video.'}, status=400)

    msg = Message.objects.create(
        conversation=conversation,
        sender_user=user,
        body=body,
        message_type=msg_type,
        attachment=attachment,
    )

    conversation.last_message_at = msg.sent_at
    conversation.save(update_fields=['last_message_at', 'updated_at'])

    # Notify recipient
    recipient = _recipient_user_for_message(conversation, user)
    sender_name = ''
    if user.role == 'COACH':
        cp = CoachProfile.objects.filter(user=user).first()
        if cp:
            sender_name = f"{cp.first_name} {cp.last_name}".strip()
    else:
        cp = ClientProfile.objects.filter(user=user).first()
        if cp:
            sender_name = f"{cp.first_name} {cp.last_name}".strip()

    Notification.objects.create(
        target_user=recipient,
        notification_type='MESSAGE',
        title=f'Nuovo messaggio da {sender_name or user.email}',
        body=(body[:120] + '…') if len(body) > 120 else body,
        link_url=f'/chat/{conversation.id}/',
    )

    return JsonResponse({
        'id': msg.id,
        'body': msg.body,
        'message_type': msg.message_type,
        'attachment_url': msg.attachment.url if msg.attachment else None,
        'sent_at': msg.sent_at.isoformat(),
        'sender_user_id': user.id,
    })


@require_http_methods(["POST"])
def api_mark_read(request, conversation_id):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    conversation = get_object_or_404(Conversation, id=conversation_id)
    if not _user_has_access_to_conversation(user, conversation):
        return JsonResponse({'error': 'Forbidden'}, status=403)

    now = timezone.now()
    conversation.messages.filter(read_at__isnull=True).exclude(sender_user=user).update(read_at=now)
    return JsonResponse({'status': 'ok'})


@require_http_methods(["POST"])
def api_appointment_request(request, conversation_id):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    conversation = get_object_or_404(Conversation, id=conversation_id)
    if not _user_has_access_to_conversation(user, conversation):
        return JsonResponse({'error': 'Forbidden'}, status=403)

    try:
        data = json.loads(request.body)
    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON'}, status=400)

    from datetime import date as date_type, time as time_type, datetime, timedelta
    from django.utils.timezone import make_aware

    title = (data.get('title') or 'Appuntamento').strip()
    preferred_date_str = data.get('preferred_date', '').strip()
    time_from_str = data.get('time_from', '').strip()
    time_to_str = data.get('time_to', '').strip()
    notes = (data.get('notes') or '').strip()

    if not preferred_date_str or not time_from_str or not time_to_str:
        return JsonResponse({'error': 'Giorno e fascia oraria sono obbligatori'}, status=400)

    try:
        preferred_date = date_type.fromisoformat(preferred_date_str)
        h_from, m_from = map(int, time_from_str.split(':'))
        h_to, m_to = map(int, time_to_str.split(':'))
        start_dt = make_aware(datetime(preferred_date.year, preferred_date.month, preferred_date.day, h_from, m_from))
        end_dt = make_aware(datetime(preferred_date.year, preferred_date.month, preferred_date.day, h_to, m_to))
    except (ValueError, TypeError):
        return JsonResponse({'error': 'Formato data/orario non valido'}, status=400)

    if end_dt <= start_dt:
        return JsonResponse({'error': "L'orario di fine deve essere successivo all'inizio"}, status=400)
    if (end_dt - start_dt) > timedelta(hours=10):
        return JsonResponse({'error': 'La fascia oraria non può superare le 10 ore'}, status=400)

    appointment = Appointment.objects.create(
        coach=conversation.coach,
        client=conversation.client,
        appointment_type='consultation',
        title=title,
        description=notes or None,
        start_datetime=start_dt,
        end_datetime=end_dt,
        status='PENDING',
    )

    body_msg = f'Richiesta appuntamento: {title} il {preferred_date.strftime("%d/%m/%Y")} dalle {time_from_str} alle {time_to_str}'

    msg = Message.objects.create(
        conversation=conversation,
        sender_user=user,
        body=body_msg,
        message_type='APPOINTMENT_REQUEST',
        appointment=appointment,
    )
    conversation.last_message_at = msg.sent_at
    conversation.save(update_fields=['last_message_at', 'updated_at'])

    recipient = _recipient_user_for_message(conversation, user)
    Notification.objects.create(
        target_user=recipient,
        notification_type='APPOINTMENT_REQUEST',
        title='Nuova richiesta di appuntamento',
        body=body_msg,
        link_url=f'/chat/{conversation.id}/',
    )

    return JsonResponse({
        'id': msg.id,
        'message_type': msg.message_type,
        'appointment_id': appointment.id,
        'appointment_status': appointment.status,
        'body': msg.body,
        'sent_at': msg.sent_at.isoformat(),
        'sender_user_id': user.id,
    })


@require_http_methods(["POST"])
def api_appointment_respond(request, conversation_id, appointment_id):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    conversation = get_object_or_404(Conversation, id=conversation_id)
    if not _user_has_access_to_conversation(user, conversation):
        return JsonResponse({'error': 'Forbidden'}, status=403)

    appointment = get_object_or_404(Appointment, id=appointment_id, coach=conversation.coach, client=conversation.client)
    if appointment.status != 'PENDING':
        return JsonResponse({'error': 'Appointment già processato'}, status=400)

    try:
        data = json.loads(request.body)
    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON'}, status=400)

    action = (data.get('action') or '').lower()
    if action not in ('accept', 'reject'):
        return JsonResponse({'error': 'Azione non valida'}, status=400)

    from datetime import date as date_type, datetime, timedelta
    from django.utils.timezone import make_aware

    if action == 'accept':
        confirmed_date_str = data.get('confirmed_date', '').strip()
        confirmed_time_str = data.get('confirmed_time', '').strip()
        if not confirmed_date_str or not confirmed_time_str:
            return JsonResponse({'error': 'Data e orario confermati sono obbligatori'}, status=400)
        try:
            cd = date_type.fromisoformat(confirmed_date_str)
            h, m = map(int, confirmed_time_str.split(':'))
            start_dt = make_aware(datetime(cd.year, cd.month, cd.day, h, m))
            end_dt = start_dt + timedelta(hours=1)
        except (ValueError, TypeError):
            return JsonResponse({'error': 'Formato data/orario non valido'}, status=400)
        appointment.start_datetime = start_dt
        appointment.end_datetime = end_dt
        appointment.status = 'SCHEDULED'
        appointment.save(update_fields=['start_datetime', 'end_datetime', 'status', 'updated_at'])
        body_msg = f'Appuntamento confermato: {appointment.title} il {start_dt.strftime("%d/%m/%Y")} alle {start_dt.strftime("%H:%M")}'
        notif_type = 'APPOINTMENT_ACCEPTED'
        notif_title = 'Appuntamento confermato'
    else:
        appointment.status = 'CANCELLED'
        appointment.cancellation_reason = 'Richiesta rifiutata'
        appointment.save(update_fields=['status', 'cancellation_reason', 'updated_at'])
        body_msg = f'Appuntamento rifiutato: {appointment.title}'
        notif_type = 'APPOINTMENT_REJECTED'
        notif_title = 'Appuntamento rifiutato'

        # Optional counter-proposal: create a new pending appointment + message
        counter_date_str = data.get('counter_date', '').strip()
        counter_time_str = data.get('counter_time', '').strip()
        if counter_date_str and counter_time_str:
            try:
                cd = date_type.fromisoformat(counter_date_str)
                h, m = map(int, counter_time_str.split(':'))
                counter_start = make_aware(datetime(cd.year, cd.month, cd.day, h, m))
                counter_end = counter_start + timedelta(hours=1)
                counter_appt = Appointment.objects.create(
                    coach=conversation.coach,
                    client=conversation.client,
                    appointment_type='consultation',
                    title=appointment.title,
                    start_datetime=counter_start,
                    end_datetime=counter_end,
                    status='PENDING',
                )
                counter_msg = Message.objects.create(
                    conversation=conversation,
                    sender_user=user,
                    body=f'Controproposta: {appointment.title} il {cd.strftime("%d/%m/%Y")} alle {counter_time_str}',
                    message_type='APPOINTMENT_REQUEST',
                    appointment=counter_appt,
                )
                conversation.last_message_at = counter_msg.sent_at
                conversation.save(update_fields=['last_message_at', 'updated_at'])
            except (ValueError, TypeError):
                pass

    msg = Message.objects.create(
        conversation=conversation,
        sender_user=user,
        body=body_msg,
        message_type='APPOINTMENT_RESPONSE',
        appointment=appointment,
    )
    conversation.last_message_at = msg.sent_at
    conversation.save(update_fields=['last_message_at', 'updated_at'])

    recipient = _recipient_user_for_message(conversation, user)
    Notification.objects.create(
        target_user=recipient,
        notification_type=notif_type,
        title=notif_title,
        body=body_msg,
        link_url=f'/chat/{conversation.id}/',
    )

    return JsonResponse({
        'id': msg.id,
        'appointment_status': appointment.status,
        'body': msg.body,
        'sent_at': msg.sent_at.isoformat(),
    })


def api_messages_before(request, conversation_id):
    """Pagination endpoint — returns up to 20 messages older than ?before=<message_id>."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    conversation = get_object_or_404(Conversation, id=conversation_id)
    if not _user_has_access_to_conversation(user, conversation):
        return JsonResponse({'error': 'Forbidden'}, status=403)

    before_id = request.GET.get('before', '0')
    try:
        before_id = int(before_id)
    except ValueError:
        return JsonResponse({'error': 'Invalid before'}, status=400)

    PAGE_SIZE = 20
    qs = conversation.messages.filter(id__lt=before_id).select_related('sender_user', 'appointment').order_by('-sent_at')[:PAGE_SIZE]
    msgs = list(reversed(qs))
    has_more = conversation.messages.filter(id__lt=before_id).count() > PAGE_SIZE

    return JsonResponse({
        'messages': [_serialize_message(m) for m in msgs],
        'has_more': has_more,
    })


def _serialize_message(m):
    return {
        'id': m.id,
        'body': m.body,
        'message_type': m.message_type,
        'attachment_url': m.attachment.url if m.attachment else None,
        'sent_at': m.sent_at.isoformat(),
        'sender_user_id': m.sender_user_id,
        'appointment_id': m.appointment_id,
        'appointment_status': m.appointment.status if m.appointment else None,
        'appointment_title': m.appointment.title if m.appointment else None,
        'read_at': m.read_at.isoformat() if m.read_at else None,
    }


def api_messages_since(request, conversation_id):
    """Polling endpoint — returns messages newer than ?after=<message_id>."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    conversation = get_object_or_404(Conversation, id=conversation_id)
    if not _user_has_access_to_conversation(user, conversation):
        return JsonResponse({'error': 'Forbidden'}, status=403)

    after_id = request.GET.get('after', '0')
    try:
        after_id = int(after_id)
    except ValueError:
        after_id = 0

    qs = conversation.messages.filter(id__gt=after_id).select_related('sender_user', 'appointment').order_by('sent_at')

    messages = [_serialize_message(m) for m in qs]

    # Mark as read and collect which sent messages just got read
    now = timezone.now()
    just_read_qs = conversation.messages.filter(read_at__isnull=True).exclude(sender_user=user)
    just_read_ids = list(just_read_qs.values_list('id', flat=True))
    just_read_qs.update(read_at=now)

    # Tell the sender which of their messages are now read
    read_updates = [{'id': mid, 'read_at': now.isoformat()} for mid in just_read_ids]

    return JsonResponse({'messages': messages, 'read_updates': read_updates})
