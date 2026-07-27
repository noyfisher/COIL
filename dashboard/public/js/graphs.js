/**
 * Graphs page.
 *
 * One filter row (7 / 30 / 90 days) scopes every chart below it. Each chart is
 * a card with a table-view twin and a per-widget empty state, so a missing
 * section of the payload never blanks the page.
 *
 * Two deliberate departures from the "obvious" version of this page, both to
 * avoid the dual-axis anti-pattern (two y-scales on one plot invent a
 * correlation the data doesn't contain):
 *   - completion rate (%) and average duration (min) are small multiples,
 *     not two lines on one plot;
 *   - AI cost ($) and AI errors (count) share an x-axis in two stacked grids,
 *     each with its own scale, rather than an overlay on one.
 */

import { bootPage } from './auth.js';
import { fetchDashboard, handleApiError, ApiError } from './api.js';
import { toDagLinks } from './sankey-utils.js';
import {
  Card, axisChrome, crosshair, escapeHtml, fmtCompact, fmtDayShort, fmtInt, fmtMs, fmtPct,
  fmtUSD, humanize, isEmptySection, isNum, legendBase, lineSeries, tooltipBase, valueAxis,
} from './ui.js';

const RANGES = [7, 30, 90];
const DEFAULT_RANGE = 30;
const MAX_COST_SERIES = 7;   // 7 hues + "Other" — never generate a 9th

let cards = null;
let currentRange = DEFAULT_RANGE;
let inFlight = 0;

/* ------------------------------------------------------------------ helpers */

function relLuminance(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex).trim());
  if (!m) return 0;
  const int = parseInt(m[1], 16);
  const channel = (c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel((int >> 16) & 255) + 0.7152 * channel((int >> 8) & 255) + 0.0722 * channel(int & 255);
}

/** Label ink for text sitting *inside* a filled mark — picked by fill luminance. */
function inkOn(hex) {
  return relLuminance(hex) > 0.42 ? '#0b0b0b' : '#ffffff';
}

/** Axis-trigger tooltip: value leads, series name follows, keyed by a line. */
function axisTooltip(t, { dates, format }) {
  return {
    ...tooltipBase(t),
    trigger: 'axis',
    axisPointer: crosshair(t),
    formatter: (params) => {
      const list = Array.isArray(params) ? params : [params];
      if (list.length === 0) return '';
      const day = dates[list[0].dataIndex] ?? '';
      const head = `<div style="color:${t.textSecondary};margin-bottom:4px">${escapeHtml(fmtDayShort(day))}</div>`;
      const rows = list
        .filter((p) => p.value !== null && p.value !== undefined)
        .map((p) => {
          const key = `<span style="display:inline-block;width:12px;height:2px;background:${p.color};vertical-align:3px;margin-right:6px"></span>`;
          return `<div>${key}<strong>${escapeHtml(format(p.value, p.seriesName))}</strong>`
            + `<span style="color:${t.textSecondary}"> ${escapeHtml(p.seriesName ?? '')}</span></div>`;
        })
        .join('');
      return head + rows;
    },
  };
}

function dayCategoryAxis(t, dates, { gridIndex, showLabels = true } = {}) {
  return {
    type: 'category',
    data: dates.map(fmtDayShort),
    boundaryGap: true,
    ...(gridIndex === undefined ? {} : { gridIndex }),
    ...axisChrome(t),
    // Let ECharts thin the ticks itself; a hard interval crowds the narrow
    // (half-width) cards at 30 and 90 days.
    axisLabel: { ...axisChrome(t).axisLabel, show: showLabels, interval: 'auto' },
  };
}

/* ---------------------------------------------------------------- 1. engagement */

function renderEngagement(daily) {
  const card = cards.engagement;
  if (isEmptySection(daily)) {
    card.showEmpty('No GA4 days materialised for this range yet.');
    return;
  }
  const dates = daily.map((d) => d.date);
  const dau = daily.map((d) => d.engagement?.dau ?? null);
  const sessions = daily.map((d) => d.engagement?.totalSessions ?? null);

  card.render((t) => ({
    animation: false,
    grid: { top: 34, right: 58, bottom: 26, left: 8, containLabel: true },
    legend: legendBase(t, { data: ['Sessions', 'Daily active users'] }),
    tooltip: axisTooltip(t, { dates, format: (v) => fmtInt(v) }),
    xAxis: dayCategoryAxis(t, dates),
    yAxis: valueAxis(t, { axisLabel: { color: t.textMuted, fontSize: 11, formatter: (v) => fmtCompact(v) } }),
    series: [
      {
        ...lineSeries(t, { name: 'Sessions', data: sessions, color: t.series2 }),
        endLabel: { show: true, distance: 6, color: t.textPrimary, fontSize: 11, fontWeight: 600, formatter: (p) => fmtCompact(p.value) },
      },
      {
        ...lineSeries(t, { name: 'Daily active users', data: dau, color: t.series1 }),
        endLabel: { show: true, distance: 6, color: t.textPrimary, fontSize: 11, fontWeight: 600, formatter: (p) => fmtCompact(p.value) },
      },
    ],
  }));

  card.renderTable({
    columns: ['Day', 'Daily active users', 'Sessions'],
    rows: daily.map((d) => [d.date, fmtInt(d.engagement?.dau), fmtInt(d.engagement?.totalSessions)]),
  });
}

/* -------------------------------------------------------------------- 2. funnel */

function renderFunnel(funnelSummary) {
  const card = cards.funnel;
  const steps = funnelSummary?.steps;
  if (isEmptySection(steps)) {
    card.showEmpty('No funnel rollup yet — materializeRollups writes it with the 17:00 UTC pull.');
    return;
  }
  const ordered = [...steps].sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
  const names = ordered.map((s) => s.name ?? `Step ${s.order}`);
  const users = ordered.map((s) => (isNum(s.uniqueUsers) ? s.uniqueUsers : null));

  // One measure, one hue: the ordering is already carried by position and
  // length, so a value-ramp here would double-encode it.
  card.render((t) => ({
    animation: false,
    grid: { top: 8, right: 76, bottom: 26, left: 8, containLabel: true },
    tooltip: {
      ...tooltipBase(t),
      trigger: 'item',
      formatter: (p) => {
        const step = ordered[p.dataIndex];
        return `<div><strong>${escapeHtml(fmtInt(step.uniqueUsers))}</strong>`
          + `<span style="color:${t.textSecondary}"> unique users</span></div>`
          + `<div style="color:${t.textSecondary}">${escapeHtml(step.name ?? '')} · ${escapeHtml(fmtPct(step.conversionPct))} of step 1</div>`;
      },
    },
    xAxis: valueAxis(t, { axisLabel: { color: t.textMuted, fontSize: 11, formatter: (v) => fmtCompact(v) } }),
    yAxis: { type: 'category', data: names, inverse: true, ...axisChrome(t), axisLabel: { ...axisChrome(t).axisLabel, fontSize: 12, color: t.textSecondary, hideOverlap: false } },
    series: [{
      type: 'bar',
      data: users,
      barMaxWidth: 24,
      itemStyle: { color: t.series1, borderRadius: [0, 4, 4, 0] },
      label: {
        show: true,
        position: 'right',
        distance: 8,
        color: t.textSecondary,
        fontSize: 11,
        fontWeight: 600,
        formatter: (p) => fmtPct(ordered[p.dataIndex]?.conversionPct),
      },
      emphasis: { itemStyle: { color: t.series1, opacity: 0.85 } },
    }],
  }));

  card.renderTable({
    columns: ['#', 'Step', 'Unique users', 'Conversion from step 1'],
    rows: ordered.map((s, i) => [s.order ?? i + 1, s.name ?? '', fmtInt(s.uniqueUsers), fmtPct(s.conversionPct)]),
  });
}

/* --------------------------------------------------- 3 + 4. workout quality */

function renderSingleLine(card, { daily, pick, colorToken, format, axisFormat, yExtra = {}, seriesName }) {
  if (isEmptySection(daily)) {
    card.showEmpty('No workout days in this range.');
    return;
  }
  const dates = daily.map((d) => d.date);
  const values = daily.map(pick);

  card.render((t) => ({
    animation: false,
    grid: { top: 18, right: 54, bottom: 26, left: 8, containLabel: true },
    tooltip: axisTooltip(t, { dates, format: (v) => format(v) }),
    xAxis: dayCategoryAxis(t, dates),
    yAxis: valueAxis(t, { axisLabel: { color: t.textMuted, fontSize: 11, formatter: axisFormat }, ...yExtra }),
    series: [{
      // Single series — the card title names it, so no legend box.
      ...lineSeries(t, { name: seriesName, data: values, color: t[colorToken], area: true }),
      endLabel: { show: true, distance: 6, color: t.textPrimary, fontSize: 11, fontWeight: 600, formatter: (p) => format(p.value) },
    }],
  }));
}

function renderWorkoutQuality(daily) {
  renderSingleLine(cards.completion, {
    daily,
    seriesName: 'Completion rate',
    pick: (d) => (isNum(d.workout?.completionRatePct) ? d.workout.completionRatePct : null),
    colorToken: 'series3',
    format: (v) => fmtPct(v),
    axisFormat: (v) => `${v}%`,
    yExtra: { min: 0, max: 100 },
  });

  renderSingleLine(cards.duration, {
    daily,
    seriesName: 'Average duration',
    pick: (d) => (isNum(d.workout?.avgDurationSeconds) ? Number((d.workout.avgDurationSeconds / 60).toFixed(1)) : null),
    colorToken: 'series4',
    format: (v) => (isNum(v) ? `${v} min` : '—'),
    axisFormat: (v) => `${v}m`,
    yExtra: { min: 0 },
  });

  const table = {
    columns: ['Day', 'Started', 'Completed', 'Ended early', 'Completion rate', 'Avg duration'],
    rows: (daily ?? []).map((d) => [
      d.date,
      fmtInt(d.workout?.started),
      fmtInt(d.workout?.completed),
      fmtInt(d.workout?.endedEarly),
      fmtPct(d.workout?.completionRatePct),
      isNum(d.workout?.avgDurationSeconds) ? `${(d.workout.avgDurationSeconds / 60).toFixed(1)} min` : '—',
    ]),
  };
  if (!isEmptySection(daily)) {
    cards.completion.renderTable(table);
    cards.duration.renderTable(table);
  }
}

/* ------------------------------------------------------------- 5. AI cost */

function renderAiCost(aiDaily) {
  const card = cards.aiCost;
  if (isEmptySection(aiDaily)) {
    card.showEmpty('No aiUsageDaily rollups in this range.');
    return;
  }
  const dates = aiDaily.map((d) => d.date);
  const errors = aiDaily.map((d) => (isNum(d.errors) ? d.errors : 0));

  // Rank request types by total spend, keep the top 7, fold the tail into
  // "Other" — a 9th generated hue is never the answer.
  const totals = new Map();
  for (const day of aiDaily) {
    for (const [type, usd] of Object.entries(day.byTypeCostUSD ?? {})) {
      if (!isNum(usd)) continue;
      totals.set(type, (totals.get(type) ?? 0) + usd);
    }
  }
  const ranked = [...totals.entries()].sort((a, b) => b[1] - a[1]).map(([type]) => type);
  const kept = ranked.slice(0, MAX_COST_SERIES);
  const folded = ranked.slice(MAX_COST_SERIES);

  if (kept.length === 0) {
    card.showEmpty('Rollups exist but carry no per-type cost yet.');
    return;
  }

  const stackNames = [...kept.map(humanize), ...(folded.length ? ['Other'] : [])];
  const columns = [
    ...kept.map((type) => aiDaily.map((d) => Number((d.byTypeCostUSD?.[type] ?? 0).toFixed?.(4) ?? 0))),
    ...(folded.length
      ? [aiDaily.map((d) => Number(folded.reduce((sum, type) => sum + (d.byTypeCostUSD?.[type] ?? 0), 0).toFixed(4)))]
      : []),
  ];

  const note = document.getElementById('aiCostNote');
  if (note) {
    note.textContent = folded.length
      ? `top ${kept.length} request types · ${folded.length} folded into "Other"`
      : `${kept.length} request types`;
  }

  card.render((t) => {
    const hues = [...t.categorical.slice(0, kept.length), t.seriesOther];
    return {
      animation: false,
      // Plain (wrapping) legend, not a scroll pager: eight names have to be
      // readable at once, and the card is often only half the page wide.
      legend: legendBase(t, { data: stackNames, itemGap: 14, width: '96%' }),
      axisPointer: { link: [{ xAxisIndex: 'all' }] },
      tooltip: {
        ...tooltipBase(t),
        trigger: 'axis',
        axisPointer: { type: 'shadow' },
        formatter: (params) => {
          const list = Array.isArray(params) ? params : [params];
          const idx = list[0]?.dataIndex ?? 0;
          const head = `<div style="color:${t.textSecondary};margin-bottom:4px">${escapeHtml(fmtDayShort(dates[idx]))}</div>`;
          const total = columns.reduce((sum, col) => sum + (col[idx] ?? 0), 0);
          const body = list
            .filter((p) => p.seriesType === 'bar' && p.value > 0)
            .map((p) => `<div><span style="display:inline-block;width:12px;height:2px;background:${p.color};vertical-align:3px;margin-right:6px"></span>`
              + `<strong>${escapeHtml(fmtUSD(p.value))}</strong>`
              + `<span style="color:${t.textSecondary}"> ${escapeHtml(p.seriesName)}</span></div>`)
            .join('');
          return `${head}${body}<div style="margin-top:4px"><strong>${escapeHtml(fmtUSD(total))}</strong>`
            + `<span style="color:${t.textSecondary}"> total · ${escapeHtml(fmtInt(errors[idx]))} errors</span></div>`;
        },
      },
      grid: [
        // Two grids, one shared x — cost ($) and errors (count) never share a
        // y-scale. Bottom padding on grid 0 leaves room for grid 1.
        { top: 58, right: 20, bottom: 132, left: 8, containLabel: true },
        { right: 20, bottom: 26, height: 62, left: 8, containLabel: true },
      ],
      xAxis: [
        { ...dayCategoryAxis(t, dates, { gridIndex: 0, showLabels: false }) },
        { ...dayCategoryAxis(t, dates, { gridIndex: 1 }) },
      ],
      yAxis: [
        {
          // The $ formatter is the unit label — no axis name needed, and none
          // to collide with the wrapped legend above it.
          ...valueAxis(t, { axisLabel: { color: t.textMuted, fontSize: 11, formatter: (v) => `$${v.toFixed(2)}` } }),
          gridIndex: 0,
        },
        {
          ...valueAxis(t, { axisLabel: { color: t.textMuted, fontSize: 11, formatter: (v) => fmtInt(v) } }),
          gridIndex: 1,
          name: 'errors',
          nameLocation: 'middle',
          nameRotate: 90,
          nameGap: 26,
          nameTextStyle: { color: t.textMuted, fontSize: 11 },
          minInterval: 1,
        },
      ],
      series: [
        ...columns.map((data, i) => ({
          name: stackNames[i],
          type: 'bar',
          stack: 'cost',
          data,
          barMaxWidth: 24,
          // 2px of surface between segments — the gap does the separating,
          // not a contrasting stroke.
          itemStyle: {
            color: hues[i],
            borderColor: t.surface1,
            borderWidth: 1,
            borderRadius: i === columns.length - 1 ? [4, 4, 0, 0] : 0,
          },
        })),
        {
          name: 'Errors',
          type: 'line',
          xAxisIndex: 1,
          yAxisIndex: 1,
          data: errors,
          symbol: 'circle',
          symbolSize: 8,
          showSymbol: false,
          lineStyle: { width: 2, color: t.statusCritical, cap: 'round' },
          itemStyle: { color: t.statusCritical, borderColor: t.surface1, borderWidth: 2 },
          areaStyle: { color: t.statusCritical, opacity: 0.1 },
        },
      ],
    };
  });

  card.renderTable({
    columns: ['Day', 'Calls', 'Errors', 'Total cost', ...stackNames],
    rows: aiDaily.map((d, i) => [
      d.date,
      fmtInt(d.calls),
      fmtInt(d.errors),
      fmtUSD(d.totalCostUSD),
      ...columns.map((col) => fmtUSD(col[i])),
    ]),
  });
}

/* ---------------------------------------------------------- 6. AI latency */

function renderLatency(aiDaily) {
  const card = cards.latency;
  if (isEmptySection(aiDaily)) {
    card.showEmpty('No aiUsageDaily rollups in this range.');
    return;
  }
  const dates = aiDaily.map((d) => d.date);
  const values = aiDaily.map((d) => (isNum(d.avgLatencyMs) ? d.avgLatencyMs : null));

  card.render((t) => ({
    animation: false,
    grid: { top: 18, right: 62, bottom: 26, left: 8, containLabel: true },
    tooltip: axisTooltip(t, { dates, format: (v) => fmtMs(v) }),
    xAxis: dayCategoryAxis(t, dates),
    yAxis: valueAxis(t, { axisLabel: { color: t.textMuted, fontSize: 11, formatter: (v) => fmtMs(v) }, min: 0 }),
    series: [{
      ...lineSeries(t, { name: 'Average latency', data: values, color: t.series1, area: true }),
      endLabel: { show: true, distance: 6, color: t.textPrimary, fontSize: 11, fontWeight: 600, formatter: (p) => fmtMs(p.value) },
    }],
  }));

  card.renderTable({
    columns: ['Day', 'Calls', 'Avg latency'],
    rows: aiDaily.map((d) => [d.date, fmtInt(d.calls), fmtMs(d.avgLatencyMs)]),
  });
}

/* --------------------------------------------------------- 7. retention */

function renderRetention(retention) {
  const card = cards.retention;
  const cohorts = retention?.cohorts;
  if (isEmptySection(cohorts)) {
    card.showEmpty('No retention cohorts yet.');
    return;
  }
  const weeks = Math.max(...cohorts.map((c) => (c.retentionPct?.length ?? 0)));
  const weekLabels = Array.from({ length: weeks }, (_, i) => `W+${i}`);
  const cohortLabels = cohorts.map((c) => c.week ?? '');

  const cells = [];
  cohorts.forEach((cohort, y) => {
    (cohort.retentionPct ?? []).forEach((pct, x) => {
      if (isNum(pct)) cells.push([x, y, pct]);
    });
  });

  card.render((t) => {
    const ramp = t.sequential;
    const cellInk = (pct) => inkOn(ramp[Math.max(0, Math.min(ramp.length - 1, Math.round((pct / 100) * (ramp.length - 1))))]);
    return {
      animation: false,
      grid: { top: 10, right: 16, bottom: 58, left: 8, containLabel: true },
      tooltip: {
        ...tooltipBase(t),
        trigger: 'item',
        formatter: (p) => {
          const cohort = cohorts[p.value[1]];
          return `<div><strong>${escapeHtml(fmtPct(p.value[2]))}</strong>`
            + `<span style="color:${t.textSecondary}"> retained</span></div>`
            + `<div style="color:${t.textSecondary}">cohort ${escapeHtml(cohort?.week ?? '')} · ${escapeHtml(weekLabels[p.value[0]])} · ${escapeHtml(fmtInt(cohort?.size))} users</div>`;
        },
      },
      xAxis: { type: 'category', data: weekLabels, ...axisChrome(t), splitArea: { show: false } },
      yAxis: { type: 'category', data: cohortLabels, ...axisChrome(t), splitArea: { show: false } },
      visualMap: {
        min: 0,
        max: 100,
        calculable: false,
        orient: 'horizontal',
        left: 'center',
        bottom: 0,
        itemWidth: 12,
        itemHeight: 120,
        text: ['100%', '0%'],
        textStyle: { color: t.textMuted, fontSize: 11, fontFamily: 'inherit' },
        inRange: { color: t.sequential },
      },
      series: [{
        type: 'heatmap',
        // A label sitting inside a filled cell picks white or ink by the
        // fill's luminance, so it clears contrast at both ends of the ramp.
        data: cells.map(([x, y, v]) => ({ value: [x, y, v], label: { color: cellInk(v) } })),
        // 2px of surface between cells — same spacer rule as stacked bars.
        itemStyle: { borderColor: t.surface1, borderWidth: 2, borderRadius: 2 },
        label: {
          show: weeks <= 12,
          fontSize: 10,
          fontFamily: 'inherit',
          formatter: (p) => `${Math.round(p.value[2])}`,
        },
        emphasis: { itemStyle: { borderColor: t.textPrimary, borderWidth: 2 } },
        labelLayout: (params) => ({ fontSize: params.rect.width < 26 ? 0 : 10 }),
      }],
    };
  });

  card.renderTable({
    columns: ['Cohort', 'Users', ...weekLabels],
    rows: cohorts.map((c) => [
      c.week ?? '',
      fmtInt(c.size),
      ...weekLabels.map((_, i) => (isNum(c.retentionPct?.[i]) ? fmtPct(c.retentionPct[i]) : '—')),
    ]),
  });
}

/* ------------------------------------------------------------ 8. Sankey */

function renderSankey(screenFlow) {
  const card = cards.sankey;
  const edges = screenFlow?.edges;
  if (isEmptySection(edges)) {
    card.showEmpty('No screen-flow rollup yet — it is written with the 17:00 UTC pull.');
    return;
  }

  const { nodes, links, dropped } = toDagLinks(edges);
  if (links.length === 0) {
    card.showEmpty('Every transition in this window closed a cycle — nothing left to draw.');
    return;
  }

  const note = document.getElementById('sankeyNote');
  if (note) {
    const windowLabel = isNum(screenFlow.windowDays) ? `${screenFlow.windowDays}-day window` : 'rolling window';
    note.textContent = `${windowLabel} · ${nodes.length} screens · ${links.length} transitions`
      + (dropped.length ? ` · ${dropped.length} back-navigation edges removed to keep the flow acyclic` : '');
  }

  card.render((t) => ({
    animation: false,
    tooltip: {
      ...tooltipBase(t),
      trigger: 'item',
      triggerOn: 'mousemove',
      formatter: (p) => {
        if (p.dataType === 'edge') {
          return `<div><strong>${escapeHtml(fmtInt(p.data.value))}</strong>`
            + `<span style="color:${t.textSecondary}"> transitions</span></div>`
            + `<div style="color:${t.textSecondary}">${escapeHtml(p.data.source)} &rarr; ${escapeHtml(p.data.target)}</div>`;
        }
        return `<div><strong>${escapeHtml(p.name)}</strong></div>`;
      },
    },
    series: [{
      type: 'sankey',
      data: nodes,
      links,
      top: 10,
      bottom: 10,
      left: 8,
      right: 130,
      nodeWidth: 12,
      nodeGap: 10,
      nodeAlign: 'justify',
      draggable: false,
      // One hue for every node: this chart's job is the shape of the flow,
      // not telling 15 screens apart by colour. Labels carry identity.
      itemStyle: { color: t.series1, borderWidth: 0 },
      lineStyle: { color: t.textMuted, opacity: 0.22, curveness: 0.5 },
      label: { color: t.textPrimary, fontSize: 11, fontFamily: 'inherit' },
      emphasis: { focus: 'adjacency', lineStyle: { opacity: 0.45 } },
    }],
  }));

  const droppedKeys = new Set(dropped.map((d) => `${d.source}>${d.target}`));
  card.renderTable({
    columns: ['From', 'To', 'Transitions', 'In the diagram'],
    rows: [...edges]
      .filter((e) => e && e.source && e.target)
      .sort((a, b) => (b.count ?? 0) - (a.count ?? 0))
      .map((e) => [
        e.source,
        e.target,
        fmtInt(e.count),
        e.source === e.target ? 'no — self-loop' : droppedKeys.has(`${e.source}>${e.target}`) ? 'no — closes a cycle' : 'yes',
      ]),
  });
}

/* ---------------------------------------------------------------- loading */

function setStale(stale) {
  for (const card of Object.values(cards)) card.setStale(stale);
}

function showBanner(message) {
  const banner = document.getElementById('loadBanner');
  if (!banner) return;
  banner.hidden = !message;
  if (message) {
    banner.replaceChildren();
    const strong = document.createElement('strong');
    strong.textContent = 'Load failed. ';
    banner.append(strong, document.createTextNode(message));
  }
}

async function load(days, { first = false } = {}) {
  const ticket = ++inFlight;
  setStale(true);
  try {
    const payload = await fetchDashboard('graphs', { days });
    if (ticket !== inFlight) return;       // a newer range won the race
    renderEngagement(payload?.daily);
    renderFunnel(payload?.funnelSummary);
    renderWorkoutQuality(payload?.daily);
    renderAiCost(payload?.aiDaily);
    renderLatency(payload?.aiDaily);
    renderRetention(payload?.retention);
    renderSankey(payload?.screenFlow);
    showBanner(null);
  } catch (err) {
    if (first) {
      handleApiError(err instanceof ApiError ? err : new ApiError(0, 'unknown', String(err?.message ?? err)));
      return;
    }
    showBanner(err?.message ?? String(err));
  } finally {
    if (ticket === inFlight) setStale(false);
  }
}

function wireRange() {
  const host = document.getElementById('rangeButtons');
  if (!host) return;
  host.replaceChildren(...RANGES.map((days) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'btn';
    btn.textContent = `${days} days`;
    btn.setAttribute('aria-pressed', String(days === currentRange));
    btn.addEventListener('click', () => {
      if (days === currentRange) return;
      currentRange = days;
      for (const other of host.querySelectorAll('button')) {
        other.setAttribute('aria-pressed', String(other === btn));
      }
      void load(days);
    });
    return btn;
  }));
}

bootPage(async () => {
  cards = {
    engagement: new Card('card-engagement'),
    funnel: new Card('card-funnel'),
    completion: new Card('card-completion'),
    duration: new Card('card-duration'),
    aiCost: new Card('card-ai-cost'),
    latency: new Card('card-latency'),
    retention: new Card('card-retention'),
    sankey: new Card('card-sankey'),
  };
  wireRange();
  await load(currentRange, { first: true });
});
