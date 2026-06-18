"""Drop the orphan `timeline_timelineevent` table.

The `timeline` app was removed from the codebase, but its table still lives in
the production database with a non-cascading FK to `accounts_clientprofile`.
That dangling constraint blocks deleting an athlete ("update or delete on table
accounts_clientprofile violates foreign key constraint ... timeline_timelineevent").
Nothing reads or writes the table anymore, so drop it for good.
"""
from django.db import migrations


def drop_orphan_timeline(apps, schema_editor):
    # CASCADE is Postgres-only; SQLite (tests) never has this orphan table.
    if schema_editor.connection.vendor != 'postgresql':
        return
    with schema_editor.connection.cursor() as cur:
        cur.execute('DROP TABLE IF EXISTS timeline_timelineevent CASCADE;')


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0014_devicetoken_bundle_id'),
    ]

    operations = [
        migrations.RunPython(drop_orphan_timeline, migrations.RunPython.noop),
    ]
