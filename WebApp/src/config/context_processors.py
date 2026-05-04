from .session_utils import build_identity_context


def _get_current_section(path):
    if path == '/':
        return 'dashboard'
    if path.startswith('/clienti'):
        return 'clienti'
    if path.startswith('/allenamenti'):
        return 'allenamenti'
    if path.startswith('/nutrizione'):
        return 'nutrizione'
    if path.startswith('/agenda'):
        return 'agenda'
    if path.startswith('/chat'):
        return 'chat'
    if path.startswith('/check'):
        return 'check'
    if path.startswith('/abbonamenti'):
        return 'abbonamenti'
    if path.startswith('/il-mio-coach') or path.startswith('/il-mio-specialista'):
        return 'specialista'
    if path.startswith('/impostazioni'):
        return 'impostazioni'
    return ''


def identity_context(request):
    ctx = build_identity_context(request)
    ctx['current_section'] = _get_current_section(request.path)
    return ctx
