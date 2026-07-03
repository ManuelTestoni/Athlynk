"""API endpoints for check folders (per coach).

Mirrors the nutrition folder system but scoped to QuestionnaireTemplate/CheckFolder.
Folders organize the coach's *personal* templates only — preset clones are never
filed (preset_key is non-null).
"""

from __future__ import annotations

from django.db.models import Count, Q
from django.http import JsonResponse
from django.shortcuts import get_object_or_404

from domain.checks.models import CheckFolder, QuestionnaireTemplate

from .http_utils import parse_json_body, require_coach, serialize_folder


ALLOWED_LABEL_COLORS = {
    'bronze', 'aegean', 'amber', 'emerald', 'rose',
    'violet', 'slate', 'sand', 'crimson', 'teal',
}


def _require_coach(request):
    return require_coach(request)


def _custom_filter(coach):
    return Q(coach=coach, is_active=True, preset_key__isnull=True)


def _serialize_folder(folder, template_count=None):
    count = template_count if template_count is not None \
        else folder.templates.filter(is_active=True).count()
    return serialize_folder(folder, 'template_count', count)


def _parse_body(request):
    return parse_json_body(request)


def api_check_folders(request):
    coach, err = _require_coach(request)
    if err:
        return err

    if request.method == 'GET':
        folders = CheckFolder.objects.filter(coach=coach).annotate(
            _count=Count('templates', filter=Q(templates__is_active=True)),
        )
        return JsonResponse(
            [_serialize_folder(f, template_count=f._count) for f in folders],
            safe=False,
        )

    if request.method == 'POST':
        data, perr = _parse_body(request)
        if perr:
            return perr
        title = (data.get('title') or '').strip()
        if not title:
            return JsonResponse({'error': 'Titolo richiesto.'}, status=400)
        if CheckFolder.objects.filter(coach=coach, title__iexact=title).exists():
            return JsonResponse({'error': 'Hai già una cartella con questo nome.'}, status=400)
        label_text = (data.get('label_text') or '').strip()[:40]
        label_color = (data.get('label_color') or '').strip().lower()
        if label_color and label_color not in ALLOWED_LABEL_COLORS:
            label_color = ''
        order = CheckFolder.objects.filter(coach=coach).count() + 1
        folder = CheckFolder.objects.create(
            coach=coach, title=title,
            label_text=label_text, label_color=label_color, order=order,
        )
        return JsonResponse(_serialize_folder(folder, template_count=0), status=201)

    return JsonResponse({'error': 'method not allowed'}, status=405)


def api_check_folder_detail(request, folder_id):
    coach, err = _require_coach(request)
    if err:
        return err
    folder = get_object_or_404(CheckFolder, id=folder_id, coach=coach)

    if request.method == 'GET':
        return JsonResponse(_serialize_folder(folder))

    if request.method == 'PATCH':
        data, perr = _parse_body(request)
        if perr:
            return perr
        if 'title' in data:
            title = (data.get('title') or '').strip()
            if not title:
                return JsonResponse({'error': 'Titolo richiesto.'}, status=400)
            if CheckFolder.objects.filter(coach=coach, title__iexact=title).exclude(id=folder.id).exists():
                return JsonResponse({'error': 'Hai già una cartella con questo nome.'}, status=400)
            folder.title = title
        if 'label_text' in data:
            folder.label_text = (data.get('label_text') or '').strip()[:40]
        if 'label_color' in data:
            color = (data.get('label_color') or '').strip().lower()
            folder.label_color = color if color in ALLOWED_LABEL_COLORS or color == '' else folder.label_color
        if 'order' in data:
            try:
                folder.order = max(0, int(data.get('order')))
            except (TypeError, ValueError):
                pass
        folder.save()
        return JsonResponse(_serialize_folder(folder))

    if request.method == 'DELETE':
        action = request.GET.get('action', 'move_to_unfiled')
        target_id = request.GET.get('target_folder_id')

        if action == 'move_to_unfiled':
            folder.templates.update(folder=None)
        elif action == 'move_to':
            if not target_id:
                return JsonResponse({'error': 'target_folder_id richiesto.'}, status=400)
            try:
                target = CheckFolder.objects.get(id=int(target_id), coach=coach)
            except (CheckFolder.DoesNotExist, ValueError, TypeError):
                return JsonResponse({'error': 'Cartella di destinazione non trovata.'}, status=404)
            if target.id == folder.id:
                return JsonResponse({'error': 'Cartella di destinazione coincide.'}, status=400)
            folder.templates.update(folder=target)
        elif action == 'delete_templates':
            folder.templates.all().delete()
        else:
            return JsonResponse({'error': 'azione non valida.'}, status=400)

        folder.delete()
        return JsonResponse({'status': 'ok'})

    return JsonResponse({'error': 'method not allowed'}, status=405)


def api_check_folders_reorder(request):
    """POST {ids: [...]} → persiste l'ordine manuale delle cartelle del coach."""
    coach, err = _require_coach(request)
    if err:
        return err
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    data, perr = _parse_body(request)
    if perr:
        return perr
    ids = data.get('ids')
    if not isinstance(ids, list) or not ids:
        return JsonResponse({'error': 'ids richiesto.'}, status=400)
    folders = {f.id: f for f in CheckFolder.objects.filter(coach=coach, id__in=ids)}
    for idx, fid in enumerate(ids):
        folder = folders.get(fid)
        if folder and folder.order != idx + 1:
            folder.order = idx + 1
            folder.save(update_fields=['order', 'updated_at'])
    return JsonResponse({'status': 'ok'})


def api_check_template_folder(request, template_id):
    """Lightweight PATCH to move a (custom) QuestionnaireTemplate in/out of a folder."""
    coach, err = _require_coach(request)
    if err:
        return err
    template = get_object_or_404(
        QuestionnaireTemplate, id=template_id, coach=coach,
        is_active=True, preset_key__isnull=True,
    )

    if request.method != 'PATCH':
        return JsonResponse({'error': 'method not allowed'}, status=405)

    data, perr = _parse_body(request)
    if perr:
        return perr
    if 'folder_id' not in data:
        return JsonResponse({'error': 'folder_id richiesto.'}, status=400)

    folder_id = data.get('folder_id')
    if folder_id in (None, '', 0):
        template.folder = None
    else:
        try:
            template.folder = CheckFolder.objects.get(id=int(folder_id), coach=coach)
        except (CheckFolder.DoesNotExist, ValueError, TypeError):
            return JsonResponse({'error': 'Cartella non trovata.'}, status=404)
    template.save(update_fields=['folder', 'updated_at'])
    return JsonResponse({'status': 'ok', 'folder_id': template.folder_id})
