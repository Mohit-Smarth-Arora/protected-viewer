const path = require('path');
const fs = require('fs');
const Database = require('better-sqlite3');
const { dataDir } = require('./paths');

if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

const db = new Database(path.join(dataDir, 'app.sqlite'));
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  -- role: 'viewer' (default, regular account) | 'admin' (approved, can
  -- upload assets + manage grants) | 'owner' (you — there is exactly one,
  -- seeded manually, can approve/reject admin requests and toggle
  -- has_master_access on other admins).
  -- has_master_access: only meaningful for role='admin'. When true, that
  -- admin gets owner-level powers too (approve requests, toggle other
  -- admins' master access). Off by default — owner grants it explicitly
  -- per admin, per the tiered model decided for this feature.
  -- email_verified: must be 1 before a viewer can do anything past
  -- registration (see requireEmailVerified middleware). signup_status:
  -- 'active' (referral code used, or email-verified path completed) |
  -- 'pending_approval' (registered without a referral code, waiting on
  -- any admin to approve — see signup_requests below).
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('viewer', 'admin', 'owner')),
    has_master_access INTEGER NOT NULL DEFAULT 0,
    email_verified INTEGER NOT NULL DEFAULT 0,
    signup_status TEXT NOT NULL DEFAULT 'active' CHECK (signup_status IN ('active', 'pending_approval')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- A 6-digit code emailed at registration (and resend). Verified once;
  -- rows are kept (not deleted) for a simple audit trail, superseded rows
  -- just stay unused. expires_at bounds how long a code is valid.
  CREATE TABLE IF NOT EXISTS email_verification_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    code TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    used_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Referral codes: created only by owner/master-access admins. A valid,
  -- active code entered at registration skips the pending-approval step
  -- entirely (still requires email verification). is_active lets an admin
  -- deactivate a code without deleting its usage history.
  CREATE TABLE IF NOT EXISTS referral_codes (
    code TEXT PRIMARY KEY,
    created_by INTEGER NOT NULL REFERENCES users(id),
    is_active INTEGER NOT NULL DEFAULT 1,
    uses_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- A pending "no referral code" signup, waiting for any admin to approve
  -- or reject. Mirrors admin_requests' shape/spirit but simpler — no
  -- identity form, just an account waiting on a yes/no.
  CREATE TABLE IF NOT EXISTS signup_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewed_by INTEGER REFERENCES users(id),
    reviewed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- A pending application to become an admin. Reviewed in-app by the owner
  -- (or a master-access admin). photo_path points into the same
  -- STORAGE_ROOT-relative convention as assets.file_path, but under
  -- admin_photos/ — never exposed via the public /api/assets routes.
  CREATE TABLE IF NOT EXISTS admin_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    full_legal_name TEXT NOT NULL,
    phone_number TEXT NOT NULL,
    organization TEXT,
    reason TEXT NOT NULL,
    photo_path TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewed_by INTEGER REFERENCES users(id),
    reviewed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Folders are hierarchical (parent_id, nullable = root-level). Access
  -- grants live at the folder level (folder_grants below) — a viewer
  -- granted a folder implicitly sees everything inside it, including
  -- subfolders, without needing a grant row for each descendant.
  CREATE TABLE IF NOT EXISTS folders (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id TEXT REFERENCES folders(id),
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- type 'html': a raw HTML document, served inline (not flattened to an
  -- image) with a server-injected watermark overlay per request — see
  -- lib/watermark.js injectWatermarkIntoHtml. Weaker protection than
  -- image/snippet (view-source and save-page-as still work; nothing about
  -- HTML rendered in a browser can be made truly copy-proof), accepted
  -- deliberately for this asset type rather than flattening it to a
  -- screenshot, which would defeat the point of it being an interactive page.
  CREATE TABLE IF NOT EXISTS assets (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('image', 'video', 'snippet', 'html')),
    title TEXT NOT NULL,
    file_path TEXT NOT NULL,
    folder_id TEXT REFERENCES folders(id),
    uploaded_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Per-user, per-asset access grants. Kept for assets at root (no folder)
  -- or for granting a single asset without granting its whole folder.
  -- Admins/owner always have implicit access to everything.
  -- watermark_enabled: per-grant override, meaningful for type='html' only
  -- (image/snippet are always watermarked — there's no unwatermarked path
  -- for those, the pixels are baked server-side regardless). Defaults on;
  -- an admin can grant a specific viewer the unwatermarked version of an
  -- HTML asset by turning this off for their grant row specifically.
  CREATE TABLE IF NOT EXISTS asset_grants (
    user_id INTEGER NOT NULL REFERENCES users(id),
    asset_id TEXT NOT NULL REFERENCES assets(id),
    granted_by INTEGER NOT NULL REFERENCES users(id),
    watermark_enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, asset_id)
  );

  -- Per-user, per-folder access grants. Grants everything in the folder
  -- and all its subfolders (checked via ancestor walk in code — see
  -- lib/folders.js — not duplicated as rows per descendant).
  CREATE TABLE IF NOT EXISTS folder_grants (
    user_id INTEGER NOT NULL REFERENCES users(id),
    folder_id TEXT NOT NULL REFERENCES folders(id),
    granted_by INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, folder_id)
  );

  -- asset_id is deliberately NOT a foreign key: this is the
  -- leak-traceability record (who viewed what, when) and must survive an
  -- asset being deleted later — a hard FK would force cascading deletes
  -- of view history whenever an asset is removed, defeating the point of
  -- keeping the log. asset_title snapshots the title at view time so the
  -- log stays human-readable even after the asset row is gone. user_id is
  -- likewise NOT a foreign key, for the same reason: deleting a user's
  -- account (see routes/admin.js DELETE /users/:id) must not erase the
  -- record of what they viewed. user_email is snapshotted at delete time
  -- so the log stays attributable even once the account is gone.
  CREATE TABLE IF NOT EXISTS access_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    user_email TEXT,
    asset_id TEXT NOT NULL,
    asset_title TEXT,
    action TEXT NOT NULL,
    ip TEXT,
    user_agent TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS agreements (
    user_id INTEGER PRIMARY KEY REFERENCES users(id),
    accepted_at TEXT NOT NULL DEFAULT (datetime('now')),
    version TEXT NOT NULL
  );

  -- One row per successful login. Separate from access_log (which is
  -- asset-view specific) since this is account-level activity the "view
  -- all who joined/signed in" admin screen reads.
  CREATE TABLE IF NOT EXISTS login_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    ip TEXT,
    user_agent TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Last-seen heartbeat for a rough "active now" admin view. Overwritten
  -- in place (one row per user, not a log) — the client pings periodically
  -- while the app is open; "online" is derived as "seen within N minutes"
  -- at read time, not stored as a boolean.
  CREATE TABLE IF NOT EXISTS user_presence (
    user_id INTEGER PRIMARY KEY REFERENCES users(id),
    last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- A viewer's request to open a chat with an admin/owner. Approving a
  -- request (or an admin messaging a viewer directly, which auto-creates
  -- an approved thread) opens a chat_threads row; messages then reference
  -- that thread. One thread per (viewer, admin) pair.
  CREATE TABLE IF NOT EXISTS chat_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    viewer_id INTEGER NOT NULL REFERENCES users(id),
    admin_id INTEGER REFERENCES users(id), -- NULL = directed at "any admin"/owner
    message TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewed_by INTEGER REFERENCES users(id),
    reviewed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS chat_threads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    viewer_id INTEGER NOT NULL REFERENCES users(id),
    admin_id INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (viewer_id, admin_id)
  );

  CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL REFERENCES chat_threads(id),
    sender_id INTEGER NOT NULL REFERENCES users(id),
    body TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
`);

// Lightweight forward-compatible migration for columns added after the
// initial CREATE TABLE above, so existing local/deployed DBs upgrade
// in place instead of needing a manual wipe. SQLite has no
// "ADD COLUMN IF NOT EXISTS", so we check pragma table_info first.
// Returns true if the column was actually added (false if it already
// existed) — callers use this to run one-time backfill logic only on a
// genuine upgrade, not on a fresh install where the CREATE TABLE above
// already has the right defaults.
function ensureColumn(table, column, definition) {
  const existing = db.prepare(`PRAGMA table_info(${table})`).all();
  const hasColumn = existing.some((col) => col.name === column);
  if (!hasColumn) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
    return true;
  }
  return false;
}

ensureColumn('users', 'role', "TEXT NOT NULL DEFAULT 'viewer'");
ensureColumn('users', 'has_master_access', 'INTEGER NOT NULL DEFAULT 0');
ensureColumn('assets', 'uploaded_by', 'INTEGER REFERENCES users(id)');
ensureColumn('assets', 'folder_id', 'TEXT REFERENCES folders(id)');
ensureColumn('access_log', 'asset_title', 'TEXT');
ensureColumn('access_log', 'user_email', 'TEXT');
const emailVerifiedColumnIsNew = ensureColumn('users', 'email_verified', 'INTEGER NOT NULL DEFAULT 0');
ensureColumn('users', 'signup_status', "TEXT NOT NULL DEFAULT 'active'");
ensureColumn('asset_grants', 'watermark_enabled', 'INTEGER NOT NULL DEFAULT 1');

// SQLite can't ALTER a CHECK constraint in place, so widening
// assets.type to allow 'html' (added after the original 'image'/'video'/
// 'snippet' set) requires a rebuild-and-swap on any DB created before this
// change. Detected by checking the table's own SQL text for the new value
// — idempotent, a no-op on both fresh installs (already correct) and DBs
// that have already been migrated once.
const assetsTableSql = db
  .prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'assets'")
  .get();
if (assetsTableSql && !assetsTableSql.sql.includes("'html'")) {
  // asset_grants (and access_log, though that one has no real FK — see its
  // own comment) hold rows referencing assets.id, so this rebuild has to
  // happen with foreign key enforcement OFF, or SQLite refuses the DROP
  // TABLE partway through with SQLITE_CONSTRAINT_FOREIGNKEY. PRAGMA
  // foreign_keys is a documented no-op inside a transaction, so it's
  // toggled outside of one, matching SQLite's own recommended
  // "12-step" procedure for changing a table referenced by others.
  db.pragma('foreign_keys = OFF');
  db.transaction(() => {
    db.exec(`
      CREATE TABLE assets_new (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL CHECK (type IN ('image', 'video', 'snippet', 'html')),
        title TEXT NOT NULL,
        file_path TEXT NOT NULL,
        folder_id TEXT REFERENCES folders(id),
        uploaded_by INTEGER REFERENCES users(id),
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      INSERT INTO assets_new SELECT id, type, title, file_path, folder_id, uploaded_by, created_at FROM assets;
      DROP TABLE assets;
      ALTER TABLE assets_new RENAME TO assets;
    `);
  })();
  db.pragma('foreign_key_check');
  db.pragma('foreign_keys = ON');
}

// Existing accounts (from before this feature existed) should not suddenly
// be locked out by the new email-verification requirement — grandfather
// them in as already verified/active, but only as a one-time backfill on a
// genuine upgrade (i.e. this boot is the one that just added the column).
// A fresh install never runs this: new registrations from here on go
// through the real verification flow and should NOT be auto-verified.
if (emailVerifiedColumnIsNew) {
  db.prepare("UPDATE users SET email_verified = 1, signup_status = 'active'").run();
}

// Best-effort backfill: fill in user_email for existing access_log rows
// from the still-live users table, wherever the account hasn't been
// deleted yet. Harmless to re-run (only touches rows where it's still
// NULL); rows for already-deleted users stay NULL, same as if they'd been
// deleted after this ran.
db.exec(`
  UPDATE access_log
  SET user_email = (SELECT email FROM users WHERE users.id = access_log.user_id)
  WHERE user_email IS NULL
`);

module.exports = db;
