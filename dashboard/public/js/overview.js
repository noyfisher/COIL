/**
 * Overview page.
 *
 * Three rows of stat tiles + a 14-day trend strip. Each tile names the day its
 * number comes from ("today (UTC)", "yesterday (GA4)", "as of 01:00 UTC"),
 * because the three sources keep three different clocks and reconciling them
 * would be a lie — labelling them is the honest fix.
 *
 * Row 1 re-polls every 60s. Refetch holds the previous render at reduced
 * opacity rather than flashing a skeleton.
 */

import { bootPage } from './auth.js';
import { fetchDashboard, handleApiError, ApiError } from './api.js';
import {
  Card, dash, fmtClockUTC, fmtCompact, fmtDayShort, fmtInt, fmtMs, fmtPct, fmtSigned, fmtUSD,
  humanize, isEmptySection, isNum, lineSeries, tooltipBase, crosshair, axisChrome, valueAxis,
} from './ui.js';

const POLL_MS = 60_000;

let sparkKey = null;   // only rebuild the trend charts when the window moves
let sparkCards = null;

/* -------------------------------------------------------------- tile render */

function warnIcon() {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 16 16');
  svg.setAttribute('width', '13');
  svg.setAttribute('height', '13');
  svg.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  path.setAttribute('d', 'M8 1.6 15 14H1L8 1.6Zm0 4.1a.75.75 0 0 0-.75.75v3a.75.75 0 0 0 1.5 0v-3A.75.75 0 0 0 8 5.7Zm0 5.4a.9.9 0 1 0 0 1.8.9.9 0 0 0 0-1.8Z');
  path.setAttribute('fill', 'currentColor');
  svg.appendChild(path);
  return svg;
}

/**
 * @param {{label:string, value:string, unit?:string, sub?:string|Node,
 *          source:string, state?:'critical'|'warning', flag?:string,
 *          meter?:{pct:number, state?:string}}} spec
 */
function tileEl(spec) {
  const tile = document.createElement('div');
  tile.className = 'tile';
  if (spec.state) tile.classList.add(`is-${spec.state}`);

  const label = document.createElement('div');
  label.className = 'tile-label';
  label.textContent = spec.label;
  tile.appendChild(label);

  const value = document.createElement('div');
  value.className = 'tile-value';
  value.textContent = spec.value;
  if (spec.unit) {
    const unit = document.createElement('span');
    unit.className = 'tile-unit';
    unit.textContent = spec.unit;
    value.appendChild(unit);
  }
  tile.appendChild(value);

  if (spec.flag) {
    const flag = document.createElement('div');
    flag.className = 'tile-sub status-flag';
    flag.appendChild(warnIcon());
    flag.appendChild(document.createTextNode(` ${spec.flag}`));
    tile.appendChild(flag);
  }

  if (spec.meter) {
    const meter = document.createElement('div');
    meter.className = 'meter';
    if (spec.meter.state) meter.classList.add(`is-${spec.meter.state}`);
    const fill = document.createElement('span');
    fill.style.width = `${Math.max(0, Math.min(100, spec.meter.pct))}%`;
    meter.appendChild(fill);
    tile.appendChild(meter);
  }

  if (spec.sub) {
    const sub = document.createElement('div');
    sub.className = 'tile-sub';
    if (spec.sub instanceof Node) sub.appendChild(spec.sub);
    else sub.textContent = spec.sub;
    tile.appendChild(sub);
  }

  const source = document.createElement('div');
  source.className = 'tile-source';
  source.textContent = spec.source;
  tile.appendChild(source);

  return tile;
}

function deltaNode(delta, period) {
  if (!isNum(delta)) return null;
  const wrap = document.createElement('span');
  const num = document.createElement('span');
  num.className = `tile-delta ${delta >= 0 ? 'up' : 'down'}`;
  num.textContent = fmtSigned(delta);
  wrap.appendChild(num);
  wrap.appendChild(document.createTextNode(` ${period}`));
  return wrap;
}

function renderRow(id, specs) {
  const row = document.getElementById(id);
  if (!row) return;
  row.replaceChildren(...specs.map(tileEl));
}

/* ---------------------------------------------------------------- the rows */

function renderLiveRow(live = {}, nowDate) {
  const dayLabel = nowDate ? `today (UTC) · ${fmtDayShort(nowDate)}` : 'today (UTC)';
  const calls = live.aiCallsToday;
  const budget = live.aiBudgetLimit;
  const errors = live.aiErrorsToday;
  const errorRate = isNum(calls) && calls > 0 && isNum(errors) ? (errors / calls) * 100 : isNum(calls) ? 0 : null;
  const usedPct = isNum(calls) && isNum(budget) && budget > 0 ? (calls / budget) * 100 : 0;
  const crashes = live.crashes24h;

  renderRow('row-live', [
    {
      label: 'AI calls today',
      value: fmtInt(calls),
      unit: isNum(budget) ? `/ ${fmtInt(budget)}` : '',
      meter: { pct: usedPct, state: usedPct >= 90 ? 'critical' : usedPct >= 70 ? 'warning' : undefined },
      sub: isNum(budget) ? `${usedPct.toFixed(0)}% of the daily budget` : 'no budget configured',
      source: `${dayLabel} · aiUsageDaily`,
    },
    {
      label: 'AI cost today',
      value: fmtUSD(live.aiCostTodayUSD),
      sub: `avg latency ${fmtMs(live.aiAvgLatencyMsToday)}`,
      source: `${dayLabel} · static price table`,
    },
    {
      label: 'AI error rate today',
      value: fmtPct(errorRate),
      sub: `${fmtInt(errors)} failed of ${fmtInt(calls)} calls`,
      state: isNum(errorRate) && errorRate >= 10 ? 'critical' : undefined,
      source: `${dayLabel} · aiUsageDaily`,
    },
    {
      label: 'Crashes',
      value: fmtInt(crashes),
      state: isNum(crashes) && crashes > 0 ? 'critical' : undefined,
      flag: isNum(crashes) && crashes > 0 ? 'crash markers uploaded' : undefined,
      sub: isNum(crashes) && crashes === 0 ? 'none reported' : undefined,
      source: 'last 24h · sessionLogs',
    },
  ]);
}

/**
 * API-shape adapters. `buildOverviewPayload` (functions/src/dashboard-data.ts)
 * returns `yesterday` NESTED (engagement/funnel/workout/ai) and `totals` with
 * a `deltas{}` object + `date` — the tile renderers below want flat fields.
 * Each adapter also passes through an already-flat shape, so a fixture or a
 * future API change in either direction can't blank the row again.
 */
function flattenYesterday(y) {
  if (!y || typeof y !== 'object') return y;
  const e = y.engagement ?? {};
  const f = y.funnel ?? {};
  const w = y.workout ?? {};
  return {
    date: y.date,
    dau: y.dau ?? e.dau ?? null,
    sessions: y.sessions ?? e.totalSessions ?? null,
    workoutsCompleted: y.workoutsCompleted ?? w.completed ?? e.workoutsCompleted ?? null,
    plansGenerated: y.plansGenerated ?? f.rehabPlanGenerated ?? null,
  };
}

function flattenTotals(t) {
  if (!t || typeof t !== 'object') return t;
  const d = t.deltas ?? {};
  return {
    ...t,
    asOf: t.asOf ?? t.date ?? null,
    totalUsersDelta7d: t.totalUsersDelta7d ?? d.totalUsers ?? null,
    totalPlansDelta7d: t.totalPlansDelta7d ?? d.totalPlans ?? null,
  };
}

function renderYesterdayRow(yesterday) {
  const head = document.getElementById('head-yesterday');
  if (head) {
    head.textContent = yesterday?.date
      ? `GA4 day ${yesterday.date} — lands the next morning, so today is never here`
      : 'GA4 day — lands the next morning';
  }
  if (isEmptySection(yesterday)) {
    const row = document.getElementById('row-yesterday');
    if (row) {
      const empty = document.createElement('div');
      empty.className = 'empty';
      empty.textContent = 'No GA4 day materialised yet. Run backfillAnalytics, or wait for the 17:00 UTC pull.';
      row.replaceChildren(empty);
    }
    return;
  }

  const source = `yesterday (GA4) · ${fmtDayShort(yesterday.date)}`;
  renderRow('row-yesterday', [
    { label: 'Daily active users', value: fmtCompact(yesterday.dau), source },
    { label: 'Sessions', value: fmtCompact(yesterday.sessions), source },
    { label: 'Workouts completed', value: fmtCompact(yesterday.workoutsCompleted), source },
    { label: 'Plans generated', value: fmtCompact(yesterday.plansGenerated), source },
  ]);
}

function renderTotalsRow(totals, live = {}) {
  if (isEmptySection(totals)) {
    const row = document.getElementById('row-totals');
    if (row) {
      const empty = document.createElement('div');
      empty.className = 'empty';
      empty.textContent = 'No aggregate document yet — aggregateDailyMetrics runs at 01:00 UTC.';
      row.replaceChildren(empty);
    }
    return;
  }

  const asOf = totals.asOf ? `as of ${fmtDayShort(String(totals.asOf).slice(0, 10))} 01:00 UTC` : 'as of last aggregate';
  renderRow('row-totals', [
    {
      label: 'Total users',
      value: fmtCompact(totals.totalUsers),
      sub: deltaNode(totals.totalUsersDelta7d, 'vs 7 days ago'),
      source: `${asOf} · dailyAggregates`,
    },
    {
      label: 'Total plans',
      value: fmtCompact(totals.totalPlans),
      sub: deltaNode(totals.totalPlansDelta7d, 'vs 7 days ago'),
      source: `${asOf} · dailyAggregates`,
    },
    {
      label: 'Active plans',
      value: fmtCompact(totals.activePlansCount),
      sub: 'touched in the last 14 days',
      source: `${asOf} · dailyAggregates`,
    },
    {
      label: 'Session logs uploaded',
      value: fmtCompact(live.sessionsUploaded24h),
      sub: `${fmtCompact(totals.totalWorkoutSessions)} workout sessions all-time`,
      source: 'last 24h · sessionLogs',
    },
  ]);
}

function renderDataQuality(live = {}) {
  const host = document.getElementById('dataQualityBody');
  if (!host) return;
  const failures = live.validationFailures ?? {};
  const entries = Object.entries(failures).filter(([, v]) => isNum(v) && v > 0);
  const missing = live.missingExerciseImages;

  if (entries.length === 0 && !isNum(missing)) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'No validation counters reported.';
    host.replaceChildren(empty);
    return;
  }

  const list = document.createElement('dl');
  list.className = 'kv-list';
  const rows = [
    ...entries.sort((a, b) => b[1] - a[1]).map(([key, count]) => [`${humanize(key)} rejections`, fmtInt(count)]),
    ['Missing exercise images', fmtInt(missing)],
  ];
  for (const [term, value] of rows) {
    const row = document.createElement('div');
    row.className = 'kv-row';
    const dt = document.createElement('dt');
    dt.textContent = term;
    const dd = document.createElement('dd');
    dd.textContent = value;
    row.append(dt, dd);
    list.appendChild(row);
  }
  if (entries.length === 0) {
    const note = document.createElement('div');
    note.className = 'inline-note';
    note.textContent = 'No response-validation rejections today.';
    host.replaceChildren(list, note);
    return;
  }
  host.replaceChildren(list);
}

/* ----------------------------------------------------------- nightly report */

/**
 * Delivery chip. "skipped" is the honest label for BOTH "no recipient
 * configured" and "SendGrid never attempted" — the report is on the dashboard
 * either way, which is the point of persisting it before the send.
 */
const REPORT_STATUS_CHIP = {
  sent: { text: 'email sent', cls: 'is-sent' },
  failed: { text: 'email failed', cls: 'is-failed' },
  skipped: { text: 'email off — dashboard only', cls: 'is-off' },
};

let reportKey = null;   // don't re-render (and collapse) an unchanged report

function renderNightlyReport(report) {
  const body = document.getElementById('nightlyReportBody');
  const meta = document.getElementById('nightlyReportMeta');
  const chip = document.getElementById('nightlyReportStatus');
  const toggle = document.getElementById('nightlyReportToggle');
  const warning = document.getElementById('nightlyReportWarning');
  if (!body) return;

  if (isEmptySection(report)) {
    reportKey = null;
    if (meta) meta.textContent = '';
    if (chip) chip.hidden = true;
    if (toggle) toggle.hidden = true;
    if (warning) warning.hidden = true;
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'No report yet — first one lands after the next 07:00 run.';
    body.classList.remove('is-collapsed');
    body.replaceChildren(empty);
    return;
  }

  const key = `${report.date}|${report.generatedAt}|${report.emailStatus}`;
  if (key === reportKey) return;            // same report — leave the reader's toggle alone
  reportKey = key;

  if (meta) {
    const when = report.generatedAt ? ` · generated ${fmtClockUTC(report.generatedAt)}` : '';
    meta.textContent = `${fmtDayShort(report.date)}${when}`;
  }

  if (chip) {
    const spec = REPORT_STATUS_CHIP[report.emailStatus];
    chip.className = `report-chip${spec ? ` ${spec.cls}` : ''}`;
    chip.textContent = spec ? spec.text : 'email status unknown';
    chip.hidden = false;
  }

  if (warning) {
    warning.hidden = report.validationPassed !== false;
    if (!warning.hidden) {
      warning.textContent = 'This report failed structural validation — it is the degraded fallback, not Claude’s summary.';
    }
  }

  // The ONLY innerHTML on this page. `summaryHtml` is server-rendered by
  // markdownToHtml() in functions/src/index.ts — the same HTML already trusted
  // as an email body — and never leaves this container.
  body.classList.add('is-collapsed');
  body.innerHTML = report.summaryHtml ?? '';

  if (toggle) {
    // Only offer the toggle when there is something hidden below the fold.
    const overflows = body.scrollHeight > body.clientHeight + 8;
    toggle.hidden = !overflows;
    toggle.textContent = 'Show full report';
    toggle.setAttribute('aria-expanded', 'false');
    if (!overflows) body.classList.remove('is-collapsed');
  }
}

function wireReportToggle() {
  const toggle = document.getElementById('nightlyReportToggle');
  const body = document.getElementById('nightlyReportBody');
  if (!toggle || !body) return;
  toggle.addEventListener('click', () => {
    const expanded = body.classList.toggle('is-collapsed') === false;
    toggle.textContent = expanded ? 'Show less' : 'Show full report';
    toggle.setAttribute('aria-expanded', String(expanded));
  });
}

/* ------------------------------------------------------------- trend strip */

function sparkline(card, { rows, valueKey, color, format, axisFormat }) {
  const dates = rows.map((r) => r.date);
  const values = rows.map((r) => (isNum(r[valueKey]) ? r[valueKey] : null));
  const lastIndex = values.length - 1;

  card.render((t) => {
    const hue = t[color];
    return {
      animation: false,
      // right padding holds the end-value label; keep it wider than "$0.00"
      grid: { top: 18, right: 60, bottom: 18, left: 8, containLabel: true },
      tooltip: {
        ...tooltipBase(t),
        trigger: 'axis',
        axisPointer: crosshair(t),
        formatter: (params) => {
          const p = params[0];
          return `<div style="font-weight:600">${format(p.value)}</div>`
            + `<div style="color:${t.textSecondary}">${fmtDayShort(dates[p.dataIndex])}</div>`;
        },
      },
      xAxis: { type: 'category', data: dates.map(fmtDayShort), boundaryGap: false, ...axisChrome(t), axisLabel: { show: false } },
      yAxis: { ...valueAxis(t, { axisLabel: { show: false }, splitLine: { show: false } }), scale: true },
      series: [
        {
          ...lineSeries(t, { name: card.root.id, data: values, color: hue, area: true }),
          markPoint: {
            symbol: 'circle',
            symbolSize: 9,
            data: [{ coord: [lastIndex, values[lastIndex]] }],
            itemStyle: { color: hue, borderColor: t.surface1, borderWidth: 2 },
            label: {
              show: true,
              position: 'right',
              distance: 8,
              color: t.textPrimary,
              fontSize: 12,
              fontWeight: 600,
              fontFamily: 'inherit',
              formatter: () => axisFormat(values[lastIndex]),
            },
          },
        },
      ],
    };
  });

  card.renderTable({
    columns: ['Day', card.root.dataset.metric ?? 'Value'],
    rows: rows.map((r) => [r.date, format(r[valueKey])]),
  });
}

function renderTrend(trend14d) {
  if (!sparkCards) {
    sparkCards = {
      dau: new Card('card-spark-dau'),
      workouts: new Card('card-spark-workouts'),
      cost: new Card('card-spark-cost'),
    };
  }
  if (isEmptySection(trend14d)) {
    for (const card of Object.values(sparkCards)) card.showEmpty('No 14-day history materialised yet.');
    return;
  }
  const key = `${trend14d.length}:${trend14d[trend14d.length - 1]?.date}`;
  if (key === sparkKey) return;             // window hasn't moved — leave the charts alone
  sparkKey = key;

  sparkline(sparkCards.dau, {
    rows: trend14d, valueKey: 'dau', color: 'series1',
    format: (v) => fmtInt(v), axisFormat: (v) => fmtCompact(v),
  });
  sparkline(sparkCards.workouts, {
    rows: trend14d, valueKey: 'workoutsCompleted', color: 'series3',
    format: (v) => fmtInt(v), axisFormat: (v) => fmtCompact(v),
  });
  sparkline(sparkCards.cost, {
    rows: trend14d, valueKey: 'aiCostUSD', color: 'series2',
    format: (v) => fmtUSD(v), axisFormat: (v) => fmtUSD(v),
  });
}

/* -------------------------------------------------------------------- boot */

function setUpdated(payload) {
  const el = document.getElementById('lastUpdated');
  if (el) el.textContent = `updated ${fmtClockUTC(payload?.generatedAt ?? payload?.now?.serverTime)}`;
}

function setStale(stale) {
  const row = document.getElementById('row-live');
  if (row) row.classList.toggle('is-stale', stale);
}

function renderAll(payload) {
  renderLiveRow(payload?.live ?? {}, payload?.today ?? payload?.now?.date);
  renderYesterdayRow(flattenYesterday(payload?.yesterday));
  renderTotalsRow(flattenTotals(payload?.totals), payload?.live ?? {});
  renderDataQuality(payload?.live ?? {});
  renderTrend(payload?.trend14d);
  renderNightlyReport(payload?.nightlyReport);
  setUpdated(payload);
}

function showPollBanner(message) {
  const banner = document.getElementById('pollBanner');
  if (!banner) return;
  banner.hidden = !message;
  if (message) {
    banner.replaceChildren();
    const strong = document.createElement('strong');
    strong.textContent = 'Refresh failed. ';
    banner.append(strong, document.createTextNode(`${message} Showing the last good read.`));
  }
}

async function load({ first }) {
  setStale(true);
  try {
    const payload = await fetchDashboard('overview');
    renderAll(payload);
    showPollBanner(null);
  } catch (err) {
    if (first) {
      handleApiError(err instanceof ApiError ? err : new ApiError(0, 'unknown', String(err?.message ?? err)));
      return;
    }
    showPollBanner(err?.message ?? String(err));
  } finally {
    setStale(false);
  }
}

bootPage(async () => {
  const refresh = document.getElementById('refreshBtn');
  if (refresh) refresh.addEventListener('click', () => { void load({ first: false }); });
  wireReportToggle();

  await load({ first: true });

  window.setInterval(() => {
    if (document.visibilityState === 'visible') void load({ first: false });
  }, POLL_MS);
});
