const { hasMasterAccess } = require('../lib/permissions');

// Requires an authenticated user (run after requireAuth) who is the owner,
// or an admin with has_master_access toggled on. Gates owner-level actions:
// reviewing admin requests, toggling other admins' master access.
function requireMasterAccess(req, res, next) {
  if (!hasMasterAccess(req.user)) {
    return res.status(403).json({ error: 'Master access required' });
  }
  next();
}

module.exports = requireMasterAccess;
