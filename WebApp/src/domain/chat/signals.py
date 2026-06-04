from django.db import transaction
from django.db.models.signals import pre_save, post_save
from django.dispatch import receiver

from domain.coaching.models import CoachingRelationship
from domain.chat.models import Notification
from domain.chat.services import send_automatic_message


@receiver(pre_save, sender=CoachingRelationship)
def _stash_old_status(sender, instance, **kwargs):
    """Capture the previous status so post_save can detect the → INACTIVE transition."""
    if instance.pk:
        instance._old_status = (
            sender.objects.filter(pk=instance.pk).values_list('status', flat=True).first()
        )
    else:
        instance._old_status = None


@receiver(post_save, sender=CoachingRelationship)
def _send_lifecycle_message(sender, instance, created, **kwargs):
    coach = instance.coach
    client = instance.client

    if created and instance.status == 'ACTIVE':
        transaction.on_commit(lambda: send_automatic_message(coach, client, 'WELCOME'))
        return

    old_status = getattr(instance, '_old_status', None)
    if not created and old_status != 'INACTIVE' and instance.status == 'INACTIVE':
        transaction.on_commit(lambda: send_automatic_message(coach, client, 'GOODBYE'))


@receiver(post_save, sender=Notification)
def _push_on_notification(sender, instance, created, **kwargs):
    """Mirror every freshly-created in-app Notification to an APNs push. Central
    fan-out: every event that already creates a Notification (new message, check
    assigned/reviewed, plan assigned, macro reminder, …) gets a push for free.
    Delivery is a no-op until APNs is configured, so this is inert today."""
    if not created:
        return
    from config.services.push import send_push_to_user
    user = instance.target_user
    title = instance.title
    body = instance.body or ''
    data = {'type': instance.notification_type, 'link': instance.link_url or ''}
    transaction.on_commit(lambda: send_push_to_user(user, title, body, data))
