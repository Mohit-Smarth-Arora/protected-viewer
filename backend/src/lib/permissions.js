// Central place for role logic so route files don't each re-derive what
// counts as "admin enough" — the tiered model (from the roadmap
// discussion) is:
//   viewer: no admin powers. Can only see assets explicitly granted to them.
//   admin (has_master_access = 0): can upload assets and manage grants,
//     cannot review admin requests or touch other admins' access.
//   admin (has_master_access = 1): everything a plain admin can do, plus
//     owner-level powers (review requests, toggle master access), except
//     cannot demote/replace the owner.
//   owner: exactly one account, seeded via scripts/seed_owner.js. Implicit
//     master access, cannot be edited via the admin API.

function isAdmin(user) {
  return user.role === 'admin' || user.role === 'owner';
}

function hasMasterAccess(user) {
  return user.role === 'owner' || (user.role === 'admin' && !!user.has_master_access);
}

// Owner + master-access admins can manage other admins (review requests,
// toggle master access). Plain admins cannot, even though they can still
// upload assets and manage viewer grants.
function canManageAdmins(user) {
  return hasMasterAccess(user);
}

module.exports = { isAdmin, hasMasterAccess, canManageAdmins };
