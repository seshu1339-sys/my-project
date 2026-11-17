// Visitor counters in batches (free-limit plan, 17 Nov 2026): apps from 1.0.13 send ad views and taps together; older apps still send
// one event a call. A wrong event in a batch is skipped; a batch with nothing right is refused.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {normalizeEvents, MAX_BATCH} = require('./analytics');

const visitorId = '0123456789abcdef0123';

test('one event (older apps) still works', () => {
  assert.deepEqual(normalizeEvents({visitorId, type: 'visit', platform: 'web'}).map(e => e.type), ['visit']);
  assert.throws(() => normalizeEvents({visitorId: 'x', type: 'visit'}), /visitor id/);
});

test('a batch: every right event counted, a wrong one skipped, at most MAX_BATCH', () => {
  const events = normalizeEvents({visitorId, platform: 'android', events: [
    {type: 'adImpression', adId: 'ad1', placement: 'box'},
    {type: 'adClick', adId: 'ad1', placement: 'box'},
    {type: 'adImpression'}, // no ad: skipped
    {type: 'hack', adId: 'x'}, // unknown: skipped
  ]});
  assert.deepEqual(events.map(e => e.type), ['adImpression', 'adClick']);
  assert.equal(events[0].platform, 'android');
  assert.equal(events[0].visitorId, visitorId);
  const many = normalizeEvents({visitorId, events: Array.from({length: 50}, (_, i) => ({type: 'adImpression', adId: `a${i}`}))});
  assert.equal(many.length, MAX_BATCH);
  assert.throws(() => normalizeEvents({visitorId, events: [{type: 'hack'}]}), /Unsupported event/);
});
