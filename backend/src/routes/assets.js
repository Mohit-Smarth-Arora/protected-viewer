const express = require('express');
const fs = require('fs');
const path = require('path');
const db = require('../lib/db');
const requireAuth = require('../middleware/requireAuth');
const requireAgreement = require('../middleware/requireAgreement');
const { issueAssetToken, verifyAssetToken } = require('../lib/auth');
const { watermarkImage, watermarkCodeSnippet } = require('../lib/watermark');
const { STORAGE_ROOT } = require('../lib/paths');
const { isAdmin } = require('../lib/permissions');

const router = express.Router();
const ASSET_TOKEN_TTL = parseInt(process.env.ASSET_TOKEN_TTL_SECONDS || '120', 10);

function logAccess(req, userId, assetId, action) {
  db.prepare(
    'INSERT INTO access_log (user_id, asset_id, action, ip, user_agent) VALUES (?, ?, ?, ?, ?)'
  ).run(userId, assetId, action, req.ip, req.headers['user-agent'] || null);
}

// Admins/owner implicitly see and can request tokens for everything (they
// manage the library). Plain viewers only get assets explicitly granted to
// them via asset_grants — see routes/admin.js grants endpoints.
function hasAccessToAsset(user, assetId) {
  if (isAdmin(user)) return true;
  const grant = db
    .prepare('SELECT 1 FROM asset_grants WHERE user_id = ? AND asset_id = ?')
    .get(user.id, assetId);
  return !!grant;
}

// List available assets (metadata only — no file bytes here). Viewers only
// see assets they've been granted; admins/owner see everything.
router.get('/', requireAuth, requireAgreement, (req, res) => {
  const rows = isAdmin(req.user)
    ? db.prepare('SELECT id, type, title, created_at FROM assets ORDER BY created_at DESC').all()
    : db
        .prepare(
          `SELECT a.id, a.type, a.title, a.created_at
           FROM assets a JOIN asset_grants g ON g.asset_id = a.id
           WHERE g.user_id = ?
           ORDER BY a.created_at DESC`
        )
        .all(req.user.id);
  res.json({ assets: rows });
});

// Step 1: client asks for permission to view a specific asset. Server issues
// a short-lived, single-asset-scoped token. This is the "signed URL" pattern
// — the token can't be reused for a different asset and expires quickly.
router.post('/:id/token', requireAuth, requireAgreement, (req, res) => {
  const asset = db.prepare('SELECT id FROM assets WHERE id = ?').get(req.params.id);
  if (!asset) return res.status(404).json({ error: 'Asset not found' });
  if (!hasAccessToAsset(req.user, asset.id)) {
    return res.status(403).json({ error: 'You do not have access to this asset' });
  }

  const token = issueAssetToken(req.user.id, asset.id, ASSET_TOKEN_TTL);
  logAccess(req, req.user.id, asset.id, 'token_issued');

  res.json({ token, expiresIn: ASSET_TOKEN_TTL });
});

// Step 2: client fetches the actual (watermarked) bytes using the token from
// step 1. This is the ONLY route that returns asset bytes, and it always
// watermarks before sending — the raw file on disk never goes over the wire.
router.get('/:id/content', async (req, res) => {
  const token = req.query.token;
  if (!token) return res.status(401).json({ error: 'Missing asset token' });

  let payload;
  try {
    payload = verifyAssetToken(token);
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired asset token' });
  }

  if (payload.assetId !== req.params.id) {
    return res.status(403).json({ error: 'Token does not match requested asset' });
  }

  const asset = db.prepare('SELECT * FROM assets WHERE id = ?').get(req.params.id);
  if (!asset) return res.status(404).json({ error: 'Asset not found' });

  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(payload.sub);
  if (!user) return res.status(401).json({ error: 'User no longer exists' });

  const label = `${user.email} • ${new Date().toISOString()}`;
  const absolutePath = path.join(STORAGE_ROOT, asset.file_path);

  logAccess(req, user.id, asset.id, 'content_viewed');

  try {
    if (asset.type === 'image') {
      const buffer = await watermarkImage(absolutePath, label);
      res.set('Content-Type', 'image/png');
      res.set('Cache-Control', 'no-store');
      return res.send(buffer);
    }

    if (asset.type === 'snippet') {
      const code = fs.readFileSync(absolutePath, 'utf8');
      const buffer = await watermarkCodeSnippet(code, label);
      res.set('Content-Type', 'image/png');
      res.set('Cache-Control', 'no-store');
      return res.send(buffer);
    }

    // Video watermarking (ffmpeg/HLS pipeline) lands in a later step —
    // Phase 1 covers images + snippets first per the roadmap.
    return res.status(501).json({ error: 'Video streaming not implemented yet' });
  } catch (err) {
    console.error('Watermarking failed:', err);
    return res.status(500).json({ error: 'Failed to render asset' });
  }
});

module.exports = router;
