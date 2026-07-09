"""Package dei check (ex monolite config/views_check.py, ~1900 righe).

I sottomoduli sono organizzati per responsabilità; questo __init__ re-esporta
tutti i simboli pubblici così `from . import views_check` in urls.py e gli
import esistenti (`from .views_check import ...`) continuano a funzionare.
"""

from .helpers import (  # noqa: F401
    RESERVED_FIELD_MAP, build_measurements,
    create_quick_measurement, quick_measurement_template, QuickMeasurementError,
)
from .pages import (  # noqa: F401
    check_dashboard_view, check_create_view, check_detail_view,
    check_edit_view, client_check_history_view, check_progress_charts_view,
    check_comparator_view, client_assigned_checks_view, fill_assigned_check_view,
    api_check_photo_proxy,
)
from .assignments import (  # noqa: F401
    api_check_assign, api_check_assignment_ics, api_check_search,
    api_coach_clients_check_status, api_check_schedule, api_check_review,
)
from .templates_admin import (  # noqa: F401
    check_templates_list_view, check_template_new_view, check_template_edit_view,
    api_check_template_restore, api_check_template_duplicate, api_check_template_delete,
    api_bmr_formula_create, check_templates_api,
)
