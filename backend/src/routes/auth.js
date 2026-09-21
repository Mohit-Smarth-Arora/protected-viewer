const express = require('express');
const db = require('../lib/db');
const { hashPassword, verifyPassword, issueSessionToken } = require('../lib/auth');
const requireAuth = require('../middleware/requireAuth');
const { uploadAdminPhoto } = require('../lib/uploads');
const { STORAGE_ROOT } = require('../lib/paths');
const path = require('path');

const router = express.Router();

const AGREEMENT_VERSION = '2026-09-21';

function isValidEmail(email) {
  return typeof email === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

// NOTE: open self-registration is fine for development. Before sharing this
// with real external viewers, replace this with invite-only account creation
// (you create accounts for the specific people you're sharing with) — open
// signup defeats the point of "not full access to just anyone."
router.post('/register', async (req, res) => {
  const { email, password, displayName } = req.body || {};

  if (!isValidEmail(email)) {
    return res.status(400).json({ error: 'Valid email is required' });
  }
  if (typeof password !== 'string' || password.length < 10) {
    return res.status(400).json({ error: 'Password must be at least 10 characters' });
  }
  if (typeof displayName !== 'string' || displayName.trim().length === 0) {
    return res.status(400).json({ error: 'Display name is required' });
  }

  const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email.toLowerCase());
  if (existing) {
    return res.status(409).json({ error: 'An account with this email already exists' });
  }

  const passwordHash = await hashPassword(password);
  const info = db
    .prepare('INSERT INTO users (email, password_hash, display_name) VALUES (?, ?, ?)')
    .run(email.toLowerCase(), passwordHash, displayName.trim());

  const user = { id: info.lastInsertRowid, email: email.toLowerCase(), display_name: displayName.trim() };
  const token = issueSessionToken(user);

  res.status(201).json({ token, user: { id: user.id, email: user.email, displayName: user.display_name } });
});

router.post('/login', async (req, res) => {
  const { email, password } = req.body || {};

  if (!isValidEmail(email) || typeof password !== 'string') {
    return res.status(400).json({ error: 'Email and password are required' });
  }

  const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email.toLowerCase());
  // Constant-shape response whether the user exists or not, to avoid
  // leaking which emails are registered via response timing/content.
  const dummyHash = '$2b$12$C6UzMDM.H6dfI/f/IKcEeOfRfvSTf5D1Zg3v6H8n0z0oX2v7X6c3G';
  const ok = await verifyPassword(password, user ? user.password_hash : dummyHash);

  if (!user || !ok) {
    return res.status(401).json({ error: 'Invalid email or password' });
  }

  const token = issueSessionToken(user);
  res.json({ token, user: { id: user.id, email: user.email, displayName: user.display_name } });
});

router.get('/me', requireAuth, (req, res) => {
  const agreement = db.prepare('SELECT version FROM agreements WHERE user_id = ?').get(req.user.id);
  res.json({
    user: req.user,
    agreementAccepted: !!agreement && agreement.version === AGREEMENT_VERSION,
    agreementVersion: AGREEMENT_VERSION,
  });
});

router.post('/agreement/accept', requireAuth, (req, res) => {
  db.prepare(
    `INSERT INTO agreements (user_id, version) VALUES (?, ?)
     ON CONFLICT(user_id) DO UPDATE SET version = excluded.version, accepted_at = datetime('now')`
  ).run(req.user.id, AGREEMENT_VERSION);
  res.json({ ok: true, agreementVersion: AGREEMENT_VERSION });
});

// Submits (or re-submits after a rejection) a request to become an admin.
// Requires being logged in as a plain viewer first — this is an upgrade
// request on an existing account, not a separate signup path. Approval
// happens later via the admin-requests review routes (routes/admin.js).
router.post('/admin-request', requireAuth, uploadAdminPhoto.single('photo'), (req, res) => {
  if (req.user.role !== 'viewer') {
    return res.status(400).json({ error: 'Only viewer accounts can request admin access' });
  }

  const { fullLegalName, phoneNumber, organization, reason } = req.body || {};

  if (typeof fullLegalName !== 'string' || fullLegalName.trim().length === 0) {
    return res.status(400).json({ error: 'Full legal name is required' });
  }
  if (typeof phoneNumber !== 'string' || phoneNumber.trim().length === 0) {
    return res.status(400).json({ error: 'Phone number is required' });
  }
  if (typeof reason !== 'string' || reason.trim().length === 0) {
    return res.status(400).json({ error: 'Reason for admin access is required' });
  }
  if (!req.file) {
    return res.status(400).json({ error: 'A passport-size photo is required' });
  }

  const existingPending = db
    .prepare("SELECT id FROM admin_requests WHERE user_id = ? AND status = 'pending'")
    .get(req.user.id);
  if (existingPending) {
    return res.status(409).json({ error: 'You already have a pending admin request' });
  }

  const photoRelativePath = path.join(
    'admin_photos',
    path.relative(path.join(STORAGE_ROOT, 'admin_photos'), req.file.path)
  );

  const info = db
    .prepare(
      `INSERT INTO admin_requests
        (user_id, full_legal_name, phone_number, organization, reason, photo_path)
       VALUES (?, ?, ?, ?, ?, ?)`
    )
    .run(
      req.user.id,
      fullLegalName.trim(),
      phoneNumber.trim(),
      organization ? organization.trim() : null,
      reason.trim(),
      photoRelativePath
    );

  res.status(201).json({ ok: true, requestId: info.lastInsertRowid, status: 'pending' });
});

module.exports = router;
