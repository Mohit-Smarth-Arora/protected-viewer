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

  CREATE TABLE IF NOT EXISTS assets (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('image', 'video', 'snippet')),
    title TEXT NOT NULL,
    file_path TEXT NOT NULL,
    uploaded_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Per-user, per-asset access grants. An asset is only listable/viewable
  -- by a viewer if a row exists here — admins/owner always have implicit
  -- access to everything they can manage (checked in code, not via a row).
  CREATE TABLE IF NOT EXISTS asset_grants (
    user_id INTEGER NOT NULL REFERENCES users(id),
    asset_id TEXT NOT NULL REFERENCES assets(id),
    granted_by INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, asset_id)
  );

  CREATE TABLE IF NOT EXISTS access_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    asset_id TEXT NOT NULL REFERENCES assets(id),
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

module.exports = db;
