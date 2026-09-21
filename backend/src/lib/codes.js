const crypto = require('crypto');

// 6-digit numeric code for email verification — easy to type/read, short
// expiry (see auth.js) keeps the small keyspace an acceptable tradeoff.
function generateVerificationCode() {
  return crypto.randomInt(100000, 1000000).toString();
}

// Referral codes: short, human-shareable (e.g. spoken/typed over chat),
// uppercase alphanumeric with ambiguous characters (0/O, 1/I/L) excluded.
const REFERRAL_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
function generateReferralCode(length = 8) {
  let code = '';
  const bytes = crypto.randomBytes(length);
  for (let i = 0; i < length; i++) {
    code += REFERRAL_ALPHABET[bytes[i] % REFERRAL_ALPHABET.length];
  }
  return code;
}

module.exports = { generateVerificationCode, generateReferralCode };
