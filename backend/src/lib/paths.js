const path = require('path');

// STORAGE_ROOT points at durable storage for everything that must survive a
// redeploy: the SQLite DB and the raw asset source files. Locally this is
// just backend/ (data/ and assets/ live there as before). In production
// (Railway) it's the mounted volume path, set via STORAGE_ROOT env var, so
// both the DB and the source assets a deploy needs are on the one volume
// Railway allows per service.
const STORAGE_ROOT = process.env.STORAGE_ROOT || path.join(__dirname, '..', '..');

const dataDir = path.join(STORAGE_ROOT, 'data');
const assetsDir = path.join(STORAGE_ROOT, 'assets');

module.exports = { STORAGE_ROOT, dataDir, assetsDir };
