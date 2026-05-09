document.addEventListener('alpine:init', () => {
    Alpine.data('workoutBuilder', () => ({
        editMode: false,
        title: '',
        description: '',
        goal: 'Ipertrofia',
        level: 'Intermedio',

        clientSearchQuery: '',
        clientSearchResults: [],
        selectedClient: null,

        days: [{ id: 1, name: 'Giorno 1', exercises: [] }],
        daySearch: { 1: { q: '', results: [], searching: false, show: false } },

        isSaving: false,

        init() {
            if (window.WORKOUT_DATA) {
                this.editMode = true;
                this.title = window.WORKOUT_DATA.title || '';
                this.description = window.WORKOUT_DATA.description || '';
                this.goal = window.WORKOUT_DATA.goal || 'Ipertrofia';
                this.level = window.WORKOUT_DATA.level || 'Intermedio';
                this.selectedClient = {
                    id: window.WORKOUT_DATA.client_id,
                    name: window.WORKOUT_DATA.client_name
                };
                if (window.WORKOUT_DATA.days && window.WORKOUT_DATA.days.length > 0) {
                    this.days = window.WORKOUT_DATA.days;
                }
            }
            // Ensure all days have a daySearch entry
            this.days.forEach(d => {
                if (!this.daySearch[d.id]) {
                    this.daySearch[d.id] = { q: '', results: [], searching: false, show: false };
                }
            });
        },

        // ----- CLIENTI -----
        async searchClients() {
            if (this.clientSearchQuery.length < 2) {
                this.clientSearchResults = [];
                return;
            }
            try {
                const response = await fetch(`/api/clients/search/?q=${this.clientSearchQuery}`);
                this.clientSearchResults = await response.json();
            } catch (e) {
                console.error(e);
            }
        },

        selectClient(client) {
            this.selectedClient = client;
            this.clientSearchQuery = '';
            this.clientSearchResults = [];
        },

        clearClient() {
            this.selectedClient = null;
        },

        // ----- RICERCA ESERCIZI PER GIORNO -----
        async searchForDay(dayId, query) {
            const s = this.daySearch[dayId];
            if (!s) return;
            if (query.length < 2) { s.results = []; s.show = false; return; }
            s.searching = true;
            try {
                const r = await fetch('/api/exercises/search/?q=' + encodeURIComponent(query));
                s.results = await r.json();
                s.show = true;
            } catch (e) {
                console.error(e);
            } finally {
                s.searching = false;
            }
        },

        pickForDay(dayIndex, dayId, ex) {
            const newExercise = {
                exercise_id: ex.id,
                name: ex.name,
                target_muscle_group: ex.target_muscle_group,
                sets: '4',
                reps: '10',
                rest: '90s',
                notes: ''
            };
            const day = this.days[dayIndex];
            this.days[dayIndex] = { ...day, exercises: [...day.exercises, newExercise] };
            const s = this.daySearch[dayId];
            if (s) { s.q = ''; s.results = []; s.show = false; }
        },

        closeDaySearch(dayId) {
            const s = this.daySearch[dayId];
            if (s) s.show = false;
        },

        // ----- BUILDER -----
        addDay() {
            const nextId = this.days.length > 0 ? Math.max(...this.days.map(d => d.id)) + 1 : 1;
            this.days = [...this.days, { id: nextId, name: `Giorno ${nextId}`, exercises: [] }];
            this.daySearch[nextId] = { q: '', results: [], searching: false, show: false };
        },

        removeDay(index) {
            const dayId = this.days[index].id;
            this.days = this.days.filter((_, i) => i !== index);
            delete this.daySearch[dayId];
        },

        removeExercise(dayIndex, exIndex) {
            const day = this.days[dayIndex];
            this.days[dayIndex] = {
                ...day,
                exercises: day.exercises.filter((_, i) => i !== exIndex)
            };
        },

        // ----- SAVE -----
        async saveWorkout(status = "ACTIVE") {
            if (!this.title || !this.selectedClient) {
                alert("Titolo e cliente obbligatori.");
                return;
            }
            if (this.days.length > 20) {
                alert("Massimo 20 giornate per scheda.");
                return;
            }

            this.isSaving = true;

            const payload = {
                title: this.title,
                description: this.description,
                goal: this.goal,
                level: this.level,
                status: status,
                client_id: this.selectedClient.id,
                days: this.days
            };

            try {
                const csrfToken = document.querySelector('[name=csrfmiddlewaretoken]')?.value
                               || document.cookie.split('; ').find(row => row.startsWith('csrftoken=')).split('=')[1];

                const savedUrl = this.editMode && window.WORKOUT_EDIT_URL
                                 ? window.WORKOUT_EDIT_URL
                                 : '/allenamenti/crea/';

                const response = await fetch(savedUrl, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRFToken': csrfToken
                    },
                    body: JSON.stringify(payload)
                });

                const data = await response.json();
                if (response.ok && data.redirect_url) {
                    window.location.href = data.redirect_url;
                } else {
                    alert("Errore: " + (data.error || "Impossibile salvare la scheda"));
                }
            } catch (e) {
                console.error(e);
                alert("Errore di rete");
            } finally {
                this.isSaving = false;
            }
        }
    }));
});
