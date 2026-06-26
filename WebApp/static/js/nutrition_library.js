/* Athlynk · Nutrition · Piani Alimentari hub
   Alpine factory backing pages/nutrizione/piani_list.html.
   Source data is bootstrapped via window.NUTRITION_LIBRARY_INIT in the template. */

function nutCsrfToken() {
  return document.cookie.split('; ').find(r => r.startsWith('csrftoken='))?.split('=')[1]
    || (window.NUTRITION_LIBRARY_INIT && window.NUTRITION_LIBRARY_INIT.csrf)
    || '';
}

function nutritionLibrary() {
  return {
    /* === state === */
    plans: window.NUTRITION_LIBRARY_INIT.plans || [],
    folders: window.NUTRITION_LIBRARY_INIT.folders || [],
    clientsAll: window.NUTRITION_LIBRARY_INIT.clients || [],
    urls: window.NUTRITION_LIBRARY_INIT.urls,
    search: '',
    selectedFolderId: 'all',
    availableLabelColors: ['bronze','aegean','amber','emerald','rose','violet','slate','sand','crimson','teal'],

    /* filter chips */
    activeFilter: 'all',
    filterChips: [
      { id: 'all',      label: 'Tutti' },
      { id: 'active',   label: 'Attivi' },
      { id: 'template', label: 'Template' },
      { id: 'draft',    label: 'Bozza' },
    ],

    /* new-plan modal */
    newPlanModal: false,
    newPlanKind: null,
    newPlanMode: 'FOOD',

    /* duplicate */
    duplicatingId: null,

    /* drag */
    draggedPlanId: null,
    dropTargetId: null,
    draggedFolderId: null,

    /* folder edit */
    editingFolderId: null,
    folderEditDraft: '',
    creatingFolder: false,
    folderCreateDraft: '',
    menuFolder: null,

    /* assign modal */
    assignModal: false,
    assignPlanId: null,
    assignPlanName: '',
    clientSearch: '',
    selectedClient: null,
    startDate: '',
    endDate: '',
    assignNotes: '',
    saving: false,
    successFlash: false,

    /* delete plan */
    deleteModal: false,
    deletePlanId: null,

    /* delete folder */
    deleteFolderOpen: false,
    folderToDelete: null,
    deleteFolderAction: 'move_to_unfiled',
    deleteFolderTarget: '',

    init() {
      // bfcache restore (browser Back) can resurrect a deleted plan — reload fresh.
      window.addEventListener('pageshow', (e) => { if (e.persisted) location.reload(); });
    },

    /* === selectors === */
    selectFolder(id) { this.selectedFolderId = id; },
    plansInFolder() {
      if (this.selectedFolderId === 'all') return this.plans;
      if (this.selectedFolderId === 'unfiled') return this.plans.filter(p => !p.folder_id);
      return this.plans.filter(p => p.folder_id === this.selectedFolderId);
    },
    visiblePlans() {
      const q = (this.search || '').toLowerCase().trim();
      return this.plansInFolder().filter(p => {
        if (q) {
          const hay = (p.title || '').toLowerCase() + ' ' + (p.description || '').toLowerCase();
          if (!hay.includes(q)) return false;
        }
        if (!this.matchesFilter(p, this.activeFilter)) return false;
        return true;
      });
    },
    matchesFilter(p, f) {
      if (f === 'all') return true;
      if (f === 'active')   return (p.assigned_count || 0) > 0;
      if (f === 'template') return p.is_template === true;
      if (f === 'draft')    return (p.status || '').toUpperCase() === 'DRAFT';
      return true;
    },
    get filterCounts() {
      const all = this.plans;
      return {
        all:      all.length,
        active:   all.filter(p => this.matchesFilter(p, 'active')).length,
        template: all.filter(p => this.matchesFilter(p, 'template')).length,
        draft:    all.filter(p => this.matchesFilter(p, 'draft')).length,
      };
    },
    emptyTitle() {
      if (this.selectedFolderId === 'all' && !this.search) return 'Nessun piano creato';
      return 'Nessun risultato';
    },
    emptyDescription() {
      if (this.selectedFolderId === 'all' && !this.search) {
        return 'Crea il tuo primo piano alimentare e assegnalo agli atleti.';
      }
      return 'Nessun piano corrisponde ai filtri attivi.';
    },
    newPlanUrl() {
      const fid = (typeof this.selectedFolderId === 'number') ? this.selectedFolderId : '';
      return fid ? (this.urls.planCreate + '?folder_id=' + fid) : this.urls.planCreate;
    },
    filteredClients() {
      const q = this.clientSearch.toLowerCase();
      const plan = this.plans.find(p => p.id === this.assignPlanId);
      const blocked = new Set(plan ? (plan.assigned_client_ids || []) : []);
      return this.clientsAll
        .filter(c => !blocked.has(c.id))
        .filter(c => !q || c.name.toLowerCase().includes(q));
    },

    /* === new-plan modal === */
    openNewPlanModal() {
      this.newPlanKind = null;
      this.newPlanMode = 'FOOD';
      this.newPlanModal = true;
    },
    selectKind(k) { this.newPlanKind = k; },
    selectMode(m) { this.newPlanMode = m; },
    continueNewPlan() {
      if (!this.newPlanKind) return;
      const fid = (typeof this.selectedFolderId === 'number') ? this.selectedFolderId : '';
      const params = new URLSearchParams();
      params.set('kind', this.newPlanKind);
      if (this.newPlanMode && this.newPlanMode !== 'FOOD') params.set('mode', this.newPlanMode);
      if (fid) params.set('folder_id', fid);
      window.location.href = this.urls.planCreate + '?' + params.toString();
    },

    /* === folders === */
    startCreateFolder() {
      this.creatingFolder = true;
      this.folderCreateDraft = '';
      this.$nextTick(() => this.$refs.folderCreateInput?.focus());
    },
    cancelCreateFolder() {
      this.creatingFolder = false;
      this.folderCreateDraft = '';
    },
    async finishCreateFolder() {
      const title = (this.folderCreateDraft || '').trim();
      if (!title) { this.cancelCreateFolder(); return; }
      try {
        const res = await fetch(this.urls.folders, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': nutCsrfToken() },
          body: JSON.stringify({ title }),
        });
        const data = await res.json();
        if (!res.ok) { Alpine.store('toasts').push({ kind: 'danger', msg: data.error || 'Errore' }); return; }
        this.folders.push(data);
        this.selectedFolderId = data.id;
      } catch (e) {
        Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete.' });
      }
      this.cancelCreateFolder();
    },

    startEditFolder(folder) {
      this.editingFolderId = folder.id;
      this.folderEditDraft = folder.title;
      this.$nextTick(() => this.$refs.folderEditInput?.focus());
    },
    cancelEditFolder() {
      this.editingFolderId = null;
      this.folderEditDraft = '';
    },
    async finishEditFolder(folder) {
      const newTitle = (this.folderEditDraft || '').trim();
      if (!newTitle || newTitle === folder.title) { this.cancelEditFolder(); return; }
      try {
        const res = await fetch(this.urls.folderDetail.replace('__ID__', folder.id), {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': nutCsrfToken() },
          body: JSON.stringify({ title: newTitle }),
        });
        const data = await res.json();
        if (!res.ok) { Alpine.store('toasts').push({ kind: 'danger', msg: data.error || 'Errore' }); this.cancelEditFolder(); return; }
        folder.title = data.title;
      } catch (e) { Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete.' }); }
      this.cancelEditFolder();
    },

    openFolderMenu(folder) {
      this.menuFolder = this.menuFolder === folder ? null : folder;
    },
    async patchFolderLabel(folder) {
      try {
        await fetch(this.urls.folderDetail.replace('__ID__', folder.id), {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': nutCsrfToken() },
          body: JSON.stringify({ label_text: folder.label_text || '' }),
        });
      } catch (e) { /* swallow */ }
    },
    async setFolderColor(folder, color) {
      folder.label_color = color;
      try {
        await fetch(this.urls.folderDetail.replace('__ID__', folder.id), {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': nutCsrfToken() },
          body: JSON.stringify({ label_color: color }),
        });
      } catch (e) { /* swallow */ }
    },
    confirmDeleteFolder(folder) {
      this.folderToDelete = folder;
      this.deleteFolderOpen = true;
      this.deleteFolderAction = 'move_to_unfiled';
      this.deleteFolderTarget = '';
      this.menuFolder = null;
    },
    async executeFolderDelete() {
      if (!this.folderToDelete) return;
      let url = this.urls.folderDetail.replace('__ID__', this.folderToDelete.id);
      const params = new URLSearchParams();
      params.set('action', this.deleteFolderAction);
      if (this.deleteFolderAction === 'move_to' && this.deleteFolderTarget) {
        params.set('target_folder_id', this.deleteFolderTarget);
      }
      url += '?' + params.toString();
      try {
        const res = await fetch(url, {
          method: 'DELETE',
          headers: { 'X-CSRFToken': nutCsrfToken() },
        });
        if (!res.ok) {
          const data = await res.json();
          Alpine.store('toasts').push({ kind: 'danger', msg: data.error || 'Errore' });
          return;
        }
        const deletedId = this.folderToDelete.id;
        if (this.deleteFolderAction === 'delete_plans') {
          this.plans = this.plans.filter(p => p.folder_id !== deletedId);
        } else if (this.deleteFolderAction === 'move_to_unfiled') {
          this.plans.forEach(p => { if (p.folder_id === deletedId) p.folder_id = null; });
        } else {
          const tid = parseInt(this.deleteFolderTarget, 10);
          this.plans.forEach(p => { if (p.folder_id === deletedId) p.folder_id = tid; });
          const tgt = this.folders.find(f => f.id === tid);
          if (tgt) tgt.plan_count = this.plans.filter(p => p.folder_id === tid).length;
        }
        this.folders = this.folders.filter(f => f.id !== deletedId);
        if (this.selectedFolderId === deletedId) this.selectedFolderId = 'all';
      } catch (e) { Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete.' }); }
      this.deleteFolderOpen = false;
      this.folderToDelete = null;
    },

    /* === drag & drop === */
    /* Drop su una cartella: o sto riordinando le cartelle (drag della voce
       sidebar) o sto archiviando un piano (drag della card). */
    handleFolderDrop(folderId) {
      if (this.draggedFolderId) {
        if (folderId && this.draggedFolderId !== folderId) this.reorderFolders(folderId);
        this.draggedFolderId = null;
        this.dropTargetId = null;
        return;
      }
      this.dropPlanOnFolder(folderId);
    },
    async reorderFolders(targetId) {
      const srcIdx = this.folders.findIndex(f => f.id === this.draggedFolderId);
      const tgtIdx = this.folders.findIndex(f => f.id === targetId);
      if (srcIdx === -1 || tgtIdx === -1) return;
      const moved = this.folders.splice(srcIdx, 1)[0];
      this.folders.splice(tgtIdx, 0, moved);
      try {
        const res = await fetch(this.urls.foldersReorder, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': nutCsrfToken() },
          body: JSON.stringify({ ids: this.folders.map(f => f.id) }),
        });
        if (!res.ok) throw new Error('save');
      } catch (e) {
        Alpine.store('toasts').push({ kind: 'danger', msg: 'Riordino non salvato. Riprova.' });
      }
    },
    async dropPlanOnFolder(folderId) {
      this.dropTargetId = null;
      const pid = this.draggedPlanId;
      this.draggedPlanId = null;
      if (!pid) return;
      const plan = this.plans.find(p => p.id === pid);
      if (!plan) return;
      const previousFolderId = plan.folder_id;
      if (previousFolderId === folderId) return;
      plan.folder_id = folderId;
      try {
        const res = await fetch(this.urls.planFolder.replace('__ID__', pid), {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': nutCsrfToken() },
          body: JSON.stringify({ folder_id: folderId }),
        });
        if (!res.ok) throw new Error('save');
        if (previousFolderId) {
          const f = this.folders.find(f => f.id === previousFolderId);
          if (f) f.plan_count = Math.max(0, f.plan_count - 1);
        }
        if (folderId) {
          const f = this.folders.find(f => f.id === folderId);
          if (f) f.plan_count += 1;
        }
      } catch (e) { plan.folder_id = previousFolderId; Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete.' }); }
    },

    /* === assign === */
    openAssign(id, name) {
      this.assignPlanId = id;
      this.assignPlanName = name;
      this.clientSearch = ''; this.selectedClient = null;
      this.startDate = ''; this.endDate = ''; this.assignNotes = '';
      this.successFlash = false;
      this.assignModal = true;
    },
    async submitAssign() {
      if (!this.selectedClient) return;
      this.saving = true;
      const res = await fetch(this.urls.planAssign.replace('__ID__', this.assignPlanId), {
        method: 'POST',
        headers: {'Content-Type': 'application/json', 'X-CSRFToken': nutCsrfToken()},
        body: JSON.stringify({
          client_id: this.selectedClient.id,
          start_date: this.startDate || null,
          end_date: this.endDate || null,
          notes: this.assignNotes,
        })
      });
      this.saving = false;
      if (res.ok) {
        const plan = this.plans.find(p => p.id === this.assignPlanId);
        if (plan) {
          plan.assigned_count += 1;
          if (!plan.assigned_client_ids) plan.assigned_client_ids = [];
          if (!plan.assigned_client_ids.includes(this.selectedClient.id)) {
            plan.assigned_client_ids.push(this.selectedClient.id);
          }
        }
        this.successFlash = true;
        setTimeout(() => {
          this.assignModal = false;
          this.successFlash = false;
        }, 700);
      } else {
        Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore durante l\'assegnazione.' });
      }
    },

    /* === delete plan === */
    async openDelete(id) {
      const plan = this.plans.find(p => p.id === id);
      const assignedCount = plan ? (plan.assigned_count || 0) : 0;
      const assigned = assignedCount > 0;
      if (!(await window.alConfirm({
        icon: 'ph-trash',
        title: 'Eliminare il\npiano?',
        subtitle: assigned
          ? 'Attenzione: il piano è assegnato a ' + assignedCount + (assignedCount === 1 ? ' atleta' : ' atleti')
            + '. Verrà rimosso anche dal loro profilo e riceveranno un messaggio automatico in chat (personalizzabile da Impostazioni → Messaggi automatici).'
          : 'Verranno eliminati tutti i pasti e gli alimenti associati. Operazione irreversibile.',
        confirmLabel: assigned ? 'Sì, elimina e avvisa' : 'Sì, elimina',
      }))) return;
      this.deletePlanId = id;
      await this.confirmDelete();
    },
    async confirmDelete() {
      try {
        const res = await fetch(this.urls.planDelete.replace('__ID__', this.deletePlanId), {
          method: 'POST', headers: {'X-CSRFToken': nutCsrfToken()}
        });
        if (!res.ok) {
          const data = await res.json().catch(() => ({}));
          Alpine.store('toasts').push({ kind: 'danger', msg: data.error || 'Errore eliminazione.' });
          return;
        }
        const deletedId = this.deletePlanId;
        const plan = this.plans.find(p => p.id === deletedId);
        if (plan && plan.folder_id) {
          const f = this.folders.find(f => f.id === plan.folder_id);
          if (f) f.plan_count = Math.max(0, f.plan_count - 1);
        }
        this.plans = this.plans.filter(p => p.id !== deletedId);
        this.deleteModal = false;
      } catch (e) {
        Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete.' });
      }
    },

    /* === duplicate plan === */
    async duplicatePlan(id) {
      if (this.duplicatingId) return;
      this.duplicatingId = id;
      try {
        const res = await fetch(this.urls.planDuplicate.replace('__ID__', id), {
          method: 'POST', headers: {'X-CSRFToken': nutCsrfToken()}
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok) {
          Alpine.store('toasts').push({ kind: 'danger', msg: data.error || 'Errore duplicazione.' });
          return;
        }
        // Open the new draft straight in the editor so the coach can tweak it.
        window.location.href = this.urls.planEdit.replace('__ID__', data.id);
      } catch (e) {
        Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete.' });
      } finally {
        this.duplicatingId = null;
      }
    },

    /* === utils === */
    relativeTime(iso) {
      if (!iso) return '';
      const date = new Date(iso);
      const diff = Math.floor((Date.now() - date.getTime()) / 1000);
      if (diff < 60) return 'adesso';
      if (diff < 3600) return Math.floor(diff/60) + ' min fa';
      if (diff < 86400) return Math.floor(diff/3600) + ' h fa';
      if (diff < 604800) return Math.floor(diff/86400) + ' g fa';
      return date.toLocaleDateString('it-IT', { day: '2-digit', month: 'short' });
    },
  };
}

window.nutritionLibrary = nutritionLibrary;
window.nutCsrfToken = window.nutCsrfToken || nutCsrfToken;
