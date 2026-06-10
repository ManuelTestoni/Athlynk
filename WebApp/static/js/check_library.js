/* Athlynk · Check · Modelli hub
   Alpine factory backing pages/check/templates_list.html.
   Source data is bootstrapped via window.CHECK_LIBRARY_INIT in the template. */

function chkCsrfToken() {
  return document.cookie.split('; ').find(r => r.startsWith('csrftoken='))?.split('=')[1]
    || (window.CHECK_LIBRARY_INIT && window.CHECK_LIBRARY_INIT.csrf)
    || '';
}

function checkLibrary() {
  return {
    /* === state === */
    templates: window.CHECK_LIBRARY_INIT.templates || [],
    folders: window.CHECK_LIBRARY_INIT.folders || [],
    urls: window.CHECK_LIBRARY_INIT.urls,
    search: '',
    selectedFolderId: 'all',
    availableLabelColors: ['bronze','aegean','amber','emerald','rose','violet','slate','sand','crimson','teal'],

    /* drag */
    draggedTemplateId: null,
    dropTargetId: null,
    draggedFolderId: null,

    /* folder edit */
    editingFolderId: null,
    folderEditDraft: '',
    creatingFolder: false,
    folderCreateDraft: '',
    menuFolder: null,

    /* delete folder */
    deleteFolderOpen: false,
    folderToDelete: null,
    deleteFolderAction: 'move_to_unfiled',
    deleteFolderTarget: '',

    /* delete template */
    deleteModal: false,
    deleteTemplateId: null,

    init() {},

    /* === selectors === */
    selectFolder(id) { this.selectedFolderId = id; },
    templatesInFolder() {
      if (this.selectedFolderId === 'all') return this.templates;
      if (this.selectedFolderId === 'unfiled') return this.templates.filter(t => !t.folder_id);
      return this.templates.filter(t => t.folder_id === this.selectedFolderId);
    },
    visibleTemplates() {
      const q = (this.search || '').toLowerCase().trim();
      return this.templatesInFolder().filter(t => {
        if (!q) return true;
        const hay = (t.title || '').toLowerCase() + ' ' + (t.description || '').toLowerCase();
        return hay.includes(q);
      });
    },
    emptyTitle() {
      if (this.selectedFolderId === 'all' && !this.search) return 'Nessun modello personale';
      return 'Nessun risultato';
    },
    emptyDescription() {
      if (this.selectedFolderId === 'all' && !this.search) {
        return 'Crea il tuo primo modello di check oppure duplica un preset.';
      }
      return 'Nessun modello corrisponde alla cartella o alla ricerca.';
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
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': chkCsrfToken() },
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
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': chkCsrfToken() },
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
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': chkCsrfToken() },
          body: JSON.stringify({ label_text: folder.label_text || '' }),
        });
      } catch (e) { /* swallow */ }
    },
    async setFolderColor(folder, color) {
      folder.label_color = color;
      try {
        await fetch(this.urls.folderDetail.replace('__ID__', folder.id), {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': chkCsrfToken() },
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
          headers: { 'X-CSRFToken': chkCsrfToken() },
        });
        if (!res.ok) {
          const data = await res.json();
          Alpine.store('toasts').push({ kind: 'danger', msg: data.error || 'Errore' });
          return;
        }
        const deletedId = this.folderToDelete.id;
        if (this.deleteFolderAction === 'delete_templates') {
          this.templates = this.templates.filter(t => t.folder_id !== deletedId);
        } else if (this.deleteFolderAction === 'move_to_unfiled') {
          this.templates.forEach(t => { if (t.folder_id === deletedId) t.folder_id = null; });
        } else {
          const tid = parseInt(this.deleteFolderTarget, 10);
          this.templates.forEach(t => { if (t.folder_id === deletedId) t.folder_id = tid; });
          const tgt = this.folders.find(f => f.id === tid);
          if (tgt) tgt.template_count = this.templates.filter(t => t.folder_id === tid).length;
        }
        this.folders = this.folders.filter(f => f.id !== deletedId);
        if (this.selectedFolderId === deletedId) this.selectedFolderId = 'all';
      } catch (e) { Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete.' }); }
      this.deleteFolderOpen = false;
      this.folderToDelete = null;
    },

    /* === drag & drop === */
    /* Drop su una cartella: o sto riordinando le cartelle (drag della voce
       sidebar) o sto archiviando un template (drag della card). */
    handleFolderDrop(folderId) {
      if (this.draggedFolderId) {
        if (folderId && this.draggedFolderId !== folderId) this.reorderFolders(folderId);
        this.draggedFolderId = null;
        this.dropTargetId = null;
        return;
      }
      this.dropTemplateOnFolder(folderId);
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
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': chkCsrfToken() },
          body: JSON.stringify({ ids: this.folders.map(f => f.id) }),
        });
        if (!res.ok) throw new Error('save');
      } catch (e) {
        Alpine.store('toasts').push({ kind: 'danger', msg: 'Riordino non salvato. Riprova.' });
      }
    },
    async dropTemplateOnFolder(folderId) {
      this.dropTargetId = null;
      const tid = this.draggedTemplateId;
      this.draggedTemplateId = null;
      if (!tid) return;
      const tpl = this.templates.find(t => t.id === tid);
      if (!tpl) return;
      const previousFolderId = tpl.folder_id;
      if (previousFolderId === folderId) return;
      tpl.folder_id = folderId;
      try {
        const res = await fetch(this.urls.templateFolder.replace('__ID__', tid), {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': chkCsrfToken() },
          body: JSON.stringify({ folder_id: folderId }),
        });
        if (!res.ok) throw new Error('save');
        if (previousFolderId) {
          const f = this.folders.find(f => f.id === previousFolderId);
          if (f) f.template_count = Math.max(0, f.template_count - 1);
        }
        if (folderId) {
          const f = this.folders.find(f => f.id === folderId);
          if (f) f.template_count += 1;
        }
      } catch (e) { tpl.folder_id = previousFolderId; Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete.' }); }
    },

    /* === template actions === */
    async duplicate(id) {
      const csrf = chkCsrfToken();
      try {
        const res = await fetch(this.urls.templateDuplicate.replace('__ID__', id), {
          method: 'POST', headers: { 'X-CSRFToken': csrf },
        });
        const data = await res.json();
        if (data.success) { window.location.reload(); }
        else { Alpine.store('toasts').push({ kind: 'danger', msg: data.error || 'Errore' }); }
      } catch (e) { Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete' }); }
    },
    async restore(id) {
      if (!await window.alConfirm({ variant: 'neutral', icon: 'ph-arrow-counter-clockwise', title: 'Ripristinare il\nmodello?', subtitle: 'Tornerà alla configurazione di base. Le modifiche andranno perse.', confirmLabel: 'Sì, ripristina' })) return;
      const csrf = chkCsrfToken();
      try {
        const res = await fetch(this.urls.templateRestore.replace('__ID__', id), {
          method: 'POST', headers: { 'X-CSRFToken': csrf },
        });
        const data = await res.json();
        if (data.success) { window.location.reload(); }
        else { Alpine.store('toasts').push({ kind: 'danger', msg: data.error || 'Errore' }); }
      } catch (e) { Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete' }); }
    },
    openDelete(id) { this.deleteTemplateId = id; this.deleteModal = true; },
    async confirmDelete() {
      const id = this.deleteTemplateId;
      try {
        const res = await fetch(this.urls.templateDelete.replace('__ID__', id), {
          method: 'POST', headers: { 'X-CSRFToken': chkCsrfToken() },
        });
        const data = await res.json();
        if (!data.success) { Alpine.store('toasts').push({ kind: 'danger', msg: data.error || 'Errore' }); return; }
        const tpl = this.templates.find(t => t.id === id);
        if (tpl && tpl.folder_id) {
          const f = this.folders.find(f => f.id === tpl.folder_id);
          if (f) f.template_count = Math.max(0, f.template_count - 1);
        }
        this.templates = this.templates.filter(t => t.id !== id);
        this.deleteModal = false;
      } catch (e) { Alpine.store('toasts').push({ kind: 'danger', msg: 'Errore di rete' }); }
    },

    editUrl(id) { return this.urls.templateEdit.replace('__ID__', id); },
  };
}

window.checkLibrary = checkLibrary;
window.chkCsrfToken = window.chkCsrfToken || chkCsrfToken;
