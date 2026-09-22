// All storage (SQLite datetime('now'), JWT iat/exp, etc.) stays UTC —
// that's the only sane thing to persist. This module is display-only:
// it formats a UTC Date/timestamp as Indian Standard Time (UTC+5:30, no
// DST) for anything actually shown to a person, per the owner's request.
// IST needs no timezone-conversion library (fixed offset, no DST rules to
// track) — Node's built-in Intl with timeZone: 'Asia/Kolkata' is enough.

const IST_TIME_ZONE = 'Asia/Kolkata';

// e.g. "22 Sep 2026, 14:54:08 IST" — used in the per-view watermark label
// (viewer email + timestamp), baked into images/snippets/html overlays.
function formatIst(date = new Date()) {
  const formatted = new Intl.DateTimeFormat('en-IN', {
    timeZone: IST_TIME_ZONE,
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(date);
  return `${formatted} IST`;
}

module.exports = { formatIst, IST_TIME_ZONE };
