document.addEventListener('alpine:init', () => {
    Alpine.data('agendaDashboard', () => ({
        calendar: null,
        events: window.INITIAL_EVENTS || [],
        showDetailModal: false,
        showCreateModal: false,
        selectedEvent: null,

        // Create modal state
        clientSearchQuery: '',
        clientSearchResults: [],
        selectedClientName: '',
        appointmentTypes: [
            {value: 'check', label: 'Check progressi', icon: '📋'},
            {value: 'prima_visita', label: 'Prima visita', icon: '🩺'},
            {value: 'visita', label: 'Visita', icon: '📅'},
            {value: 'consulenza', label: 'Consulenza / Video', icon: '💬'},
        ],
        newEvent: {
            title: '',
            client_id: null,
            appointment_type: 'check',
            start_datetime: '',
            end_datetime: '',
            description: '',
            meeting_url: '',
            is_recurring: false,
            recurrence_rule: 'settimanale',
        },

        init() {
            this.initCalendar();
        },

        initCalendar() {
            let calendarEl = document.getElementById('calendar');
            this.calendar = new FullCalendar.Calendar(calendarEl, {
                initialView: 'timeGridWeek',
                headerToolbar: {
                    left: 'prev,next today',
                    center: 'title',
                    right: 'dayGridMonth,timeGridWeek,timeGridDay'
                },
                locale: 'it',
                events: this.events,
                eventClick: (info) => {
                    this.openEventDetail(info.event);
                },
                dateClick: (info) => {
                    this.openCreateModal(info.dateStr);
                },
                // Let FullCalendar + Tailwind custom CSS handle the event rendering globally
                eventTimeFormat: {
                    hour: '2-digit',
                    minute: '2-digit',
                    meridiem: false,
                    hour12: false
                }
            });
            this.calendar.render();
        },

        openEventDetail(event) {
            this.selectedEvent = {
                title: event.title,
                start: event.start,
                end: event.end,
                extendedProps: event.extendedProps
            };
            this.showDetailModal = true;
        },

        openCreateModal(dateStr = null) {
            this.showCreateModal = true;
            this.newEvent = {
                title: '',
                client_id: null,
                appointment_type: 'check',
                start_datetime: dateStr ? (dateStr.length > 10 ? dateStr.substring(0,16) : dateStr + "T09:00") : '',
                end_datetime: dateStr ? (dateStr.length > 10 ? dateStr.substring(0,16) : dateStr + "T10:00") : '',
                description: '',
                meeting_url: '',
                is_recurring: false,
                recurrence_rule: 'settimanale',
            };
            this.clientSearchQuery = '';
            this.clientSearchResults = [];
            this.selectedClientName = '';
        },

        appointmentTypePlaceholder() {
            const placeholders = {
                check: 'Es. Check mensile',
                prima_visita: 'Es. Prima visita',
                visita: 'Es. Visita di controllo',
                consulenza: 'Es. Videoconsulenza',
            };
            return placeholders[this.newEvent.appointment_type] || 'Titolo appuntamento';
        },

        async searchClients() {
            if (this.clientSearchQuery.length < 2) {
                this.clientSearchResults = [];
                return;
            }
            try {
                const response = await fetch(`/api/clients/search/?q=${this.clientSearchQuery}`);
                const data = await response.json();
                this.clientSearchResults = data;
            } catch (e) {
                console.error(e);
            }
        },

        selectClient(client) {
            this.newEvent.client_id = client.id;
            this.selectedClientName = client.name;
            this.clientSearchResults = [];
            this.clientSearchQuery = '';
        },

        async saveAppointment() {
            if(!this.newEvent.title || !this.newEvent.client_id || !this.newEvent.start_datetime || !this.newEvent.end_datetime) {
                Alpine.store('toasts').push({ kind: 'warn', msg: 'Completa i campi obbligatori (Titolo, Cliente, Inizio, Fine).' });
                return;
            }

            try {
                const csrfToken = document.querySelector('[name=csrfmiddlewaretoken]')?.value 
                               || document.cookie.split('; ').find(row => row.startsWith('csrftoken=')).split('=')[1];

                const response = await fetch('/api/agenda/events/', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRFToken': csrfToken
                    },
                    body: JSON.stringify(this.newEvent)
                });
                
                const data = await response.json();
                if(response.ok) {
                    Alpine.store('toasts').push({ kind: 'success', msg: 'Appuntamento salvato con successo!' });
                    window.location.reload(); // Semplice ricarica per mostrare l'evento
                } else {
                    Alpine.store('toasts').push({ kind: 'danger', msg: data.error || 'Impossibile salvare' });
                }
            } catch (e) {
                console.error(e);
                Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete' });
            }
        },

        formatDate(d) {
            if(!d) return '';
            return new Date(d).toLocaleDateString('it-IT', { year: 'numeric', month: 'long', day: 'numeric' });
        },
        
        formatTime(d) {
            if(!d) return '';
            return new Date(d).toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' });
        },

        connectGoogle() {
            Alpine.store('toasts').push({ kind: 'info', msg: 'Reindirizzamento OAuth a Google Calendar...' });
        },
        connectApple() {
            Alpine.store('toasts').push({ kind: 'info', msg: 'Apertura popup per credenziali iCloud Calendar (caldav)...' });
        }
    }));
});
