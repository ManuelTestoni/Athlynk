"""Resend HTTP API email backend.

Cloud platforms (Render, Railway, Fly) block outbound SMTP ports, so the
smtp.resend.com:587 relay times out at the TCP connect stage. Resend's HTTP API
on :443 is never blocked. This backend POSTs each message to
https://api.resend.com/emails, reusing the standard Django EmailMessage
interface so services/email.py stays unchanged.
"""
import logging

import httpx
from django.conf import settings
from django.core.mail.backends.base import BaseEmailBackend

logger = logging.getLogger(__name__)

RESEND_API_URL = 'https://api.resend.com/emails'


class ResendAPIBackend(BaseEmailBackend):
    """Send mail through the Resend HTTP API instead of SMTP."""

    def __init__(self, fail_silently=False, **kwargs):
        super().__init__(fail_silently=fail_silently, **kwargs)
        self.api_key = (getattr(settings, 'RESEND_API_KEY', '') or '').strip()
        self.timeout = getattr(settings, 'EMAIL_TIMEOUT', 10) or 10

    def send_messages(self, email_messages):
        if not email_messages:
            return 0
        if not self.api_key:
            logger.error('ResendAPIBackend: RESEND_API_KEY not configured')
            if not self.fail_silently:
                raise ValueError('RESEND_API_KEY not configured')
            return 0
        sent = 0
        with httpx.Client(timeout=self.timeout) as client:
            for message in email_messages:
                if self._send(client, message):
                    sent += 1
        return sent

    def _send(self, client, message):
        payload = {
            'from': message.from_email,
            'to': list(message.to),
            'subject': message.subject,
            'text': message.body,
        }
        if message.cc:
            payload['cc'] = list(message.cc)
        if message.bcc:
            payload['bcc'] = list(message.bcc)
        if message.reply_to:
            payload['reply_to'] = list(message.reply_to)
        for content, mimetype in getattr(message, 'alternatives', None) or []:
            if mimetype == 'text/html':
                payload['html'] = content
                break
        try:
            resp = client.post(
                RESEND_API_URL,
                json=payload,
                headers={'Authorization': f'Bearer {self.api_key}'},
            )
            resp.raise_for_status()
            return True
        except Exception as e:
            logger.exception('Resend API send failed to %s: %s', message.to, e)
            if not self.fail_silently:
                raise
            return False
