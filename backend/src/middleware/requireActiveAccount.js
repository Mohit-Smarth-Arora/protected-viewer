const { isAdmin } = require('../lib/permissions');

// Gates real app usage (assets, chat, etc.) behind having a fully-active
// account: email verified, and either signed up with a valid referral code
// or approved by an admin after the pending-approval review. Deliberately
// NOT applied to /me, /verify-email, /resend-verification, or auth routes
// themselves — a not-yet-active user still needs to reach those to
// actually become active.
//
// Admins/owner are exempt: their accounts predate this feature or were
// created through the admin-approval path already, and gating an admin's
// own account this way would risk locking out the person meant to approve
// others.
function requireActiveAccount(req, res, next) {
  if (isAdmin(req.user)) return next();

  if (!req.user.email_verified) {
    return res.status(403).json({ error: 'Email not verified', code: 'EMAIL_NOT_VERIFIED' });
  }
  if (req.user.signup_status !== 'active') {
    return res.status(403).json({ error: 'Account pending admin approval', code: 'PENDING_APPROVAL' });
  }
  next();
}

module.exports = requireActiveAccount;
