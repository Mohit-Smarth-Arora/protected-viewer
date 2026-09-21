const { verifySessionToken } = require('../lib/auth');
const db = require('../lib/db');

// Verifies the session JWT from the Authorization header and attaches the
// current user row to req.user. Re-reads the user from DB (not just the
// token payload) so a deleted/disabled account is rejected immediately
// rather than waiting out the token's remaining lifetime.
function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ error: 'Missing or malformed Authorization header' });
  }

  let payload;
  try {
    payload = verifySessionToken(token);
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired session' });
  }

  const user = db.prepare('SELECT id, email, display_name FROM users WHERE id = ?').get(payload.sub);
  if (!user) {
    return res.status(401).json({ error: 'User no longer exists' });
  }

  req.user = user;
  next();
}

module.exports = requireAuth;
