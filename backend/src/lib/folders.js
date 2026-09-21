const db = require('./db');

// Returns [folderId, ...ancestorIds] walking up via parent_id, folderId
// first. Used to check "is this folder (or one of its ancestors) granted
// to this user" without needing a grant row per descendant folder.
function folderAncestorChain(folderId) {
  const chain = [];
  let current = folderId;
  const seen = new Set(); // guards against a corrupt cycle in parent_id
  while (current && !seen.has(current)) {
    chain.push(current);
    seen.add(current);
    const row = db.prepare('SELECT parent_id FROM folders WHERE id = ?').get(current);
    current = row ? row.parent_id : null;
  }
  return chain;
}

// A folder is accessible to a user if they have a folder_grants row for
// it OR any of its ancestors (granting a parent folder grants everything
// inside, per the roadmap decision — "like Google Drive").
function hasAccessToFolder(userId, folderId) {
  if (!folderId) return false;
  const chain = folderAncestorChain(folderId);
  if (chain.length === 0) return false;
  const placeholders = chain.map(() => '?').join(',');
  const row = db
    .prepare(`SELECT 1 FROM folder_grants WHERE user_id = ? AND folder_id IN (${placeholders})`)
    .get(userId, ...chain);
  return !!row;
}

// An asset is accessible to a viewer if it has a direct asset_grants row,
// OR it lives in a folder (or subfolder of a folder) granted to them.
function hasAccessToAsset(userId, asset) {
  const directGrant = db
    .prepare('SELECT 1 FROM asset_grants WHERE user_id = ? AND asset_id = ?')
    .get(userId, asset.id);
  if (directGrant) return true;
  if (asset.folder_id) return hasAccessToFolder(userId, asset.folder_id);
  return false;
}

// Full folder subtree (folder + all descendant folder ids), used when
// deleting a folder or listing "everything under here" for the admin UI.
function folderSubtreeIds(rootFolderId) {
  const ids = [rootFolderId];
  let frontier = [rootFolderId];
  while (frontier.length > 0) {
    const placeholders = frontier.map(() => '?').join(',');
    const children = db
      .prepare(`SELECT id FROM folders WHERE parent_id IN (${placeholders})`)
      .all(...frontier)
      .map((r) => r.id);
    ids.push(...children);
    frontier = children;
  }
  return ids;
}

module.exports = { folderAncestorChain, hasAccessToFolder, hasAccessToAsset, folderSubtreeIds };
