const express = require('express');
const db = require('../lib/db');
const { hashPassword, verifyPassword, issueSessionToken } = require('../lib/auth');
const requireAuth = require('../middleware/requireAuth');
const { uploadAdminPhoto } = require('../lib/uploads');
const { STORAGE_ROOT } = require('../lib/paths');
const { sendVerificationEmail } = require('../lib/email');
const { generateVerificationCode } = require('../lib/codes');
const path = require('path');

const router = express.Router();

const AGREEMENT_VERSION = '2026-09-21';
const VERIFICATION_CODE_TTL_MINUTES = 30;

function isValidEmail(email) {
  return typeof email === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function issueAndSendVerificationCode(userId, email) {
  const code = generateVerificationCode();
  db.prepare(
    `INSERT INTO email_verification_codes (user_id, code, expires_at)
     VALUES (?, ?, datetime('now', '+${VERIFICATION_CODE_TTL_MINUTES} minutes'))`
  ).run(userId, code);
  // Fire-and-forget from the caller's perspective — email delivery
  // failures shouldn't fail registration itself (see lib/email.js: logs
  // the code to console when SendGrid isn't configured, so local dev and
  // testing work without a real provider).
  return sendVerificationEmail(email, code).catch((err) => {
    console.error('Failed to send verification email:', err);
  });
}

// Registration always creates the account with email_verified=0. A valid,
// active referral code is checked and recorded now (not consumed until
// verification succeeds, so an abandoned/unverified registration doesn't
// burn anyone's referral usage count) — see verify-email below for how it
// determines signup_status.
router.post('/register', async (req, res) => {
  const { email, password, displayName, referralCode } = req.body || {};

  if (!isValidEmail(email)) {
    return res.status(400).json({ error: 'Valid email is required' });
  }
  if (typeof password !== 'string' || password.length < 10) {
    return res.status(400).json({ error: 'Password must be at least 10 characters' });
  }
  if (typeof displayName !== 'string' || displayName.trim().length === 0) {
    return res.status(400).json({ error: 'Display name is required' });
  }

  let validReferralCode = null;
  if (referralCode && typeof referralCode === 'string' && referralCode.trim().length > 0) {
    const normalizedCode = referralCode.trim().toUpperCase();
    const row = db
      .prepare('SELECT code FROM referral_codes WHERE code = ? AND is_active = 1')
      .get(normalizedCode);
    if (!row) {
      return res.status(400).json({ error: 'Referral code is invalid or no longer active' });
    }
    validReferralCode = normalizedCode;
  }

  const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email.toLowerCase());
  if (existing) {
    return res.status(409).json({ error: 'An account with this email already exists' });
  }

  const passwordHash = await hashPassword(password);
  const info = db
    .prepare('INSERT INTO users (email, password_hash, display_name) VALUES (?, ?, ?)')
    .run(email.toLowerCase(), passwordHash, displayName.trim());

  const userId = info.lastInsertRowid;
  await issueAndSendVerificationCode(userId, email.toLowerCase());

  const user = { id: userId, email: email.toLowerCase(), display_name: displayName.trim() };
  const token = issueSessionToken(user);

  res.status(201).json({
    token,
    user: { id: user.id, email: user.email, displayName: user.display_name },
    // Client stashes this locally just to pass it back to /verify-email —
    // the server is the source of truth on whether it's actually valid;
    // this only avoids asking the user to retype the code they entered.
    pendingReferralCode: validReferralCode,
  });
});

// Verifies the 6-digit code. On success: if a valid referral code was
// supplied at registration, the account goes straight to signup_status
// 'active' and the code's uses_count increments. Otherwise a
// signup_requests row is created and the account stays 'pending_approval'
// until any admin approves it (see routes/admin.js /signup-requests).
router.post('/verify-email', requireAuth, (req, res) => {
  const { code, referralCode } = req.body || {};
  if (typeof code !== 'string' || code.trim().length === 0) {
    return res.status(400).json({ error: 'Verification code is required' });
  }

  if (req.user.email_verified) {
    return res.status(400).json({ error: 'Email is already verified' });
  }

  const codeRow = db
    .prepare(
      `SELECT * FROM email_verification_codes
       WHERE user_id = ? AND code = ? AND used_at IS NULL AND expires_at > datetime('now')
       ORDER BY id DESC LIMIT 1`
    )
    .get(req.user.id, code.trim());

  if (!codeRow) {
    return res.status(400).json({ error: 'Invalid or expired verification code' });
  }

  db.prepare('UPDATE email_verification_codes SET used_at = datetime(\'now\') WHERE id = ?').run(codeRow.id);

  let referralApplied = false;
  if (referralCode && typeof referralCode === 'string' && referralCode.trim().length > 0) {
    const normalizedCode = referralCode.trim().toUpperCase();
    const referral = db
      .prepare('SELECT code FROM referral_codes WHERE code = ? AND is_active = 1')
      .get(normalizedCode);
    if (referral) {
      db.prepare('UPDATE referral_codes SET uses_count = uses_count + 1 WHERE code = ?').run(normalizedCode);
      referralApplied = true;
    }
  }

  if (referralApplied) {
    db.prepare("UPDATE users SET email_verified = 1, signup_status = 'active' WHERE id = ?").run(req.user.id);
  } else {
    db.prepare("UPDATE users SET email_verified = 1, signup_status = 'pending_approval' WHERE id = ?").run(
      req.user.id
    );
    db.prepare('INSERT INTO signup_requests (user_id) VALUES (?)').run(req.user.id);
  }

  res.json({ ok: true, signupStatus: referralApplied ? 'active' : 'pending_approval' });
});

router.post('/resend-verification', requireAuth, async (req, res) => {
  if (req.user.email_verified) {
    return res.status(400).json({ error: 'Email is already verified' });
  }
  await issueAndSendVerificationCode(req.user.id, req.user.email);
  res.json({ ok: true });
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

  db.prepare('INSERT INTO login_events (user_id, ip, user_agent) VALUES (?, ?, ?)').run(
    user.id,
    req.ip,
    req.headers['user-agent'] || null
  );

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

// Heartbeat for the "active now" admin view (routes/admin.js /activity/online).
// Client calls this periodically while the app is open/foregrounded; "online"
// is derived at read time as "last_seen_at within N minutes", not stored as
// a boolean, so there's nothing to explicitly clear on sign-out/close.
router.post('/heartbeat', requireAuth, (req, res) => {
  db.prepare(
    `INSERT INTO user_presence (user_id, last_seen_at) VALUES (?, datetime('now'))
     ON CONFLICT(user_id) DO UPDATE SET last_seen_at = datetime('now')`
  ).run(req.user.id);
  res.json({ ok: true });
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
