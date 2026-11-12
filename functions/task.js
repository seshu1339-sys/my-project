'use strict';
// A scheduled job's work as a plain function (Cloud Scheduler cost, Nov 2026). The jobs are no longer separate scheduled functions
// (13 Cloud Scheduler jobs, only 3 are free): functions/scheduled-jobs.js runs them all from two schedules. task(handler) keeps the
// old name callable and keeps .run() for the tests; it has no Firebase endpoint, so it is never deployed on its own.
function task(handler) {
  const run = event => handler(event);
  return Object.assign(run, {run});
}

module.exports = {task};
