/* check_progress.js — Athlynk
   Modulo antropometrico (peso / circonferenze / pliche).

   Il dato singolo è rumore: ogni punto del grafico è la MEDIA SETTIMANALE
   delle misurazioni (lunedì→domenica). Asse X = calendario settimanale
   CONTINUO dalla prima all'ultima settimana misurata: ogni settimana ha il
   suo tick S1, S2, S3, S4… (progressivo nel mese, riparte a ogni mese),
   anche se non contiene misurazioni. La linea resta sulle medie
   settimanali e attraversa le settimane vuote senza interruzioni
   (nessuna interpolazione: nessun punto dove non ci sono dati).

   Vista: la card inquadra l'ultimo mese di settimane (default) oppure gli
   ultimi 3 mesi (toggle 1M/3M); lo storico precedente resta sulla stessa
   tela e si esplora trascinando col mouse (drag) o con trackpad/swipe.

   Selezione: click su un punto → quella settimana diventa il numero
   principale della card (media, n rilevazioni, delta vs settimana
   precedente). Default: l'ultima settimana.

   Il confronto è sempre con la settimana cronologicamente precedente
   (sulla serie completa, anche se la finestra la nasconde):
     delta_sett = media_settimana − media_settimana_precedente
   Il tooltip di ogni punto mostra media, delta e le singole rilevazioni
   usate per calcolarla.

   Formule: media_settimanale = Σ misurazioni settimana / n misurazioni.

   Dipendenze: Chart.js (base.html), Alpine.js.
   Dati: window._chartData — { dates[], weight[], circumferences{}, skinfolds{} … }
   prodotti da _build_chart_data (views_check/helpers.py). */
(function () {
  'use strict';

  /* ===================== date utils ===================== */

  var MESI_SHORT = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];
  var MESI_FULL = ['Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
                   'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'];
  var GIORNI = ['dom', 'lun', 'mar', 'mer', 'gio', 'ven', 'sab']; // Date.getDay()

  function parseISO(s) {
    var p = s.split('-');
    return new Date(+p[0], +p[1] - 1, +p[2]);
  }
  function toISO(d) {
    return d.getFullYear() + '-' +
      String(d.getMonth() + 1).padStart(2, '0') + '-' +
      String(d.getDate()).padStart(2, '0');
  }
  function mondayOf(d) {
    var x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    x.setDate(x.getDate() - ((x.getDay() + 6) % 7));
    return x;
  }
  function ddmm(d) {
    return String(d.getDate()).padStart(2, '0') + '/' + String(d.getMonth() + 1).padStart(2, '0');
  }
  // Settimana del mese: 1–7 → S1, 8–14 → S2, 15–21 → S3, 22–28 → S4, 29–31 → S5.
  function weekOfMonth(d) { return Math.floor((d.getDate() - 1) / 7) + 1; }

  /* ===================== aggregation ===================== */

  function stat(entry) {
    var sum = 0, lo = Infinity, hi = -Infinity;
    entry.raw.forEach(function (p) {
      sum += p.v;
      if (p.v < lo) lo = p.v;
      if (p.v > hi) hi = p.v;
    });
    entry.mean = sum / entry.raw.length;
    entry.n = entry.raw.length;
    entry.min = lo;
    entry.max = hi;
    return entry;
  }

  // points [{d:Date, v:Number}] → calendario settimanale CONTINUO dalla prima
  // all'ultima settimana misurata. Le settimane senza dati hanno mean=null
  // (nessun punto sul grafico, ma tick visibile). Ogni entry porta il numero
  // progressivo nel mese (wom) + mese/anno del lunedì.
  function aggregateWeeks(points) {
    var map = {};
    points.forEach(function (p) {
      var mon = mondayOf(p.d);
      var k = toISO(mon);
      if (!map[k]) map[k] = { key: k, monday: mon, raw: [] };
      map[k].raw.push(p);
    });
    var keys = Object.keys(map).sort();
    if (!keys.length) return [];
    var out = [];
    var cur = parseISO(keys[0]);
    var last = parseISO(keys[keys.length - 1]);
    while (cur <= last) {
      var k = toISO(cur);
      var e = map[k] ? stat(map[k])
        : { key: k, monday: new Date(cur), raw: [], mean: null, n: 0, min: null, max: null };
      e.wom = weekOfMonth(e.monday);
      e.month = e.monday.getMonth();
      e.year = e.monday.getFullYear();
      e.start = e.monday;
      e.cmpLabel = 'S' + e.wom + ' ' + MESI_SHORT[e.month];
      e.title = 'Settimana ' + e.wom + ' · ' + MESI_FULL[e.month] + ' ' + e.year;
      out.push(e);
      cur = new Date(cur);
      cur.setDate(cur.getDate() + 7);
    }
    return out;
  }

  // Settimana precedente CON dati (per i delta: le settimane vuote non contano).
  function prevWithData(entries, idx) {
    for (var j = idx - 1; j >= 0; j--) {
      if (entries[j].n > 0) return entries[j];
    }
    return null;
  }

  // Etichette asse X: 'S{n}' progressivo nel mese; il nome del mese appare
  // come seconda riga al primo punto e a ogni cambio di mese (anno se cambia).
  function tickLines(entries) {
    return entries.map(function (e, i) {
      var prev = entries[i - 1];
      var newMonth = !prev || prev.month !== e.month || prev.year !== e.year;
      if (!newMonth) return ['S' + e.wom];
      var m = MESI_SHORT[e.month];
      if (prev && prev.year !== e.year) m += ' ' + String(e.year).slice(2);
      return ['S' + e.wom, m];
    });
  }

  /* ===================== formatting ===================== */

  function fmtNum(v, dec) {
    if (v === null || v === undefined) return '—';
    if (dec === undefined) dec = 1;
    return v.toLocaleString('it-IT', { minimumFractionDigits: dec, maximumFractionDigits: dec });
  }
  function fmtDelta(d, unit) {
    if (d === null || d === undefined) return null;
    var r = Math.round(d * 10) / 10;
    var sign = r > 0 ? '+' : r < 0 ? '−' : '±';
    return sign + fmtNum(Math.abs(r)) + ' ' + unit + '/sett';
  }

  /* ===================== chart styling ===================== */

  var INK = '#14110d';
  var LABEL = '#5b554a';
  var GRID = 'rgba(91,85,74,0.10)';
  var CREAM = '#f4efe4';
  var COLORS = { weight: '#8a6a3a', circ: '#1c4a52', skin: '#8a6a3a' };
  var MIN_PX_POINT = 34;   // spaziatura minima tra punti (leggibilità tick)

  function yBounds(values, pad) {
    if (!values.length) return null;
    var lo = Math.min.apply(null, values), hi = Math.max.apply(null, values);
    return { min: Math.max(0, Math.floor(lo - pad)), max: Math.ceil(hi + pad) };
  }

  function gradientFill(color) {
    return function (ctx) {
      var area = ctx.chart.chartArea;
      var c = ctx.chart.ctx;
      if (!area) return color + '20';
      var g = c.createLinearGradient(0, area.top, 0, area.bottom);
      g.addColorStop(0, color + '34');
      g.addColorStop(1, color + '02');
      return g;
    };
  }

  // Drag-to-pan: trascinando col mouse si esplora la timeline. Un drag oltre
  // la soglia sopprime il click successivo, così la selezione del punto non
  // scatta a fine trascinamento. Wiring una sola volta per scroller.
  function wireDragPan(scroller) {
    if (scroller._dragWired) return;
    scroller._dragWired = true;
    scroller._dragMoved = false;
    var down = false, startX = 0, startScroll = 0;

    scroller.addEventListener('mousedown', function (e) {
      down = true;
      scroller._dragMoved = false;
      startX = e.clientX;
      startScroll = scroller.scrollLeft;
    });
    window.addEventListener('mousemove', function (e) {
      if (!down) return;
      var dx = e.clientX - startX;
      if (Math.abs(dx) > 4) {
        scroller._dragMoved = true;
        scroller.style.cursor = 'grabbing';
      }
      scroller.scrollLeft = startScroll - dx;
    });
    window.addEventListener('mouseup', function () {
      if (!down) return;
      down = false;
      scroller.style.cursor = '';
      // _dragMoved resta alzato fino al PROSSIMO mousedown: ogni click è
      // sempre preceduto da un mousedown, quindi la soppressione copre il
      // click di fine drag senza corse con i timer.
    });
  }

  /* ===================== Alpine component ===================== */

  window.anthroCard = function (kind) {
    var D = window._chartData || {};
    var chart = null; // istanza Chart.js fuori da Alpine (il Proxy rompe .update())

    return {
      kind: kind,
      unit: kind === 'weight' ? 'kg' : kind === 'circ' ? 'cm' : 'mm',
      color: COLORS[kind],
      zoom: 1,    // mesi inquadrati dalla card: 1 (default) o 3 — sempre scorribile
      selIdx: -1, // indice del punto selezionato (-1 → ultima settimana)
      measureKey: '',
      measureKeys: [],
      measureLabels: {},
      weeks: [],
      hasData: false,
      ready: false,
      summary: { mean: null, n: 0, deltaVal: null, deltaTxt: null, cmpLabel: '', periodLabel: '' },

      init() {
        if (kind === 'circ') {
          this.measureKeys = D.circ_keys || [];
          this.measureLabels = D.circ_labels || {};
        } else if (kind === 'skin') {
          var keys = (D.skin_keys || []).slice();
          var labels = Object.assign({}, D.skin_labels || {});
          if (keys.length >= 2) {
            keys.unshift('__sum');
            labels.__sum = 'Somma pliche';
          }
          this.measureKeys = keys;
          this.measureLabels = labels;
        }
        if (this.measureKeys.length) this.measureKey = this.firstKeyWithData();
        this.rebuild();
        // leggero ritardo: lo skeleton viene percepito, poi il grafico anima in entrata
        var self = this;
        setTimeout(function () { self.ready = true; self.render(); }, 260);
      },

      firstKeyWithData() {
        for (var i = 0; i < this.measureKeys.length; i++) {
          if (this.rawSeries(this.measureKeys[i]).some(function (v) { return v !== null && v !== undefined; }))
            return this.measureKeys[i];
        }
        return this.measureKeys[0];
      },

      rawSeries(key) {
        if (this.kind === 'weight') return D.weight || [];
        if (this.kind === 'circ') return (D.circumferences || {})[key] || [];
        if (key === '__sum') {
          var skinKeys = D.skin_keys || [];
          return (D.dates || []).map(function (_, i) {
            var sum = 0, any = false;
            skinKeys.forEach(function (k) {
              var v = ((D.skinfolds || {})[k] || [])[i];
              if (v !== null && v !== undefined) { sum += v; any = true; }
            });
            return any ? Math.round(sum * 10) / 10 : null;
          });
        }
        return (D.skinfolds || {})[key] || [];
      },

      points() {
        var series = this.rawSeries(this.measureKey);
        var out = [];
        (D.dates || []).forEach(function (ds, i) {
          var v = series[i];
          if (v !== null && v !== undefined) out.push({ d: parseISO(ds), v: v });
        });
        return out;
      },

      /* ---- (ri)costruzione aggregati: alla init e al cambio misura ---- */
      rebuild() {
        var pts = this.points();
        this.hasData = pts.length > 0;
        this.weeks = aggregateWeeks(pts);
        this.selIdx = -1;
        this.recalc();
        if (this.ready) this.render();
      },

      // Ampiezza della finestra inquadrata (1 o 3 mesi); la selezione resta.
      setZoom(z) {
        if (this.zoom === z) return;
        this.zoom = z;
        this.render();
      },

      /* ---- riepilogo: settimana selezionata vs precedente cronologica ---- */
      recalc() {
        var s = this.summary;
        s.mean = null; s.n = 0; s.deltaVal = null; s.deltaTxt = null; s.cmpLabel = ''; s.periodLabel = '';
        if (!this.hasData) return;

        var entries = this.weeks;
        if (!entries.length) return;
        // selezione valida solo su settimane con dati; default: l'ultima misurata
        if (this.selIdx < 0 || this.selIdx >= entries.length || entries[this.selIdx].n === 0) {
          for (var j = entries.length - 1; j >= 0; j--) {
            if (entries[j].n > 0) { this.selIdx = j; break; }
          }
        }

        var e = entries[this.selIdx];
        var prev = prevWithData(entries, this.selIdx);

        s.mean = e.mean;
        s.n = e.n;
        s.periodLabel = e.cmpLabel;
        if (prev) {
          s.deltaVal = e.mean - prev.mean;
          s.deltaTxt = fmtDelta(s.deltaVal, this.unit);
          s.cmpLabel = 'vs ' + prev.cmpLabel;
        }
      },

      // Click su un punto → quella settimana diventa il numero principale.
      select(i) {
        if (!this.weeks[i] || this.weeks[i].n === 0) return; // settimane vuote: non selezionabili
        this.selIdx = i;
        this.recalc();
        if (!chart) return;
        var color = this.color;
        var entries = this.weeks;
        var ds = chart.data.datasets[1]; // [0]=rilevazioni grezze, [1]=linea medie
        ds.pointRadius = entries.map(function (e, j) { return e.n === 0 ? 0 : j === i ? 6 : 3; });
        ds.pointBackgroundColor = entries.map(function (_, j) { return j === i ? color : color + 'bb'; });
        chart.update();
      },

      /* ---- formatting helpers for the template ---- */
      fmt(v, dec) { return fmtNum(v, dec); },
      deltaClass() {
        var d = this.summary.deltaVal;
        if (d === null || Math.round(d * 10) === 0) return 'pc-delta-flat';
        return d > 0 ? 'pc-delta-up' : 'pc-delta-down';
      },
      deltaIcon() {
        var d = this.summary.deltaVal;
        if (d === null || Math.round(d * 10) === 0) return 'ph ph-minus';
        return d > 0 ? 'ph ph-arrow-up-right' : 'ph ph-arrow-down-right';
      },

      /* ---- chart: linea, un punto = una settimana ---- */
      render() {
        var el = document.getElementById('chart-' + this.kind);
        if (!el || !this.hasData) return;
        if (chart) { chart.destroy(); chart = null; }

        var self = this;
        var entries = this.weeks;
        var weeks = this.weeks;
        var unit = this.unit;
        var color = this.color;
        var ticks = tickLines(entries);
        var selIdx = this.selIdx;

        // La larghezza della card inquadra le settimane degli ultimi 1 o 3
        // mesi (toggle zoom); lo storico più vecchio allunga la tela oltre la
        // card e si esplora trascinando. Spaziatura mai sotto MIN_PX_POINT.
        var inner = el.parentElement;            // .pc-scroll-inner
        var scroller = inner.parentElement;      // .pc-scroll
        var anchor = entries[entries.length - 1].start;
        var cutoff = new Date(anchor);
        cutoff.setMonth(cutoff.getMonth() - this.zoom);
        var visible = entries.filter(function (e) { return e.start >= cutoff; }).length || 1;
        var spacing = Math.max((scroller.clientWidth || 320) / visible, MIN_PX_POINT);
        inner.style.width = Math.round(entries.length * spacing) + 'px'; // min-width:100% fa da clamp
        wireDragPan(scroller);

        // Asse X lineare (indice settimana): la linea delle medie sta sui
        // valori interi; le rilevazioni grezze si spostano dentro lo slot in
        // proporzione al giorno della settimana (mer ≈ idx + 2/7).
        var lineData = entries.map(function (e, i) {
          return { x: i, y: e.n === 0 ? null : Math.round(e.mean * 10) / 10 };
        });
        var rawData = [];
        entries.forEach(function (e, i) {
          e.raw.forEach(function (p) {
            var frac = (p.d - e.monday) / (7 * 86400000); // 0 = lun … 6/7 = dom
            rawData.push({ x: i + frac, y: p.v, _d: p.d, _w: i });
          });
        });
        var radius = entries.map(function (e, i) { return e.n === 0 ? 0 : i === selIdx ? 6 : 3; });
        var ptColor = entries.map(function (_, i) { return i === selIdx ? color : color + 'bb'; });

        // Niente spazi laterali: l'asse parte sul primo dato (prima settimana
        // misurata, x=0) e finisce sull'ultimo (media finale o rilevazione
        // grezza più recente, se cade dopo il tick dell'ultima settimana).
        var maxX = entries.length - 1;
        rawData.forEach(function (p) { if (p.x > maxX) maxX = p.x; });

        var pad = this.kind === 'weight' ? (D.weight_pad || 10)
          : this.kind === 'circ' ? ((D.circ_pad || {})[this.measureKey] || 5)
          : this.measureKey === '__sum' ? 12 : ((D.skin_pad || {})[this.measureKey] || 5);
        var yb = yBounds(rawData.map(function (p) { return p.y; }), pad);

        var opts = {
          responsive: true,
          maintainAspectRatio: false,
          animation: { duration: 800, easing: 'easeOutQuart' },
          layout: { padding: { top: 6 } },
          onClick: function (evt) {
            if (scroller._dragMoved) return; // era un drag, non una selezione
            var els = chart.getElementsAtEventForMode(evt, 'nearest', { intersect: true }, true);
            if (!els.length) return;
            var el0 = els[0];
            // click su rilevazione grezza → seleziona la sua settimana
            if (el0.datasetIndex === 0) self.select(rawData[el0.index]._w);
            else self.select(el0.index);
          },
          onHover: function (evt, els) {
            if (evt.native && evt.native.target)
              evt.native.target.style.cursor = els.length ? 'pointer' : 'grab';
          },
          plugins: {
            legend: { display: false },
            tooltip: {
              backgroundColor: INK,
              titleColor: CREAM,
              bodyColor: CREAM,
              borderColor: color,
              borderWidth: 1,
              padding: 10,
              cornerRadius: 6,
              displayColors: false,
              titleFont: { family: 'JetBrains Mono, monospace', size: 10, weight: '500' },
              bodyFont: { family: 'Inter, sans-serif', size: 11, weight: '500' },
              callbacks: {
                title: function (items) {
                  if (!items.length) return '';
                  var it = items[0];
                  if (it.datasetIndex === 0) {
                    var d = rawData[it.dataIndex]._d;
                    return GIORNI[d.getDay()] + ' ' + ddmm(d) + '/' + d.getFullYear();
                  }
                  return entries[it.dataIndex].title;
                },
                label: function (ctx) {
                  // rilevazione grezza: solo data (nel titolo) e valore
                  if (ctx.datasetIndex === 0)
                    return 'Rilevazione: ' + fmtNum(rawData[ctx.dataIndex].y) + ' ' + unit;
                  var e = entries[ctx.dataIndex];
                  if (e.n === 0) return '';
                  var lines = ['Media: ' + fmtNum(e.mean) + ' ' + unit];
                  // andamento vs settimana precedente CON dati (le vuote non contano)
                  var p = prevWithData(weeks, weeks.indexOf(e));
                  if (p) lines.push('Δ vs sett. prec. (' + p.cmpLabel + '): ' + fmtDelta(e.mean - p.mean, unit));
                  if (e.n > 1) lines.push('Min–Max: ' + fmtNum(e.min) + ' – ' + fmtNum(e.max));
                  // le rilevazioni usate per calcolare la media
                  lines.push('Rilevazioni usate (' + e.n + '):');
                  var MAX = 6;
                  e.raw.slice(0, MAX).forEach(function (r) {
                    lines.push('  · ' + ddmm(r.d) + ' — ' + fmtNum(r.v) + ' ' + unit);
                  });
                  if (e.raw.length > MAX) lines.push('  … +' + (e.raw.length - MAX) + ' altre');
                  return lines;
                },
              },
            },
          },
          scales: {
            x: {
              type: 'linear',
              min: 0,
              max: maxX,
              grid: { display: false },
              border: { color: 'rgba(91,85,74,0.18)' },
              // un tick per settimana, sugli interi (dove sta la media)
              afterBuildTicks: function (axis) {
                axis.ticks = entries.map(function (_, i) { return { value: i }; });
              },
              ticks: {
                font: { family: 'JetBrains Mono, monospace', size: 10 },
                color: LABEL,
                maxRotation: 0,
                autoSkip: false,
                callback: function (v) { return ticks[v]; },
              },
            },
            y: {
              grid: { color: GRID, drawTicks: false },
              border: { display: false },
              // i valori sono renderizzati nell'overlay HTML fisso (.pc-yaxis),
              // che resta visibile mentre la timeline scorre
              ticks: { display: false },
            },
          },
        };
        if (yb) { opts.scales.y.min = yb.min; opts.scales.y.max = yb.max; }

        chart = new Chart(el, {
          type: 'line',
          data: {
            datasets: [
              // [0] rilevazioni grezze: trasparenti, sotto la linea — danno il
              // contesto delle oscillazioni dentro la settimana
              {
                type: 'scatter',
                data: rawData,
                clip: false, // i punti sul bordo (x=0 / x=maxX) non vanno tagliati
                pointRadius: 2.5,
                pointHoverRadius: 5,
                pointBackgroundColor: color + '3d',
                pointBorderColor: color + '22',
                pointBorderWidth: 1,
                pointHoverBackgroundColor: color + '90',
                pointHoverBorderColor: CREAM,
              },
              // [1] linea delle medie settimanali — attraversa le settimane
              // vuote senza spezzarsi (nessun punto dove non ci sono dati)
              {
                data: lineData,
                clip: false, // il punto sul bordo (x=0 / x=maxX) non va tagliato
                borderColor: color,
                backgroundColor: gradientFill(color),
                fill: true,
                borderWidth: 2,
                pointRadius: radius,
                pointHoverRadius: 7,
                pointBackgroundColor: ptColor,
                pointBorderColor: CREAM,
                pointBorderWidth: 1.5,
                tension: 0.35,
                spanGaps: true,
              },
            ],
          },
          options: opts,
        });

        // Asse Y fisso: i tick calcolati da Chart.js vengono replicati in un
        // overlay HTML ancorato alla card, così restano visibili a ogni
        // posizione di scroll della timeline.
        var yaxisEl = document.getElementById('yaxis-' + this.kind);
        if (yaxisEl) {
          var yScale = chart.scales.y;
          yaxisEl.innerHTML = yScale.ticks.map(function (t) {
            var py = yScale.getPixelForValue(t.value);
            return '<span style="top:' + py.toFixed(1) + 'px">' + fmtNum(t.value, 0) + '</span>';
          }).join('');
        }

        // mostra subito le settimane più recenti (la coda destra della serie)
        requestAnimationFrame(function () { scroller.scrollLeft = scroller.scrollWidth; });
      },
    };
  };
})();
