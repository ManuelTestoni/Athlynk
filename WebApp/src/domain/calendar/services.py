from datetime import date as date_type, datetime, timedelta

from django.utils import timezone
from django.utils.timezone import make_aware

from domain.chat.models import Message, Notification

from .models import Appointment


def appointment_expired(appointment, now=None):
    """A PENDING request whose requested moment has already passed, unanswered."""
    now = now or timezone.now()
    return bool(appointment) and appointment.status == 'PENDING' and appointment.start_datetime < now


def _recipient_user_for_message(conversation, sender_user):
    if sender_user.role == 'COACH':
        return conversation.client.user
    return conversation.coach.user


def create_appointment_request(user, conversation, title, preferred_date_str, time_from_str, time_to_str, notes):
    """Validates input, creates a PENDING Appointment + APPOINTMENT_REQUEST Message + notification.

    Raises ValueError(message) on invalid input. Returns the created Message.
    """
    title = (title or 'Appuntamento').strip()
    preferred_date_str = (preferred_date_str or '').strip()
    time_from_str = (time_from_str or '').strip()
    time_to_str = (time_to_str or '').strip()
    notes = (notes or '').strip()

    if not preferred_date_str or not time_from_str or not time_to_str:
        raise ValueError('Giorno e fascia oraria sono obbligatori')

    try:
        preferred_date = date_type.fromisoformat(preferred_date_str)
        h_from, m_from = map(int, time_from_str.split(':'))
        h_to, m_to = map(int, time_to_str.split(':'))
        start_dt = make_aware(datetime(preferred_date.year, preferred_date.month, preferred_date.day, h_from, m_from))
        end_dt = make_aware(datetime(preferred_date.year, preferred_date.month, preferred_date.day, h_to, m_to))
    except (ValueError, TypeError):
        raise ValueError('Formato data/orario non valido')

    if end_dt <= start_dt:
        raise ValueError("L'orario di fine deve essere successivo all'inizio")
    if (end_dt - start_dt) > timedelta(hours=10):
        raise ValueError('La fascia oraria non può superare le 10 ore')

    appointment = Appointment.objects.create(
        coach=conversation.coach,
        client=conversation.client,
        appointment_type='consultation',
        title=title,
        description=notes or None,
        start_datetime=start_dt,
        duration_minutes=max(1, int((end_dt - start_dt).total_seconds() // 60)),
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

    Notification.objects.create(
        target_user=_recipient_user_for_message(conversation, user),
        notification_type='APPOINTMENT_REQUEST',
        title='Nuova richiesta di appuntamento',
        body=body_msg,
        link_url=f'/chat/{conversation.id}/',
    )

    return msg


def respond_to_appointment(user, conversation, appointment, action, counter_date_str=None, counter_time_str=None):
    """Validates and applies accept/reject for a PENDING appointment, creates the
    APPOINTMENT_RESPONSE Message (+ optional counter-proposal on reject) + notification.

    Accepting confirms the slot the requester already proposed (``appointment.start_datetime``)
    as-is — no re-entry of date/time.

    Raises ValueError(message) on invalid input. Returns the created response Message.
    """
    if appointment.status != 'PENDING':
        raise ValueError('Appointment già processato')

    action = (action or '').lower()
    if action not in ('accept', 'reject'):
        raise ValueError('Azione non valida')

    if action == 'accept':
        appointment.status = 'SCHEDULED'
        appointment.save(update_fields=['status', 'updated_at'])
        start_dt = appointment.start_datetime
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

        counter_date_str = (counter_date_str or '').strip()
        counter_time_str = (counter_time_str or '').strip()
        if counter_date_str and counter_time_str:
            try:
                cd = date_type.fromisoformat(counter_date_str)
                h, m = map(int, counter_time_str.split(':'))
                counter_start = make_aware(datetime(cd.year, cd.month, cd.day, h, m))
                counter_appt = Appointment.objects.create(
                    coach=conversation.coach,
                    client=conversation.client,
                    appointment_type='consultation',
                    title=appointment.title,
                    start_datetime=counter_start,
                    duration_minutes=60,
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

    Notification.objects.create(
        target_user=_recipient_user_for_message(conversation, user),
        notification_type=notif_type,
        title=notif_title,
        body=body_msg,
        link_url=f'/chat/{conversation.id}/',
    )

    return msg
