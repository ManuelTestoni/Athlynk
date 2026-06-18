"""Account-level operations shared by the web views and the mobile API."""

from django.db import connection, transaction


def hard_delete_user(user):
    """Permanently delete a user and everything that hangs off them.

    Profiles (CoachProfile/ClientProfile) cascade from User, and their domain
    rows cascade in turn. Two snags handled here:

    * ``ClientSubscription`` → ``SubscriptionPlan`` (on_delete=PROTECT): deleting
      a coach cascades into their SubscriptionPlans, which Postgres refuses while
      any ClientSubscription still points at them. Tear those billing rows down
      first so the cascade completes instead of raising IntegrityError.
    * ``timeline_timelineevent``: orphan table from a removed app, still in prod
      with a non-cascading FK to accounts_clientprofile. Migration 0015 drops it,
      but clear any rows defensively so deletes work before the migration runs.
    """
    from domain.billing.models import ClientSubscription

    with transaction.atomic():
        coach = getattr(user, 'coach_profile', None)
        if coach is not None:
            ClientSubscription.objects.filter(subscription_plan__coach=coach).delete()
        _clear_orphan_timeline(user)
        user.delete()


def _clear_orphan_timeline(user):
    """Delete rows in the orphan timeline table that reference this user.

    No-op if the table is already gone (post-migration / SQLite tests).
    """
    if 'timeline_timelineevent' not in connection.introspection.table_names():
        return
    client = getattr(user, 'client_profile', None)
    with connection.cursor() as cur:
        cur.execute('DELETE FROM timeline_timelineevent WHERE author_id = %s', [user.id])
        if client is not None:
            cur.execute('DELETE FROM timeline_timelineevent WHERE athlete_id = %s', [client.id])
