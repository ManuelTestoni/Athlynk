function notificationsBell() {
    return {
        open: false,
        unreadCount: 0,
        notifications: [],
        pollInterval: null,

        init() {
            this.fetchUnreadCount();
            this.pollInterval = setInterval(() => this.fetchUnreadCount(), 15000);
        },

        async fetchUnreadCount() {
            try {
                const r = await fetch('/api/notifications/unread-count/');
                if (r.ok) {
                    const d = await r.json();
                    this.unreadCount = d.count || 0;
                }
            } catch (e) { /* silent */ }
        },

        async fetchList() {
            try {
                const r = await fetch('/api/notifications/');
                if (r.ok) {
                    const d = await r.json();
                    this.notifications = d.notifications || [];
                }
            } catch (e) { /* silent */ }
        },

        toggleOpen() {
            this.open = !this.open;
            if (this.open) this.fetchList();
        },

        getCsrf() {
            return window.csrfToken();
        },

        async markRead(id) {
            try {
                await fetch(`/api/notifications/${id}/read/`, {
                    method: 'POST',
                    headers: { 'X-CSRFToken': this.getCsrf() },
                });
                const n = this.notifications.find(x => x.id === id);
                if (n && !n.is_read) {
                    n.is_read = true;
                    this.unreadCount = Math.max(0, this.unreadCount - 1);
                }
            } catch (e) { /* silent */ }
        },

        async markAllRead() {
            try {
                await fetch('/api/notifications/read-all/', {
                    method: 'POST',
                    headers: { 'X-CSRFToken': this.getCsrf() },
                });
                this.notifications.forEach(n => n.is_read = true);
                this.unreadCount = 0;
            } catch (e) { /* silent */ }
        },

        formatTime(iso) {
            const d = new Date(iso);
            const now = new Date();
            const diffMs = now - d;
            const diffMin = Math.floor(diffMs / 60000);
            if (diffMin < 1) return 'Adesso';
            if (diffMin < 60) return `${diffMin}m fa`;
            const diffH = Math.floor(diffMin / 60);
            if (diffH < 24) return `${diffH}h fa`;
            return d.toLocaleDateString('it-IT', { day: '2-digit', month: 'short' });
        },

        getIcon(type) {
            switch (type) {
                case 'MESSAGE': return 'ph-fill ph-chat-circle text-blue-500';
                case 'APPOINTMENT_REQUEST': return 'ph-fill ph-calendar-plus text-amber-500';
                case 'APPOINTMENT_ACCEPTED': return 'ph-fill ph-calendar-check text-emerald-500';
                case 'APPOINTMENT_REJECTED': return 'ph-fill ph-calendar-x text-red-500';
                default: return 'ph-fill ph-bell text-slate-500';
            }
        },

        getIconBg(type) {
            switch (type) {
                case 'MESSAGE': return 'bg-blue-100';
                case 'APPOINTMENT_REQUEST': return 'bg-amber-100';
                case 'APPOINTMENT_ACCEPTED': return 'bg-emerald-100';
                case 'APPOINTMENT_REJECTED': return 'bg-red-100';
                default: return 'bg-slate-100';
            }
        },
    };
}
