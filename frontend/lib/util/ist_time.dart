/// Formats timestamps as Indian Standard Time (UTC+5:30, fixed, no DST)
/// for display, per the owner's request. All storage stays UTC — this is
/// display-only, same principle as the backend's lib/time.js.
///
/// The backend (SQLite `datetime('now')`) returns UTC timestamps as plain
/// strings with no timezone suffix, e.g. "2026-09-22 09:24:36" — Dart's
/// DateTime.parse() treats a string with no offset/Z as *local* time by
/// default, which would be wrong here (it's always UTC from the server).
/// [parseUtc] fixes that by parsing then explicitly marking the result UTC.
library;

const _istOffset = Duration(hours: 5, minutes: 30);
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Parses a backend timestamp string (SQLite `datetime('now')` format,
/// space-separated, no timezone suffix — always UTC) as a UTC DateTime.
DateTime parseUtc(String sqliteTimestamp) {
  // Accepts both "YYYY-MM-DD HH:MM:SS" (SQLite) and ISO ("...T...Z") just
  // in case a caller ever passes the latter — DateTime.parse handles both,
  // this only needs to force UTC when the string didn't already specify it.
  final normalized = sqliteTimestamp.contains('T') ? sqliteTimestamp : sqliteTimestamp.replaceFirst(' ', 'T');
  final parsed = DateTime.parse(normalized);
  return parsed.isUtc ? parsed : DateTime.utc(
    parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute, parsed.second, parsed.millisecond,
  );
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');

/// "22 Sep 2026, 14:54:36 IST" — a UTC backend timestamp string, formatted
/// for display in IST.
String formatIst(String sqliteTimestamp) {
  final utc = parseUtc(sqliteTimestamp);
  final ist = utc.add(_istOffset);
  final date = '${_twoDigits(ist.day)} ${_months[ist.month - 1]} ${ist.year}';
  final time = '${_twoDigits(ist.hour)}:${_twoDigits(ist.minute)}:${_twoDigits(ist.second)}';
  return '$date, $time IST';
}

/// Same as [formatIst] but without seconds — for tighter list rows.
String formatIstShort(String sqliteTimestamp) {
  final utc = parseUtc(sqliteTimestamp);
  final ist = utc.add(_istOffset);
  final date = '${_twoDigits(ist.day)} ${_months[ist.month - 1]} ${ist.year}';
  final time = '${_twoDigits(ist.hour)}:${_twoDigits(ist.minute)}';
  return '$date, $time IST';
}
