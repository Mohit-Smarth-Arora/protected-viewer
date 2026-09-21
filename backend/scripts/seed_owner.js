// One-time setup: promotes an existing account (or creates one) to the
// 'owner' role. There should be exactly one owner. Run with:
//   node scripts/seed_owner.js <email> [password] [displayName]
// If the account already exists, only its role is updated (password/name
// args are ignored). If it doesn't exist, password and displayName become
// required to create it.
require('dotenv').config();
const db = require('../src/lib/db');
const { hashPassword } = require('../src/lib/auth');

async function main() {
  const [email, password, displayName] = process.argv.slice(2);
  if (!email) {
    console.error('Usage: node scripts/seed_owner.js <email> [password] [displayName]');
    process.exit(1);
  }

  const existing = db.prepare('SELECT id, role FROM users WHERE email = ?').get(email.toLowerCase());

  // email_verified/signup_status are set explicitly here (not left to the
  // email-verification flow) because running this script IS the trusted,
  // out-of-band verification — you (the operator) are asserting this
  // account is legitimate directly, the same way SETUP_SECRET does for the
  // HTTP owner-bootstrap path.
  if (existing) {
    db.prepare(
      "UPDATE users SET role = 'owner', email_verified = 1, signup_status = 'active' WHERE id = ?"
    ).run(existing.id);
    console.log(`Existing account ${email} (id=${existing.id}) promoted to owner.`);
    return;
  }

  if (!password || !displayName) {
    console.error('Account does not exist yet — password and displayName are required to create it.');
    process.exit(1);
  }

  const passwordHash = await hashPassword(password);
  const info = db
    .prepare(
      "INSERT INTO users (email, password_hash, display_name, role, email_verified, signup_status) VALUES (?, ?, ?, 'owner', 1, 'active')"
    )
    .run(email.toLowerCase(), passwordHash, displayName);
  console.log(`Created owner account ${email} (id=${info.lastInsertRowid}).`);
}

main();
