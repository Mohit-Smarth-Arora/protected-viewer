const express = require('express');
const fs = require('fs');
const path = require('path');
const { nanoid } = require('nanoid');
const db = require('../lib/db');
const requireAuth = require('../middleware/requireAuth');
const requireAdmin = require('../middleware/requireAdmin');
const requireMasterAccess = require('../middleware/requireMasterAccess');
const { uploadAssetToMemory } = require('../lib/uploads');
const { assetsDir, STORAGE_ROOT } = require('../lib/paths');
const { hasMasterAccess } = require('../lib/permissions');

const router = express.Router();

// Every route in this file requires at least plain admin. Specific routes
// additionally require requireMasterAccess for owner-level actions.
router.use(requireAuth, requireAdmin);

// ---- Admin request review (master access only) -----------------------

router.get('/admin-requests', requireMasterAccess, (req, res) => {
  const status = req.query.status || 'pending';
  const rows = db
    .prepare(
      `SELECT ar.id, ar.full_legal_name, ar.phone_number, ar.organization, ar.reason,
              ar.status, ar.created_at, u.id AS user_id, u.email, u.display_name
       FROM admin_requests ar
       JOIN users u ON u.id = ar.user_id
       WHERE ar.status = ?
       ORDER BY ar.created_at DESC`
    )
    .all(status);
  res.json({ requests: rows });
});

// Serves the applicant's verification photo. Not under /api/assets —
// deliberately separate route, master-access only, never watermarked
// (it's for your own manual review, not something meant to circulate).
router.get('/admin-requests/:id/photo', requireMasterAccess, (req, res) => {
  const request = db.prepare('SELECT photo_path FROM admin_requests WHERE id = ?').get(req.params.id);
  if (!request) return res.status(404).json({ error: 'Request not found' });
  const absolutePath = path.join(STORAGE_ROOT, request.photo_path);
  if (!fs.existsSync(absolutePath)) return res.status(404).json({ error: 'Photo not found' });
  res.sendFile(absolutePath);
});

router.post('/admin-requests/:id/approve', requireMasterAccess, (req, res) => {
  const request = db.prepare("SELECT * FROM admin_requests WHERE id = ? AND status = 'pending'").get(req.params.id);
  if (!request) return res.status(404).json({ error: 'Pending request not found' });

  const grantMaster = req.body?.grantMasterAccess === true;

  db.prepare("UPDATE users SET role = 'admin', has_master_access = ? WHERE id = ?").run(
    grantMaster ? 1 : 0,
    request.user_id
  );
  db.prepare(
    "UPDATE admin_requests SET status = 'approved', reviewed_by = ?, reviewed_at = datetime('now') WHERE id = ?"
  ).run(req.user.id, request.id);

  res.json({ ok: true });
});

router.post('/admin-requests/:id/reject', requireMasterAccess, (req, res) => {
  const request = db.prepare("SELECT * FROM admin_requests WHERE id = ? AND status = 'pending'").get(req.params.id);
  if (!request) return res.status(404).json({ error: 'Pending request not found' });

  db.prepare(
    "UPDATE admin_requests SET status = 'rejected', reviewed_by = ?, reviewed_at = datetime('now') WHERE id = ?"
  ).run(req.user.id, request.id);

  res.json({ ok: true });
});

// ---- Managing existing admins (master access only) --------------------

router.get('/admins', requireMasterAccess, (req, res) => {
  const rows = db
    .prepare("SELECT id, email, display_name, role, has_master_access FROM users WHERE role IN ('admin', 'owner')")
    .all();
  res.json({ admins: rows });
});

router.post('/admins/:id/master-access', requireMasterAccess, (req, res) => {
  const targetId = parseInt(req.params.id, 10);
  const target = db.prepare('SELECT * FROM users WHERE id = ?').get(targetId);
  if (!target) return res.status(404).json({ error: 'User not found' });
  if (target.role === 'owner') {
    return res.status(400).json({ error: "Owner's access cannot be modified" });
  }
  if (target.role !== 'admin') {
    return res.status(400).json({ error: 'Target is not an admin' });
  }

  const grant = req.body?.grant === true;
  db.prepare('UPDATE users SET has_master_access = ? WHERE id = ?').run(grant ? 1 : 0, targetId);
  res.json({ ok: true, hasMasterAccess: grant });
});

// ---- Asset upload (plain admin and up) ---------------------------------

router.post('/assets', uploadAssetToMemory.single('file'), async (req, res) => {
  const { type, title } = req.body || {};
  if (!['image', 'snippet'].includes(type)) {
    return res.status(400).json({ error: "type must be 'image' or 'snippet' (video not supported yet)" });
  }
  if (typeof title !== 'string' || title.trim().length === 0) {
    return res.status(400).json({ error: 'Title is required' });
  }
  if (!req.file) {
    return res.status(400).json({ error: 'File is required' });
  }

  const id = nanoid(10);
  const subDir = type === 'image' ? 'images' : 'snippets';
  const ext = path.extname(req.file.originalname) || (type === 'image' ? '.png' : '.py');
  const fileName = `${id}${ext}`;
  const destDir = path.join(assetsDir, subDir);
  if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });
  const destPath = path.join(destDir, fileName);

  fs.writeFileSync(destPath, req.file.buffer);

  const relativeFilePath = path.join('assets', subDir, fileName);
  db.prepare(
    'INSERT INTO assets (id, type, title, file_path, uploaded_by) VALUES (?, ?, ?, ?, ?)'
  ).run(id, type, title.trim(), relativeFilePath, req.user.id);

  res.status(201).json({ id, type, title: title.trim() });
});

router.get('/assets', (req, res) => {
  const rows = db
    .prepare(
      `SELECT a.id, a.type, a.title, a.created_at, u.display_name AS uploaded_by_name
       FROM assets a LEFT JOIN users u ON u.id = a.uploaded_by
       ORDER BY a.created_at DESC`
    )
    .all();
  res.json({ assets: rows });
});

router.delete('/assets/:id', (req, res) => {
  const asset = db.prepare('SELECT * FROM assets WHERE id = ?').get(req.params.id);
  if (!asset) return res.status(404).json({ error: 'Asset not found' });

  db.prepare('DELETE FROM asset_grants WHERE asset_id = ?').run(asset.id);
  db.prepare('DELETE FROM assets WHERE id = ?').run(asset.id);

  const absolutePath = path.join(STORAGE_ROOT, asset.file_path);
  if (fs.existsSync(absolutePath)) fs.unlinkSync(absolutePath);

  res.json({ ok: true });
});

// ---- Per-user asset grants (plain admin and up) ------------------------

router.get('/users', (req, res) => {
  const rows = db.prepare("SELECT id, email, display_name, role FROM users WHERE role = 'viewer'").all();
  res.json({ users: rows });
});

router.get('/assets/:id/grants', (req, res) => {
  const rows = db
    .prepare(
      `SELECT u.id AS user_id, u.email, u.display_name
       FROM asset_grants g JOIN users u ON u.id = g.user_id
       WHERE g.asset_id = ?`
    )
    .all(req.params.id);
  res.json({ grants: rows });
});

router.post('/assets/:id/grants', (req, res) => {
  const { userId } = req.body || {};
  const asset = db.prepare('SELECT id FROM assets WHERE id = ?').get(req.params.id);
  if (!asset) return res.status(404).json({ error: 'Asset not found' });
  const user = db.prepare("SELECT id FROM users WHERE id = ? AND role = 'viewer'").get(userId);
  if (!user) return res.status(404).json({ error: 'Viewer not found' });

  db.prepare(
    `INSERT INTO asset_grants (user_id, asset_id, granted_by) VALUES (?, ?, ?)
     ON CONFLICT(user_id, asset_id) DO NOTHING`
  ).run(userId, asset.id, req.user.id);

  res.status(201).json({ ok: true });
});

router.delete('/assets/:id/grants/:userId', (req, res) => {
  db.prepare('DELETE FROM asset_grants WHERE asset_id = ? AND user_id = ?').run(
    req.params.id,
    req.params.userId
  );
  res.json({ ok: true });
});

module.exports = router;
