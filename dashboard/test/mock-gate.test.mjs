/**
 * Pure tests for the fixture-mode host gate.
 *
 *   node --test dashboard/test/mock-gate.test.mjs
 *
 * The case that matters most — `?mock=1` being REFUSED on a deployed origin —
 * cannot be exercised in a browser locally: the Firebase emulator serves on
 * `localhost`, which is exactly the host the gate allows. That is the whole
 * reason the predicate is pure and lives apart from ui.js.
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { isMockAllowed } from '../public/js/mock-gate.js';

test('allows fixtures on localhost with mock=1', () => {
  assert.equal(isMockAllowed('localhost', '?mock=1'), true);
  assert.equal(isMockAllowed('127.0.0.1', '?mock=1'), true);
  assert.equal(isMockAllowed('::1', '?mock=1'), true);
  assert.equal(isMockAllowed('[::1]', '?mock=1'), true); // as location.hostname reports it
});

test('refuses fixtures on the deployed origin even with mock=1', () => {
  assert.equal(isMockAllowed('pt-helper-dev.web.app', '?mock=1'), false);
  assert.equal(isMockAllowed('pt-helper-dev.firebaseapp.com', '?mock=1'), false);
  assert.equal(isMockAllowed('pt-helper-prod.web.app', '?mock=1'), false);
});

test('is not fooled by a hostname that merely contains an allowed one', () => {
  assert.equal(isMockAllowed('localhost.evil.example', '?mock=1'), false);
  assert.equal(isMockAllowed('notlocalhost', '?mock=1'), false);
  assert.equal(isMockAllowed('127.0.0.1.evil.example', '?mock=1'), false);
});

test('stays off on a local host without the flag', () => {
  assert.equal(isMockAllowed('localhost', ''), false);
  assert.equal(isMockAllowed('localhost', '?mock=0'), false);
  assert.equal(isMockAllowed('localhost', '?mock=true'), false);
  assert.equal(isMockAllowed('localhost', '?days=30'), false);
});

test('finds the flag alongside other query params', () => {
  assert.equal(isMockAllowed('localhost', '?days=30&mock=1'), true);
});

test('handles missing arguments without throwing', () => {
  assert.equal(isMockAllowed(undefined, undefined), false);
  assert.equal(isMockAllowed(null, null), false);
});
