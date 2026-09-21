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
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('viewer', 'admin', 'owner')),
    has_master_access INTEGER NOT NULL DEFAULT 0,
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

  CREATE TABLE IF NOT EXISTS assets (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('image', 'video', 'snippet')),
    title TEXT NOT NULL,
    file_path TEXT NOT NULL,
    folder_id TEXT REFERENCES folders(id),
    uploaded_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Per-user, per-asset access grants. Kept for assets at root (no folder)
  -- or for granting a single asset without granting its whole folder.
  -- Admins/owner always have implicit access to everything.
  CREATE TABLE IF NOT EXISTS asset_grants (
    user_id INTEGER NOT NULL REFERENCES users(id),
    asset_id TEXT NOT NULL REFERENCES assets(id),
    granted_by INTEGER NOT NULL REFERENCES users(id),
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
  -- log stays human-readable even after the asset row is gone.
  CREATE TABLE IF NOT EXISTS access_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
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
function ensureColumn(table, column, definition) {
  const existing = db.prepare(`PRAGMA table_info(${table})`).all();
  const hasColumn = existing.some((col) => col.name === column);
  if (!hasColumn) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  }
}

ensureColumn('users', 'role', "TEXT NOT NULL DEFAULT 'viewer'");
ensureColumn('users', 'has_master_access', 'INTEGER NOT NULL DEFAULT 0');
ensureColumn('assets', 'uploaded_by', 'INTEGER REFERENCES users(id)');
ensureColumn('assets', 'folder_id', 'TEXT REFERENCES folders(id)');
ensureColumn('access_log', 'asset_title', 'TEXT');

module.exports = db;
