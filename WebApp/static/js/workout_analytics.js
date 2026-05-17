/**
 * Pure aggregation helpers for the workout builder analytics layer.
 *
 * Reads from the Alpine `workoutWizard` component state:
 *   - plan.days[].exercises[]  (base config)
 *   - progression.computed     (per-week computed cells, keyed by exercise pk)
 *
 * All helpers are side-effect free; they take state in and return numbers/maps.
 * Designed to be called from x-data getters or before `mountChart()` calls.
 */
(function () {
  // intensity zones based on %1RM (or RPE fallback when load_unit=RPE)
  const ZONES = ['tech', 'ipert', 'forza', 'picco'];

  function zoneFromPct1RM(pct) {
    if (pct == null || isNaN(pct)) return null;
    if (pct < 60) return 'tech';
    if (pct < 75) return 'ipert';
    if (pct < 85) return 'forza';
    return 'picco';
  }

  function zoneFromRPE(rpe) {
    if (rpe == null || isNaN(rpe)) return null;
    if (rpe < 6) return 'tech';
    if (rpe < 8) return 'ipert';
    if (rpe < 9) return 'forza';
    return 'picco';
  }

  function parseReps(reps) {
    if (typeof reps === 'number') return reps;
    const s = String(reps || '').trim();
    const m = s.match(/(\d+)(?:\s*[-–]\s*(\d+))?/);
    if (!m) return 10;
    if (m[2]) return Math.round((parseInt(m[1]) + parseInt(m[2])) / 2);
    return parseInt(m[1]) || 10;
  }

  function getCell(progression, exerciseId, week) {
    if (!progression || !progression.computed) return null;
    const k = String(exerciseId);
    const wk = String(week);
    const cells = progression.computed[k];
    return (cells && cells[wk]) || null;
  }

  /**
   * Day volume by muscle group.
   * Primary muscle ×1, secondary ×0.5 (matches server formula at views_session.py:670).
   * Returns: { labels: [...], values: [...] } sorted desc by sets.
   */
  function computeDayVolume(day) {
    const map = {};
    (day.exercises || []).forEach(ex => {
      const sets = parseInt(ex.sets) || 0;
      if (!sets) return;
      const primary = ex.target_muscle_group || ex.primary_muscle;
      const secondary = ex.secondary_muscle;
      if (primary) map[primary] = (map[primary] || 0) + sets;
      if (secondary) map[secondary] = (map[secondary] || 0) + sets * 0.5;
    });
    const arr = Object.entries(map).map(([k, v]) => ({ k, v }));
    arr.sort((a, b) => b.v - a.v);
    return {
      labels: arr.map(x => x.k),
      values: arr.map(x => Math.round(x.v * 10) / 10),
    };
  }

  /**
   * Week intensity distribution: count of sets falling into each zone for given week.
   * Returns: { tech, ipert, forza, picco } counts.
   */
  function computeWeekIntensity(plan, progression, weekN) {
    const counts = { tech: 0, ipert: 0, forza: 0, picco: 0 };
    (plan.days || []).forEach(d => {
      (d.exercises || []).forEach(ex => {
        const c = getCell(progression, ex.pk, weekN) || {};
        const sets = parseInt(c.set_count ?? ex.sets) || 0;
        if (!sets) return;
        let zone = null;
        const unit = c.load_unit || ex.load_unit;
        if (unit === 'PERCENT_1RM' && (c.load_value ?? ex.load_value)) {
          zone = zoneFromPct1RM(parseFloat(c.load_value ?? ex.load_value));
        } else if (c.rpe || ex.rpe) {
          zone = zoneFromRPE(parseFloat(c.rpe ?? ex.rpe));
        }
        if (zone) counts[zone] += sets;
      });
    });
    return counts;
  }

  /**
   * Stacked-intensity dataset across all weeks.
   * Returns: { labels: ['S1','S2',...], zones: { tech:[...], ipert:[...], forza:[...], picco:[...] } }
   */
  function computeIntensityStackedSeries(plan, progression) {
    const weeks = plan.duration_weeks || 1;
    const out = { labels: [], zones: { tech: [], ipert: [], forza: [], picco: [] } };
    for (let w = 1; w <= weeks; w++) {
      out.labels.push(`S${w}`);
      const c = computeWeekIntensity(plan, progression, w);
      ZONES.forEach(z => out.zones[z].push(c[z]));
    }
    return out;
  }

  /**
   * RPE heatmap matrix: x = day index, y = exercise (flat list), v = rpe for given week.
   */
  function computeRPEHeatmap(plan, progression, weekN) {
    const xLabels = [];
    const yLabels = [];
    const cells = [];
    (plan.days || []).forEach((d, di) => {
      xLabels.push(d.name || `G${di + 1}`);
      (d.exercises || []).forEach((ex) => {
        const yi = yLabels.indexOf(ex.exercise_name);
        const y = yi === -1 ? yLabels.push(ex.exercise_name) - 1 : yi;
        const c = getCell(progression, ex.pk, weekN) || {};
        const rpe = c.rpe ?? ex.rpe;
        cells.push({ x: di, y, v: rpe ? parseFloat(rpe) : null });
      });
    });
    return { xLabels, yLabels, cells };
  }

  /**
   * Series for a single exercise across weeks: load|reps|rpe|tonnage.
   * Returns: { labels: ['S1',...], values: [...] }
   */
  function computeExerciseSeries(ex, progression, metric, weeks) {
    const labels = [];
    const values = [];
    for (let w = 1; w <= weeks; w++) {
      labels.push(`S${w}`);
      const c = getCell(progression, ex.pk, w) || {};
      const sets = parseInt(c.set_count ?? ex.sets) || 0;
      const reps = parseReps(c.rep_range ?? ex.reps);
      const load = c.load_value ?? ex.load_value;
      const rpe = c.rpe ?? ex.rpe;
      let v = null;
      switch (metric) {
        case 'load':    v = load != null && load !== '' ? parseFloat(load) : null; break;
        case 'reps':    v = reps || null; break;
        case 'rpe':     v = rpe != null && rpe !== '' ? parseFloat(rpe) : null; break;
        case 'tonnage': {
          const l = load != null && load !== '' ? parseFloat(load) : null;
          v = l !== null && sets && reps ? Math.round(sets * reps * l) : null;
          break;
        }
        case 'volume':  v = sets * reps || null; break;
        default:        v = null;
      }
      values.push(v);
    }
    return { labels, values };
  }

  /**
   * Total tonnage per week (sums across all exercises with KG load).
   */
  function computeWeeklyTonnage(plan, progression) {
    const weeks = plan.duration_weeks || 1;
    const labels = [];
    const values = [];
    for (let w = 1; w <= weeks; w++) {
      labels.push(`S${w}`);
      let tot = 0;
      (plan.days || []).forEach(d => {
        (d.exercises || []).forEach(ex => {
          const c = getCell(progression, ex.pk, w) || {};
          const sets = parseInt(c.set_count ?? ex.sets) || 0;
          const reps = parseReps(c.rep_range ?? ex.reps);
          const unit = c.load_unit || ex.load_unit;
          const load = c.load_value ?? ex.load_value;
          if (unit === 'KG' && load != null && load !== '') {
            tot += sets * reps * parseFloat(load);
          }
        });
      });
      values.push(Math.round(tot));
    }
    return { labels, values };
  }

  /**
   * KPI bundle for a week (or whole plan when weekN = null).
   */
  function weekKPIs(plan, progression, weekN) {
    let sets = 0, tonnage = 0, rpeSum = 0, rpeN = 0;
    (plan.days || []).forEach(d => {
      (d.exercises || []).forEach(ex => {
        const c = (weekN ? getCell(progression, ex.pk, weekN) : null) || {};
        const s = parseInt(c.set_count ?? ex.sets) || 0;
        const reps = parseReps(c.rep_range ?? ex.reps);
        const unit = c.load_unit || ex.load_unit;
        const load = c.load_value ?? ex.load_value;
        const rpe = c.rpe ?? ex.rpe;
        sets += s;
        if (unit === 'KG' && load != null && load !== '') {
          tonnage += s * reps * parseFloat(load);
        }
        if (rpe) { rpeSum += parseFloat(rpe); rpeN += 1; }
      });
    });
    return {
      sets,
      tonnage: Math.round(tonnage),
      avgRPE: rpeN ? Math.round((rpeSum / rpeN) * 10) / 10 : 0,
    };
  }

  /**
   * Volume-by-muscle for the whole plan (used in final review dashboard).
   */
  function computePlanVolume(plan) {
    const map = {};
    (plan.days || []).forEach(d => {
      (d.exercises || []).forEach(ex => {
        const sets = parseInt(ex.sets) || 0;
        if (!sets) return;
        const primary = ex.target_muscle_group || ex.primary_muscle;
        const secondary = ex.secondary_muscle;
        if (primary) map[primary] = (map[primary] || 0) + sets;
        if (secondary) map[secondary] = (map[secondary] || 0) + sets * 0.5;
      });
    });
    const arr = Object.entries(map).map(([k, v]) => ({ k, v }));
    arr.sort((a, b) => b.v - a.v);
    return {
      labels: arr.map(x => x.k),
      values: arr.map(x => Math.round(x.v * 10) / 10),
    };
  }

  /**
   * Count deload weeks across plan.
   */
  function countDeloadWeeks(progression) {
    const weeks = progression?.weeks || [];
    return weeks.filter(w => w.week_type === 'DELOAD').length;
  }

  /**
   * Peak intensity zone in plan (most populated zone across all weeks).
   */
  function planPeakIntensityZone(plan, progression) {
    const series = computeIntensityStackedSeries(plan, progression);
    const totals = { tech: 0, ipert: 0, forza: 0, picco: 0 };
    ZONES.forEach(z => {
      totals[z] = (series.zones[z] || []).reduce((a, b) => a + (b || 0), 0);
    });
    const total = ZONES.reduce((a, z) => a + totals[z], 0);
    let peakZone = null, peakCount = 0;
    ZONES.forEach(z => { if (totals[z] > peakCount) { peakCount = totals[z]; peakZone = z; } });
    const pct = total ? Math.round((peakCount / total) * 100) : 0;
    const label = { tech: 'Tecnica', ipert: 'Ipertrofia', forza: 'Forza', picco: 'Picco' }[peakZone] || '—';
    return { zone: peakZone, label, pct };
  }

  window.AthlynkAnalytics = {
    parseReps,
    computeDayVolume,
    computeWeekIntensity,
    computeIntensityStackedSeries,
    computeRPEHeatmap,
    computeExerciseSeries,
    computeWeeklyTonnage,
    computePlanVolume,
    weekKPIs,
    countDeloadWeeks,
    planPeakIntensityZone,
  };
})();
