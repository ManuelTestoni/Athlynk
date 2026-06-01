/**
 * Utility JS per la gestione dei form Modali via Fetch API nell'intera Web App
 * Permette di inviare dati senza ricaricare la pagina (es. aggiunta cliente, piano, dieta)
 */

document.addEventListener('DOMContentLoaded', () => {
    // Intercetta tutti i form nei modali che hanno l'attributo data-ajax-form="true"
    const ajaxForms = document.querySelectorAll('form[data-ajax-form="true"]');

    ajaxForms.forEach(form => {
        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const submitBtn = form.querySelector('button[type="submit"]');
            const originalText = submitBtn.innerHTML;
            submitBtn.innerHTML = '<i class="ph ph-spinner animate-spin mr-2"></i> Salvataggio...';
            submitBtn.disabled = true;

            const formData = new FormData(form);
            const url = form.getAttribute('action') || window.location.href;

            try {
                const response = await fetch(url, {
                    method: 'POST',
                    body: formData,
                    headers: {
                        'X-Requested-With': 'XMLHttpRequest'
                    }
                });

                if (response.ok) {
                    // Se la richiesta va a buon fine, chiude il modal (dispatch evento custom per Alpine.js se necessario)
                    // oppure ricarica o aggiorna la UI
                    const result = await response.json().catch(() => null);
                    
                    // Mostra un toast di successo se implementato, o reload
                    if (result && result.redirect_url) {
                        window.location.href = result.redirect_url;
                    } else {
                        window.location.reload(); // Per ora ricarichiamo la pagina per vedere i nuovi dati
                    }
                } else {
                    console.error("Errore nel salvataggio dei dati");
                    Alpine.store('toasts').push({ kind: 'danger', msg: 'Si è verificato un errore durante il salvataggio.' });
                }
            } catch (error) {
                console.error("Errore di rete:", error);
            } finally {
                submitBtn.innerHTML = originalText;
                submitBtn.disabled = false;
            }
        });
    });
});

/**
 * Funzione Helper per l'apertura tramite JS vanilla se Alpine.js non è usato 
 * (es. bottoni esterni ai componenti Alpine)
 */
function openModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        // Logica ibrida se si preferisce vanilla JS:
        modal.style.display = 'block';
        modal.classList.remove('hidden');
    }
}

function closeModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.style.display = 'none';
        modal.classList.add('hidden');
        
        // Reset dei form al suo interno
        const form = modal.querySelector('form');
        if (form) form.reset();
    }
}
