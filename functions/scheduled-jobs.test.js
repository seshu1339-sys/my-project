// The server has exactly two Cloud Scheduler jobs (functions/scheduled-jobs.js); loads functions/index.js, so no app is set up here first.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {TASK_NAMES, scheduledJobs} = require('./scheduled-jobs');

test('the jobs refuse to start without every task, and the server has exactly two schedules', () => {
  assert.throws(() => scheduledJobs({}), /Scheduled tasks missing/);
  const fns = require('./index');
  const scheduled = Object.entries(fns).filter(([, f]) => f?.__endpoint?.scheduleTrigger).map(([name]) => name).sort();
  assert.deepEqual(scheduled, ['every15Minutes', 'hourlyTasks'], 'at most 3 Cloud Scheduler jobs (3 are free)');
  for (const name of TASK_NAMES) assert.equal(fns[name].__endpoint, undefined, `${name} is a task, not a scheduled function of its own`);
});
