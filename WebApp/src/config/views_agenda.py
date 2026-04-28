from django.shortcuts import render, redirect
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.utils.dateparse import parse_datetime
from django.db.models import Q
import json
from domain.accounts.models import CoachProfile, ClientProfile
try:
    from domain.calendar.models import Appointment
except ImportError:
    from domain.appointments.models import Appointment

def agenda_dashboard_view(request):
    coach = CoachProfile.objects.first() # mock user
    
    # We'll pass events to the template as well
    # A robust implementation would use a separate API to fetch events, but for simplicity we render it.
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
        'events_json': json.dumps(events_data)
    }
    return render(request, 'pages/agenda/dashboard.html', context)

@csrf_exempt
def api_agenda_events(request):
    coach = CoachProfile.objects.first()
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
                
            client = ClientProfile.objects.get(id=client_id)
            
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

