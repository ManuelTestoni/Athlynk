"""Shared event contract — the single source of truth for PostHog event names,
the schema version, and the global properties stamped on every event.

The iOS (`Shared/Core/Analytics.swift`) and web (`templates/partials/posthog.html`)
clients mirror these names verbatim. Bump ``EVENT_VERSION`` on any breaking
change to a payload so downstream queries can branch on it. Keep names
``snake_case``, stable, and minimal.
"""

EVENT_VERSION = "1.0"


class Ev:
    # Lifecycle / navigation
    APP_OPENED = "app_opened"
    SCREEN_VIEWED = "screen_viewed"
    COACH_LOGGED_IN = "coach_logged_in"

    # Coach workflow
    CLIENT_LIST_VIEWED = "client_list_viewed"
    CHECKIN_OPENED = "checkin_opened"
    CHECKIN_REVIEW_STARTED = "checkin_review_started"
    CHECKIN_REVIEW_COMPLETED = "checkin_review_completed"
    MESSAGE_SENT = "message_sent"
    MESSAGE_REPLIED = "message_replied"
    PLAN_UPDATED = "plan_updated"
    TASK_CREATED = "task_created"
    TASK_COMPLETED = "task_completed"
    FOLLOWUP_SENT = "followup_sent"
    AUTOMATION_TRIGGERED = "automation_triggered"

    # Commercial (server-originated)
    SUBSCRIPTION_RENEWAL_DUE = "subscription_renewal_due"
    SUBSCRIPTION_RENEWED = "subscription_renewed"
    PAYMENT_FAILED = "payment_failed"


# Global property keys attached to every event when applicable. Documented here
# so clients stay in sync; assembled server-side by services.posthog_client and
# client-side by the iOS/web wrappers.
GLOBAL_PROPERTY_KEYS = (
    "event_version", "environment", "platform", "app_version",
    "workspace_id", "coach_id", "client_id", "role",
    "is_internal_user", "is_test_account", "package_type", "plan_type",
)
