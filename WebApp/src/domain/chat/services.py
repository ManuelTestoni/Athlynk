from domain.chat.models import Conversation, Message, Notification, AutomaticMessageTemplate


DEFAULT_PLAN_DELETED_BODY = (
    'Ciao {nome}! Ho cancellato la tua scheda: se non riesci più a visualizzarla '
    'non preoccuparti, te ne invio subito una nuova!'
)

DEFAULT_WELCOME_BODY = 'Ciao {nome}, benvenuto/a! 🎉 Sono felice di iniziare questo percorso insieme.'
DEFAULT_GOODBYE_BODY = 'Grazie di tutto {nome} 🙏 È stato un piacere allenarti. Le porte restano sempre aperte!'
DEFAULT_SUBSCRIPTION_EXPIRING_BODY = (
    'Ciao {nome}, il tuo abbonamento sta per scadere ⏳ Rinnova per non perdere i progressi!'
)

_DEFAULT_BODIES = {
    'WELCOME': DEFAULT_WELCOME_BODY,
    'GOODBYE': DEFAULT_GOODBYE_BODY,
    'SUBSCRIPTION_EXPIRING': DEFAULT_SUBSCRIPTION_EXPIRING_BODY,
}


def _render(body, client):
    """Replace personalization tokens with the client's name."""
    return (body or '').replace('{nome}', client.first_name or '').replace('{cognome}', client.last_name or '')


def _deliver(coach, client, body, attachment=None):
    """Create the chat message + conversation bump + recipient notification.

    Mirrors the message-creation flow of views_chat.api_send_message. The client
    receives it via the existing api_messages_since polling endpoint.
    """
    conversation, _ = Conversation.objects.get_or_create(coach=coach, client=client)
    body = _render(body, client)
    msg_type = 'IMAGE' if attachment else 'TEXT'

    msg = Message.objects.create(
        conversation=conversation,
        sender_user=coach.user,
        body=body,
        message_type=msg_type,
        attachment=attachment.name if attachment else None,
    )

    conversation.last_message_at = msg.sent_at
    conversation.save(update_fields=['last_message_at', 'updated_at'])

    coach_name = f"{coach.first_name} {coach.last_name}".strip()
    Notification.objects.create(
        target_user=client.user,
        notification_type='MESSAGE',
        title=f'Nuovo messaggio da {coach_name}'.strip() or 'Nuovo messaggio',
        body=(body[:120] + '…') if len(body) > 120 else body,
        link_url=f'/chat/{conversation.id}/',
    )


def send_automatic_message(coach, client, event_type):
    """Send a coach's configured automatic message to a client's chat.

    No-op when the event is disabled. When enabled with no custom text, falls
    back to a generic default message the coach can later personalize —
    matching how PLAN_DELETED already behaves.
    """
    template = AutomaticMessageTemplate.objects.filter(
        coach=coach, event_type=event_type, is_enabled=True
    ).first()
    if not template:
        return
    body = template.body or _DEFAULT_BODIES.get(event_type)
    if not body and not template.attachment:
        return

    _deliver(coach, client, body, template.attachment)


def send_plan_deleted_message(coach, client):
    """Notify a client in chat that an assigned plan was deleted.

    Unlike the other events this one is opt-out: with no template configured a
    default courtesy message is sent. A template row lets the coach customize
    the text or disable the event entirely.
    """
    template = AutomaticMessageTemplate.objects.filter(
        coach=coach, event_type='PLAN_DELETED'
    ).first()
    if template and not template.is_enabled:
        return

    body = template.body if (template and template.body) else DEFAULT_PLAN_DELETED_BODY
    _deliver(coach, client, body, template.attachment if template else None)
