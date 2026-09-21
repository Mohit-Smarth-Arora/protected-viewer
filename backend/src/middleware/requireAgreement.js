const db = require('../lib/db');

// Blocks access to protected content until the user has clicked through the
// no-redistribution agreement. This is a legal/deterrence control, not a
// technical one — see roadmap Phase 1. It pairs with access_log to give
// actual recourse if content leaks.
function requireAgreement(req, res, next) {
  const row = db.prepare('SELECT version FROM agreements WHERE user_id = ?').get(req.user.id);
  if (!row) {
    return res.status(403).json({ error: 'Agreement not accepted', code: 'AGREEMENT_REQUIRED' });
  }
  next();
}

module.exports = requireAgreement;
