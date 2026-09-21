const { isAdmin } = require('../lib/permissions');

// Requires an authenticated user (run after requireAuth) with admin or
// owner role. Does not require master access — use requireMasterAccess
// for owner-level actions.
function requireAdmin(req, res, next) {
  if (!isAdmin(req.user)) {
    return res.status(403).json({ error: 'Admin access required' });
  }
  next();
}

module.exports = requireAdmin;
