const express = require('express');
const db = require('../lib/db');
const { hashPassword, verifyPassword, issueSessionToken } = require('../lib/auth');
const requireAuth = require('../middleware/requireAuth');

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

module.exports = router;
