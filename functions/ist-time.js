'use strict';
// India time (IST, UTC+5:30) for ad and offer start / end times, the same rule as lib/domain/ist_time.dart: a saved time with its own
// zone (Z or +05:30) is that moment; one without a zone is India time. The server's clock (Date.now()) decides; never a phone's.
const IST_MS = 19800000;

/// Milliseconds since 1970 for a saved time, or null when blank or not a date.
function parseIst(value) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const v = String(value).trim();
  if (!v) return null;
  if (/(Z|[+-]\d{2}:?\d{2})$/.test(v)) {
    const t = Date.parse(v);
    return Number.isNaN(t) ? null : t;
  }
  // No zone: read the digits as India time.
  const t = Date.parse(`${v.length === 10 ? `${v}T00:00:00` : v}Z`);
  return Number.isNaN(t) ? null : t - IST_MS;
}

/// True when [now] is inside [startsAt, endsAt) (a missing end = no end, a missing start = from always).
function insideWindow(startsAt, endsAt, now = Date.now()) {
  const start = parseIst(startsAt), end = parseIst(endsAt);
  if (end !== null && now >= end) return false;
  if (start !== null && now < start) return false;
  return true;
}

module.exports = {parseIst, insideWindow, IST_MS};
