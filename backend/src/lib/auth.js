const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET;
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '8h';

if (!JWT_SECRET || JWT_SECRET.length < 32) {
  throw new Error('JWT_SECRET is missing or too short. Set a long random value in .env');
}

const SALT_ROUNDS = 12;

async function hashPassword(plain) {
  return bcrypt.hash(plain, SALT_ROUNDS);
}

async function verifyPassword(plain, hash) {
  return bcrypt.compare(plain, hash);
}

function issueSessionToken(user) {
  return jwt.sign(
    { sub: user.id, email: user.email, name: user.display_name },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRES_IN }
  );
}

function verifySessionToken(token) {
  return jwt.verify(token, JWT_SECRET); // throws on invalid/expired
}

// Short-lived, single-purpose token scoped to exactly one asset.
// This is what makes an asset URL "signed" — it can't be reused for a
// different asset and expires quickly, so it can't be bookmarked/shared usefully.
function issueAssetToken(userId, assetId, ttlSeconds) {
  return jwt.sign(
    { sub: userId, assetId, purpose: 'asset-access' },
    JWT_SECRET,
    { expiresIn: ttlSeconds }
  );
}

function verifyAssetToken(token) {
  const payload = jwt.verify(token, JWT_SECRET);
  if (payload.purpose !== 'asset-access') {
    throw new Error('Invalid token purpose');
  }
  return payload;
}

module.exports = {
  hashPassword,
  verifyPassword,
  issueSessionToken,
  verifySessionToken,
  issueAssetToken,
  verifyAssetToken,
};
