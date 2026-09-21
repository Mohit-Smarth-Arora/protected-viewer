const express = require('express');
const fs = require('fs');
const path = require('path');
const db = require('../lib/db');
const requireAuth = require('../middleware/requireAuth');
const requireAgreement = require('../middleware/requireAgreement');
const requireActiveAccount = require('../middleware/requireActiveAccount');
const { issueAssetToken, verifyAssetToken } = require('../lib/auth');
const { watermarkImage, watermarkCodeSnippet } = require('../lib/watermark');
const { STORAGE_ROOT } = require('../lib/paths');
const { isAdmin } = require('../lib/permissions');
const { hasAccessToAsset: folderAwareHasAccessToAsset, hasAccessToFolder } = require('../lib/folders');

const router = express.Router();
const ASSET_TOKEN_TTL = parseInt(process.env.ASSET_TOKEN_TTL_SECONDS || '120', 10);

function logAccess(req, userId, assetId, action, assetTitle, userEmail) {
  db.prepare(
    'INSERT INTO access_log (user_id, user_email, asset_id, asset_title, action, ip, user_agent) VALUES (?, ?, ?, ?, ?, ?, ?)'
  ).run(userId, userEmail || null, assetId, assetTitle || null, action, req.ip, req.headers['user-agent'] || null);
}

// Admins/owner implicitly see and can request tokens for everything (they
// manage the library). Plain viewers only get assets granted directly, or
// via a folder (or ancestor folder) grant — see lib/folders.js.
function hasAccessToAsset(user, asset) {
  if (isAdmin(user)) return true;
  return folderAwareHasAccessToAsset(user.id, asset);
}

// Lists both folders and assets within a given parent folder (or root when
// folderId is omitted/null) — mirrors a typical file-browser "list this
// directory" call. Viewers only see folders/assets they have access to;
// admins/owner see everything. A folder is included for a viewer if it's
// directly granted, an ancestor is granted, OR it contains (transitively)
// something granted — so browsing down to a granted subfolder is possible
// without granting every ancestor explicitly.
router.get('/', requireAuth, requireActiveAccount, requireAgreement, (req, res) => {
  const folderId = req.query.folderId || null;

  if (isAdmin(req.user)) {
    const folders = folderId
      ? db.prepare('SELECT id, name, created_at FROM folders WHERE parent_id = ? ORDER BY name').all(folderId)
      : db.prepare('SELECT id, name, created_at FROM folders WHERE parent_id IS NULL ORDER BY name').all();
    const assets = folderId
      ? db.prepare('SELECT id, type, title, created_at FROM assets WHERE folder_id = ? ORDER BY created_at DESC').all(folderId)
      : db.prepare('SELECT id, type, title, created_at FROM assets WHERE folder_id IS NULL ORDER BY created_at DESC').all();
    return res.json({ folders, assets });
  }

  // Viewer: only folders/assets in this directory that are (transitively)
  // accessible to them.
  const childFolders = folderId
    ? db.prepare('SELECT id, name, created_at FROM folders WHERE parent_id = ? ORDER BY name').all(folderId)
    : db.prepare('SELECT id, name, created_at FROM folders WHERE parent_id IS NULL ORDER BY name').all();
  const visibleFolders = childFolders.filter((f) => folderContainsAnyAccessible(req.user.id, f.id));

  const childAssets = folderId
    ? db.prepare('SELECT id, type, title, folder_id, created_at FROM assets WHERE folder_id = ?').all(folderId)
    : db.prepare('SELECT id, type, title, folder_id, created_at FROM assets WHERE folder_id IS NULL').all();
  const visibleAssets = childAssets
    .filter((a) => hasAccessToAsset(req.user, a))
    .map(({ id, type, title, created_at }) => ({ id, type, title, created_at }));

  res.json({ folders: visibleFolders, assets: visibleAssets });
});

// Does this folder subtree contain anything (asset or nested folder grant)
// accessible to the user? Used only to decide whether to show a folder in
// a viewer's listing when they weren't granted that folder directly but
// were granted something inside it.
function folderContainsAnyAccessible(userId, folderId) {
  if (hasAccessToFolder(userId, folderId)) return true;
  const assetsHere = db.prepare('SELECT id, folder_id FROM assets WHERE folder_id = ?').all(folderId);
  if (assetsHere.some((a) => folderAwareHasAccessToAsset(userId, a))) return true;
  const subfolders = db.prepare('SELECT id FROM folders WHERE parent_id = ?').all(folderId);
  return subfolders.some((f) => folderContainsAnyAccessible(userId, f.id));
}

// Step 1: client asks for permission to view a specific asset. Server issues
// a short-lived, single-asset-scoped token. This is the "signed URL" pattern
// — the token can't be reused for a different asset and expires quickly.
router.post('/:id/token', requireAuth, requireActiveAccount, requireAgreement, (req, res) => {
  const asset = db.prepare('SELECT id, title, folder_id FROM assets WHERE id = ?').get(req.params.id);
  if (!asset) return res.status(404).json({ error: 'Asset not found' });
  if (!hasAccessToAsset(req.user, asset)) {
    return res.status(403).json({ error: 'You do not have access to this asset' });
  }

  const token = issueAssetToken(req.user.id, asset.id, ASSET_TOKEN_TTL);
  logAccess(req, req.user.id, asset.id, 'token_issued', asset.title, req.user.email);

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

  logAccess(req, user.id, asset.id, 'content_viewed', asset.title, user.email);

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
