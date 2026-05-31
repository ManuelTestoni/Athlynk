from domain.chat.models import Conversation, Message, Notification, AutomaticMessageTemplate


def _render(body, client):
    """Replace personalization tokens with the client's name."""
    return (body or '').replace('{nome}', client.first_name or '').replace('{cognome}', client.last_name or '')


def send_automatic_message(coach, client, event_type):
    """Send a coach's configured automatic message to a client's chat.

    No-op when no enabled template exists or the template is empty. Mirrors the
    message-creation flow of views_chat.api_send_message (message + conversation
    bump + recipient notification). The client receives it via the existing
    api_messages_since polling endpoint.
    """
    template = AutomaticMessageTemplate.objects.filter(
        coach=coach, event_type=event_type, is_enabled=True
    ).first()
    if not template or (not template.body and not template.attachment):
        return

    conversation, _ = Conversation.objects.get_or_create(coach=coach, client=client)
    body = _render(template.body, client)
    msg_type = 'IMAGE' if template.attachment else 'TEXT'

    msg = Message.objects.create(
        conversation=conversation,
        sender_user=coach.user,
        body=body,
        message_type=msg_type,
        attachment=template.attachment.name if template.attachment else None,
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
