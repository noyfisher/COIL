/**
 * Shared UI helpers for the COIL monitoring dashboard.
 *
 * Owns the three things both pages need and neither should duplicate:
 *   1. design tokens  — read back out of CSS custom properties so ECharts and
 *      the stylesheet can never drift (and dark mode is one source of truth)
 *   2. formatting     — compact numbers, money, percents, dates
 *   3. chart plumbing — card scaffolding, the table-view twin, empty states,
 *      resize + colour-scheme re-render
 *
 * Chart chrome follows the dataviz mark specs: 2px lines, >=8px markers,
 * <=24px bars with 4px rounded data-ends, hairline solid gridlines, 10%
 * area washes, and a crosshair tooltip on every time series.
 */

/* ---------------------------------------------------------------- mock mode */

/** `?mock=1` short-circuits auth and serves fixtures (see js/mock-data.js). */
export const IS_MOCK = new URLSearchParams(window.location.search).get('mock') === '1';

/* ------------------------------------------------------------------ screens */

const SCREEN_IDS = ['screen-loading', 'screen-signin', 'screen-denied', 'screen-config', 'screen-error', 'screen-app'];

/** Show exactly one top-level screen; hide the rest. */
export function showScreen(id) {
  for (const candidate of SCREEN_IDS) {
    const el = document.getElementById(candidate);
    if (el) el.hidden = candidate !== id;
  }
}

/** Put a message into a screen's `[data-message]` slot (textContent — untrusted). */
export function setScreenMessage(screenId, message) {
  const el = document.querySelector(`#${screenId} [data-message]`);
  if (el) el.textContent = message;
}

/* --------------------------------------------------------------- formatting */

export function isNum(v) {
  return typeof v === 'number' && Number.isFinite(v);
}

/** Null-safe em dash for anything the API didn't send. */
export function dash(v) {
  return isNum(v) ? v : '—';
}

export function fmtInt(v) {
  return isNum(v) ? v.toLocaleString('en-US') : '—';
}

/** 1,284 / 12.9K / 4.2M — proportional figures, for tile values. */
export function fmtCompact(v) {
  if (!isNum(v)) return '—';
  const abs = Math.abs(v);
  if (abs >= 1e6) return `${(v / 1e6).toFixed(1).replace(/\.0$/, '')}M`;
  if (abs >= 10000) return `${(v / 1e3).toFixed(1).replace(/\.0$/, '')}K`;
  return v.toLocaleString('en-US');
}

export function fmtUSD(v, { compact = false } = {}) {
  if (!isNum(v)) return '—';
  const abs = Math.abs(v);
  if (compact && abs >= 1000) return `$${(v / 1000).toFixed(1)}K`;
  if (abs >= 100) return `$${v.toFixed(0)}`;
  return `$${v.toFixed(2)}`;
}

export function fmtPct(v, digits = 1) {
  return isNum(v) ? `${v.toFixed(digits)}%` : '—';
}

export function fmtMs(v) {
  if (!isNum(v)) return '—';
  return v >= 1000 ? `${(v / 1000).toFixed(1)}s` : `${Math.round(v)}ms`;
}

export function fmtSigned(v) {
  if (!isNum(v)) return '—';
  return `${v > 0 ? '+' : ''}${v.toLocaleString('en-US')}`;
}

/** "2026-07-25" -> "Jul 25" (kept in the payload's own calendar, no TZ shift). */
export function fmtDayShort(isoDate) {
  if (typeof isoDate !== 'string' || isoDate.length < 10) return String(isoDate ?? '');
  const [, m, d] = isoDate.slice(0, 10).split('-');
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const month = months[Number(m) - 1];
  return month ? `${month} ${Number(d)}` : isoDate;
}

export function fmtClockUTC(iso) {
  const t = iso ? new Date(iso) : new Date();
  if (Number.isNaN(t.getTime())) return '—';
  return `${String(t.getUTCHours()).padStart(2, '0')}:${String(t.getUTCMinutes()).padStart(2, '0')} UTC`;
}

/**
 * Escape API-supplied text before it goes into an ECharts tooltip string.
 * (ECharts formatters render HTML; series names come from the API, so they are
 * untrusted. Everywhere else we use textContent.)
 */
export function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Turn a snake/camel request-type key into a readable label. */
export function humanize(key) {
  return String(key)
    .replace(/[_-]+/g, ' ')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/^\s*\w/, (c) => c.toUpperCase());
}

/* ------------------------------------------------------------------- tokens */

const TOKEN_NAMES = [
  'surface-1', 'plane', 'text-primary', 'text-secondary', 'text-muted',
  'gridline', 'axis', 'hairline',
  'series-1', 'series-2', 'series-3', 'series-4',
  'series-5', 'series-6', 'series-7', 'series-8', 'series-other',
  'seq-100', 'seq-200', 'seq-300', 'seq-400', 'seq-500', 'seq-600', 'seq-700',
  'status-good', 'status-warning', 'status-serious', 'status-critical',
];

/** Resolve the CSS custom properties into plain hex for ECharts. */
export function tokens() {
  const cs = getComputedStyle(document.documentElement);
  const out = {};
  for (const name of TOKEN_NAMES) {
    out[name.replace(/-(\w)/g, (_, c) => c.toUpperCase())] = cs.getPropertyValue(`--${name}`).trim();
  }
  out.categorical = [out.series1, out.series2, out.series3, out.series4,
    out.series5, out.series6, out.series7, out.series8];
  out.sequential = [out.seq100, out.seq200, out.seq300, out.seq400, out.seq500, out.seq600, out.seq700];
  return out;
}

/** Series hue by fixed slot index — assigned by entity, never by rank. */
export function slot(i) {
  const t = tokens().categorical;
  return i < t.length ? t[i] : tokens().seriesOther;
}

/* ---------------------------------------------------------- chart defaults */

const AXIS_FONT = 11;

/** Shared axis/grid chrome: hairline solid gridlines, recessive ink. */
export function axisChrome(t, { rotate = 0 } = {}) {
  return {
    axisLine: { lineStyle: { color: t.axis } },
    axisTick: { show: false },
    axisLabel: { color: t.textMuted, fontSize: AXIS_FONT, fontFamily: 'inherit', rotate, hideOverlap: true },
    splitLine: { show: false },
  };
}

export function valueAxis(t, extra = {}) {
  return {
    type: 'value',
    ...axisChrome(t),
    axisLine: { show: false },
    splitLine: { show: true, lineStyle: { color: t.gridline, width: 1, type: 'solid' } },
    ...extra,
  };
}

export function tooltipBase(t, extra = {}) {
  return {
    backgroundColor: t.surface1,
    borderColor: t.hairline,
    borderWidth: 1,
    padding: [8, 10],
    textStyle: { color: t.textPrimary, fontSize: 12, fontFamily: 'inherit' },
    extraCssText: 'box-shadow: 0 6px 20px rgba(0,0,0,0.14); border-radius: 8px;',
    ...extra,
  };
}

/** Crosshair that snaps to the nearest X — readers aim at a date, not a line. */
export function crosshair(t) {
  return {
    type: 'line',
    lineStyle: { color: t.axis, width: 1, type: 'solid' },
    label: { show: false },
  };
}

export function legendBase(t, extra = {}) {
  return {
    show: true,
    top: 0,
    left: 0,
    itemGap: 16,
    itemWidth: 14,
    itemHeight: 8,
    icon: 'roundRect',
    textStyle: { color: t.textSecondary, fontSize: 12, fontFamily: 'inherit' },
    ...extra,
  };
}

/** 2px line + >=8px end marker with a 2px surface ring. */
export function lineSeries(t, { name, data, color, area = false, showSymbol = false }) {
  return {
    name,
    type: 'line',
    data,
    smooth: false,
    symbol: 'circle',
    symbolSize: 8,
    showSymbol,
    showAllSymbol: false,
    lineStyle: { width: 2, color, cap: 'round', join: 'round' },
    itemStyle: { color, borderColor: t.surface1, borderWidth: 2 },
    emphasis: { scale: 1.15, focus: 'none' },
    areaStyle: area ? { color, opacity: 0.1 } : undefined,
  };
}

/* ----------------------------------------------------------------- rendering */

const registry = [];

/**
 * Attach an ECharts instance to `el` and keep it in sync with the viewport and
 * the OS colour scheme. `build(t)` returns the option object for tokens `t`.
 */
export function mountChart(el, build) {
  if (!window.echarts) throw new Error('ECharts not loaded');
  const chart = window.echarts.init(el, null, { renderer: 'canvas' });
  const entry = { chart, build, el };
  registry.push(entry);
  chart.setOption(build(tokens()), true);
  return {
    chart,
    update(nextBuild) {
      if (nextBuild) entry.build = nextBuild;
      chart.setOption(entry.build(tokens()), true);
    },
    dispose() {
      const i = registry.indexOf(entry);
      if (i >= 0) registry.splice(i, 1);
      chart.dispose();
    },
  };
}

let resizeTimer = null;
window.addEventListener('resize', () => {
  window.clearTimeout(resizeTimer);
  resizeTimer = window.setTimeout(() => {
    for (const e of registry) e.chart.resize();
  }, 120);
});

// Dark mode is a re-render, not an automatic flip: the palette's dark steps
// come from the stylesheet, so re-reading tokens is all it takes.
const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');
const onSchemeChange = () => {
  const t = tokens();
  for (const e of registry) e.chart.setOption(e.build(t), true);
};
if (typeof darkQuery.addEventListener === 'function') darkQuery.addEventListener('change', onSchemeChange);

/* ---------------------------------------------------------------- card shell */

/**
 * Wraps a `<figure class="card">` already present in the HTML.
 * Handles the plot element, the table-view twin, empty states and the
 * hold-the-frame refetch treatment.
 */
export class Card {
  constructor(id) {
    this.root = document.getElementById(id);
    if (!this.root) throw new Error(`Card #${id} not found`);
    this.plotEl = this.root.querySelector('.card-plot');
    this.tableEl = this.root.querySelector('.card-table');
    this.handle = null;
    this._emptyEl = null;

    const toggle = this.root.querySelector('[data-table-toggle]');
    if (toggle && this.tableEl) {
      toggle.addEventListener('click', () => {
        const showTable = this.tableEl.hidden;
        this.tableEl.hidden = !showTable;
        this.plotEl.hidden = showTable;
        toggle.textContent = showTable ? 'Chart' : 'Table';
        toggle.setAttribute('aria-pressed', String(showTable));
        if (!showTable && this.handle) this.handle.chart.resize();
      });
    }
  }

  setStale(stale) {
    this.root.classList.toggle('is-stale', Boolean(stale));
  }

  /** Render (or re-render) the chart. `build(t)` returns an ECharts option. */
  render(build) {
    this._clearEmpty();
    // If the reader has the table view open, keep it open and rebuild behind it.
    const tableOpen = this.tableEl ? !this.tableEl.hidden : false;
    if (this.handle) this.handle.update(build);
    else this.handle = mountChart(this.plotEl, build);
    this.plotEl.hidden = tableOpen;
    if (!tableOpen) this.handle.chart.resize();
  }

  /** Every chart has a table-view twin — the WCAG-clean equivalent. */
  renderTable({ columns, rows }) {
    if (!this.tableEl) return;
    const table = document.createElement('table');
    table.className = 'dv-table';
    const thead = document.createElement('thead');
    const headRow = document.createElement('tr');
    for (const col of columns) {
      const th = document.createElement('th');
      th.scope = 'col';
      th.textContent = col;
      headRow.appendChild(th);
    }
    thead.appendChild(headRow);
    table.appendChild(thead);

    const tbody = document.createElement('tbody');
    for (const row of rows) {
      const tr = document.createElement('tr');
      for (const cell of row) {
        const td = document.createElement('td');
        if (cell && typeof cell === 'object' && cell.swatch) {
          const dot = document.createElement('span');
          dot.className = 'swatch';
          dot.style.background = cell.swatch;
          td.appendChild(dot);
          td.appendChild(document.createTextNode(String(cell.text ?? '')));
        } else {
          td.textContent = String(cell ?? '');
        }
        tr.appendChild(td);
      }
      tbody.appendChild(tr);
    }
    table.appendChild(tbody);

    this.tableEl.replaceChildren(table);
  }

  /** Per-widget empty state — a missing section never blanks the page. */
  showEmpty(message) {
    if (this.handle) {
      this.handle.dispose();
      this.handle = null;
    }
    this.plotEl.replaceChildren();
    this.plotEl.hidden = true;
    if (this.tableEl) {
      this.tableEl.replaceChildren();
      this.tableEl.hidden = true;
    }
    if (!this._emptyEl) {
      this._emptyEl = document.createElement('div');
      this._emptyEl.className = 'empty';
      this.root.appendChild(this._emptyEl);
    }
    this._emptyEl.textContent = message;
  }

  _clearEmpty() {
    if (this._emptyEl) {
      this._emptyEl.remove();
      this._emptyEl = null;
    }
    this.plotEl.hidden = false;
  }
}

/** True when a widget's slice of the payload can't be charted. */
export function isEmptySection(v) {
  if (v == null) return true;
  if (Array.isArray(v)) return v.length === 0;
  if (typeof v === 'object') return Object.keys(v).length === 0;
  return false;
}
