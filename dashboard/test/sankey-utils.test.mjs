/**
 * Pure tests for the sankey cycle-break.
 *
 *   node --test dashboard/test/sankey-utils.test.mjs
 *
 * No jest in this repo's frontend — node's built-in runner is enough for a
 * pure module, and it runs the real browser file (ESM, no build step).
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { toDagLinks, isAcyclic, canReach } from '../public/js/sankey-utils.js';
import { MOCK_SCREEN_FLOW_EDGES } from '../public/js/mock-data.js';

test('canReach walks the graph transitively', () => {
  const adjacency = new Map([
    ['A', new Set(['B'])],
    ['B', new Set(['C'])],
  ]);
  assert.equal(canReach(adjacency, 'A', 'C'), true);
  assert.equal(canReach(adjacency, 'C', 'A'), false);
  assert.equal(canReach(adjacency, 'A', 'A'), true);
});

test('a simple 2-cycle loses its lighter edge', () => {
  const { links, dropped } = toDagLinks([
    { source: 'Home', target: 'My plan', count: 100 },
    { source: 'My plan', target: 'Home', count: 40 },
  ]);
  assert.equal(links.length, 1);
  assert.deepEqual(links[0], { source: 'Home', target: 'My plan', value: 100 });
  assert.equal(dropped.length, 1);
  assert.equal(dropped[0].source, 'My plan');
});

test('a 3-cycle loses exactly one (the lightest) edge', () => {
  const { links, dropped } = toDagLinks([
    { source: 'A', target: 'B', count: 30 },
    { source: 'B', target: 'C', count: 20 },
    { source: 'C', target: 'A', count: 10 },
  ]);
  assert.equal(links.length, 2);
  assert.equal(dropped.length, 1);
  assert.deepEqual(
    { source: dropped[0].source, target: dropped[0].target },
    { source: 'C', target: 'A' },
  );
  assert.equal(isAcyclic(links), true);
});

test('normalises junk: self-loops, blanks, bad counts, duplicates', () => {
  const { links, nodes } = toDagLinks([
    { source: 'A', target: 'A', count: 99 },        // self-loop
    { source: '', target: 'B', count: 5 },           // blank source
    { source: 'A', target: '  ', count: 5 },         // blank target
    { source: 'A', target: 'B', count: 0 },          // zero
    { source: 'A', target: 'C', count: Number.NaN }, // non-finite
    { source: 'A', target: 'B', count: 3 },          // duplicate pair…
    { source: 'A', target: 'B', count: 4 },          // …summed to 7
    null,
  ]);
  assert.deepEqual(links, [{ source: 'A', target: 'B', value: 7 }]);
  assert.deepEqual(nodes, [{ name: 'A' }, { name: 'B' }]);
});

test('tolerates a missing / non-array edge list', () => {
  for (const input of [undefined, null, {}, 'nope']) {
    const out = toDagLinks(input);
    assert.deepEqual(out.links, []);
    assert.deepEqual(out.nodes, []);
  }
});

test('accepts `value` as an alias for `count`', () => {
  const { links } = toDagLinks([{ source: 'A', target: 'B', value: 12 }]);
  assert.deepEqual(links, [{ source: 'A', target: 'B', value: 12 }]);
});

test('nodes only ever reference kept links (no orphans for ECharts)', () => {
  const { nodes, links } = toDagLinks(MOCK_SCREEN_FLOW_EDGES);
  const referenced = new Set(links.flatMap((l) => [l.source, l.target]));
  assert.equal(nodes.length, referenced.size);
  for (const node of nodes) assert.ok(referenced.has(node.name), `orphan node ${node.name}`);
});

test('the cyclic 15-screen fixture reduces to a DAG', () => {
  // The fixture deliberately contains back-navigation cycles; if it did not,
  // this test would pass vacuously.
  assert.equal(isAcyclic(MOCK_SCREEN_FLOW_EDGES.map((e) => ({ source: e.source, target: e.target }))), false);

  const { nodes, links, dropped } = toDagLinks(MOCK_SCREEN_FLOW_EDGES);
  assert.ok(dropped.length > 0, 'expected at least one cycle-closing edge to be dropped');
  assert.ok(links.length > 0);
  assert.ok(nodes.length >= 10);
  assert.equal(isAcyclic(links), true);

  // Nothing invented: every kept link is a real input pair.
  const inputPairs = new Set(MOCK_SCREEN_FLOW_EDGES.map((e) => `${e.source}>${e.target}`));
  for (const link of links) assert.ok(inputPairs.has(`${link.source}>${link.target}`));
});
