const express = require('express');
const db = require('../lib/db');
const { hashPassword } = require('../lib/auth');

const router = express.Router();

// One-time-use-in-spirit owner bootstrap endpoint, for environments where
// shelling into the container (e.g. Railway SSH) isn't practical. Guarded
// by SETUP_SECRET, a random value set only via the platform's env vars,
// never committed to git. If SETUP_SECRET is unset, this route is fully
// disabled (returns 404) — so it's inert by default and only reachable
// when a deploy operator deliberately turns it on.
//
// Intended usage: set SETUP_SECRET, call this once to promote the real
// owner account, then unset SETUP_SECRET (or remove this route entirely)
// so the endpoint stops being reachable at all. See backend/README.md.
router.post('/owner', async (req, res) => {
  const configuredSecret = process.env.SETUP_SECRET;
  if (!configuredSecret) {
    return res.status(404).json({ error: 'Not found' });
  }

  const { secret, email, password, displayName } = req.body || {};
  if (secret !== configuredSecret) {
    return res.status(403).json({ error: 'Invalid setup secret' });
  }
  if (typeof email !== 'string' || !email.includes('@')) {
    return res.status(400).json({ error: 'Valid email is required' });
  }

  const existing = db.prepare('SELECT id, role FROM users WHERE email = ?').get(email.toLowerCase());

  if (existing) {
    db.prepare("UPDATE users SET role = 'owner' WHERE id = ?").run(existing.id);
    return res.json({ ok: true, action: 'promoted', userId: existing.id });
  }

  if (!password || !displayName) {
    return res.status(400).json({ error: 'password and displayName are required to create a new account' });
  }

  const passwordHash = await hashPassword(password);
  const info = db
    .prepare("INSERT INTO users (email, password_hash, display_name, role) VALUES (?, ?, ?, 'owner')")
    .run(email.toLowerCase(), passwordHash, displayName);

  res.json({ ok: true, action: 'created', userId: info.lastInsertRowid });
});

module.exports = router;
