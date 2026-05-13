function globalSearch() {
  return {
    q: '',
    results: [],
    groups: [],
    open: false,
    loading: false,
    focused: false,
    activeIndex: -1,

    async run() {
      const q = this.q.trim();
      if (q.length < 2) {
        this.results = [];
        this.groups = [];
        this.open = false;
        return;
      }
      this.loading = true;
      try {
        const r = await fetch(`/api/search/?q=${encodeURIComponent(q)}`, {
          headers: { 'Accept': 'application/json' },
        });
        if (r.ok) {
          const data = await r.json();
          this.results = data.results || [];
          this.groups = data.groups || [];
          this.open = true;
          this.activeIndex = -1;
        }
      } catch (e) {
        this.results = [];
        this.groups = [];
      } finally {
        this.loading = false;
      }
    },

    resultsForGroup(group) {
      return this.results.filter(r => r.group === group);
    },

    onFocus() {
      this.focused = true;
      if (this.results.length) this.open = true;
    },

    close() {
      this.open = false;
      this.focused = false;
    },

    go(url) {
      if (url) window.location.href = url;
    },

    onKeyDown(e) {
      if (!this.open || !this.results.length) return;
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        this.activeIndex = Math.min(this.activeIndex + 1, this.results.length - 1);
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        this.activeIndex = Math.max(this.activeIndex - 1, 0);
      } else if (e.key === 'Enter') {
        if (this.activeIndex >= 0 && this.results[this.activeIndex]) {
          e.preventDefault();
          this.go(this.results[this.activeIndex].url);
        }
      } else if (e.key === 'Escape') {
        this.close();
      }
    },
  };
}
window.globalSearch = globalSearch;
