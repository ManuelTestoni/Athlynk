from django.shortcuts import render, redirect
from django.http import JsonResponse
from django.utils.dateparse import parse_datetime
import json

from domain.accounts.models import ClientProfile
try:
    from domain.calendar.models import Appointment
except ImportError:
    from domain.appointments.models import Appointment

from .session_utils import get_session_user, get_session_coach, get_session_client, get_active_relationship


def agenda_dashboard_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return redirect('check_coach_directory')

        events = Appointment.objects.filter(coach=relationship.coach, client=client).select_related('client')
        events_data = []
        for evt in events:
            events_data.append({
                'id': evt.id,
                'title': f"{evt.title} - {evt.client.first_name} {evt.client.last_name}",
                'start': evt.start_datetime.isoformat(),
                'end': evt.end_datetime.isoformat(),
                'type': evt.appointment_type,
                'status': evt.status,
                'client_name': f"{evt.client.first_name} {evt.client.last_name}",
                'description': evt.description or '',
                'meeting_url': evt.meeting_url or '',
                'check_url': '/check/crea/' if evt.appointment_type.lower() == 'check' else '',
            })

        context = {
            'coach': relationship.coach,
            'client': client,
            'events_json': json.dumps(events_data),
            'can_manage_agenda': False,
            'is_client': True,
        }
        return render(request, 'pages/agenda/dashboard.html', context)

    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    events = Appointment.objects.filter(coach=coach).select_related('client')
    events_data = []
    for evt in events:
        events_data.append({
            'id': evt.id,
            'title': f"{evt.title} - {evt.client.first_name} {evt.client.last_name}",
            'start': evt.start_datetime.isoformat(),
            'end': evt.end_datetime.isoformat(),
            'type': evt.appointment_type,
            'status': evt.status,
            'client_name': f"{evt.client.first_name} {evt.client.last_name}",
            'description': evt.description or '',
            'meeting_url': evt.meeting_url or ''
        })
        
    context = {
        'coach': coach,
        'events_json': json.dumps(events_data),
        'can_manage_agenda': True,
    }
    return render(request, 'pages/agenda/dashboard.html', context)


def api_agenda_events(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    if user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return JsonResponse([], safe=False)

        if request.method != 'GET':
            return JsonResponse({'error': 'Forbidden'}, status=403)

        events = Appointment.objects.filter(coach=relationship.coach, client=client).select_related('client')
        events_data = []
        for evt in events:
            events_data.append({
                'id': evt.id,
                'title': f"{evt.title} - {evt.client.first_name}",
                'start': evt.start_datetime.isoformat(),
                'end': evt.end_datetime.isoformat(),
                'type': evt.appointment_type,
                'client_name': f"{evt.client.first_name} {evt.client.last_name}",
                'status': evt.status,
                'description': evt.description,
                'meeting_url': evt.meeting_url
            })
        return JsonResponse(events_data, safe=False)

    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    if request.method == 'GET':
        events = Appointment.objects.filter(coach=coach).select_related('client')
        events_data = []
        for evt in events:
            events_data.append({
                'id': evt.id,
                'title': f"{evt.title} - {evt.client.first_name}",
                'start': evt.start_datetime.isoformat(),
                'end': evt.end_datetime.isoformat(),
                'type': evt.appointment_type,
                'client_name': f"{evt.client.first_name} {evt.client.last_name}",
                'status': evt.status,
                'description': evt.description,
                'meeting_url': evt.meeting_url
            })
        return JsonResponse(events_data, safe=False)

    elif request.method == 'POST':
        try:
            data = json.loads(request.body)
            client_id = data.get('client_id')
            title = data.get('title')
            appointment_type = data.get('appointment_type', 'First Visit')
            start_datetime = parse_datetime(data.get('start_datetime'))
            end_datetime = parse_datetime(data.get('end_datetime'))
            
            if not title or not client_id or not start_datetime or not end_datetime:
                return JsonResponse({'error': 'Missing required fields'}, status=400)
                
            client = ClientProfile.objects.get(id=client_id, coaching_relationships_as_client__coach=coach)
            
            evt = Appointment.objects.create(
                coach=coach,
                client=client,
                title=title,
                appointment_type=appointment_type,
                start_datetime=start_datetime,
                end_datetime=end_datetime,
                description=data.get('description', ''),
                meeting_url=data.get('meeting_url', ''),
                status='SCHEDULED'
            )
            return JsonResponse({'status': 'success', 'event_id': evt.id})
        except Exception as e:
            return JsonResponse({'error': str(e)}, status=500)

