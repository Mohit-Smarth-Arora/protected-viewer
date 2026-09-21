const express = require('express');
const db = require('../lib/db');
const requireAuth = require('../middleware/requireAuth');
const { isAdmin } = require('../lib/permissions');

const router = express.Router();
router.use(requireAuth);

// A viewer's own request(s) to open a chat. Requires no request body
// beyond an optional message — admin_id is optional (NULL = "any admin",
// shown to all admins in their pending-requests view).
router.post('/requests', (req, res) => {
  if (isAdmin(req.user)) {
    return res.status(400).json({ error: 'Admins can message viewers directly — no request needed' });
  }
  const { message, adminId } = req.body || {};

  if (adminId) {
    const admin = db.prepare("SELECT id FROM users WHERE id = ? AND role IN ('admin', 'owner')").get(adminId);
    if (!admin) return res.status(404).json({ error: 'Admin not found' });
  }

  const existingPending = db
    .prepare("SELECT id FROM chat_requests WHERE viewer_id = ? AND status = 'pending'")
    .get(req.user.id);
  if (existingPending) {
    return res.status(409).json({ error: 'You already have a pending chat request' });
  }

  const info = db
    .prepare('INSERT INTO chat_requests (viewer_id, admin_id, message) VALUES (?, ?, ?)')
    .run(req.user.id, adminId || null, message || null);

  res.status(201).json({ ok: true, requestId: info.lastInsertRowid });
});

// Admin/owner: list pending chat requests (directed at them specifically,
// or at "any admin").
router.get('/requests', (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ error: 'Admin access required' });

  const rows = db
    .prepare(
      `SELECT cr.id, cr.message, cr.created_at, u.id AS viewer_id, u.email, u.display_name
       FROM chat_requests cr JOIN users u ON u.id = cr.viewer_id
       WHERE cr.status = 'pending' AND (cr.admin_id IS NULL OR cr.admin_id = ?)
       ORDER BY cr.created_at DESC`
    )
    .all(req.user.id);
  res.json({ requests: rows });
});

function getOrCreateThread(viewerId, adminId) {
  const existing = db
    .prepare('SELECT id FROM chat_threads WHERE viewer_id = ? AND admin_id = ?')
    .get(viewerId, adminId);
  if (existing) return existing.id;
  const info = db
    .prepare('INSERT INTO chat_threads (viewer_id, admin_id) VALUES (?, ?)')
    .run(viewerId, adminId);
  return info.lastInsertRowid;
}

router.post('/requests/:id/approve', (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ error: 'Admin access required' });

  const request = db.prepare("SELECT * FROM chat_requests WHERE id = ? AND status = 'pending'").get(req.params.id);
  if (!request) return res.status(404).json({ error: 'Pending request not found' });

  const threadId = getOrCreateThread(request.viewer_id, req.user.id);
  db.prepare(
    "UPDATE chat_requests SET status = 'approved', reviewed_by = ?, reviewed_at = datetime('now') WHERE id = ?"
  ).run(req.user.id, request.id);

  res.json({ ok: true, threadId });
});

router.post('/requests/:id/reject', (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ error: 'Admin access required' });

  const request = db.prepare("SELECT * FROM chat_requests WHERE id = ? AND status = 'pending'").get(req.params.id);
  if (!request) return res.status(404).json({ error: 'Pending request not found' });

  db.prepare(
    "UPDATE chat_requests SET status = 'rejected', reviewed_by = ?, reviewed_at = datetime('now') WHERE id = ?"
  ).run(req.user.id, request.id);

  res.json({ ok: true });
});

// Admin messaging a viewer directly (no request needed — admins already
// have authority over viewer accounts). Creates the thread on first message
// if it doesn't exist yet.
router.post('/direct/:viewerId', (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ error: 'Admin access required' });

  const viewer = db.prepare("SELECT id FROM users WHERE id = ? AND role = 'viewer'").get(req.params.viewerId);
  if (!viewer) return res.status(404).json({ error: 'Viewer not found' });

  const { body } = req.body || {};
  if (typeof body !== 'string' || body.trim().length === 0) {
    return res.status(400).json({ error: 'Message body is required' });
  }

  const threadId = getOrCreateThread(viewer.id, req.user.id);
  const info = db
    .prepare('INSERT INTO messages (thread_id, sender_id, body) VALUES (?, ?, ?)')
    .run(threadId, req.user.id, body.trim());

  res.status(201).json({ ok: true, threadId, messageId: info.lastInsertRowid });
});

// Lists threads for the current user: a viewer sees their (usually one)
// thread per admin they've messaged with; an admin sees all their viewer
// threads.
router.get('/threads', (req, res) => {
  const rows = isAdmin(req.user)
    ? db
        .prepare(
          `SELECT t.id, t.created_at, u.id AS viewer_id, u.email, u.display_name
           FROM chat_threads t JOIN users u ON u.id = t.viewer_id
           WHERE t.admin_id = ?
           ORDER BY t.created_at DESC`
        )
        .all(req.user.id)
    : db
        .prepare(
          `SELECT t.id, t.created_at, u.id AS admin_id, u.email, u.display_name
           FROM chat_threads t JOIN users u ON u.id = t.admin_id
           WHERE t.viewer_id = ?
           ORDER BY t.created_at DESC`
        )
        .all(req.user.id);
  res.json({ threads: rows });
});

function userIsInThread(userId, thread) {
  return thread.viewer_id === userId || thread.admin_id === userId;
}

router.get('/threads/:id/messages', (req, res) => {
  const thread = db.prepare('SELECT * FROM chat_threads WHERE id = ?').get(req.params.id);
  if (!thread) return res.status(404).json({ error: 'Thread not found' });
  if (!userIsInThread(req.user.id, thread)) {
    return res.status(403).json({ error: 'Not a participant in this thread' });
  }

  const messages = db
    .prepare('SELECT id, sender_id, body, created_at FROM messages WHERE thread_id = ? ORDER BY created_at ASC')
    .all(thread.id);
  res.json({ messages });
});

router.post('/threads/:id/messages', (req, res) => {
  const thread = db.prepare('SELECT * FROM chat_threads WHERE id = ?').get(req.params.id);
  if (!thread) return res.status(404).json({ error: 'Thread not found' });
  if (!userIsInThread(req.user.id, thread)) {
    return res.status(403).json({ error: 'Not a participant in this thread' });
  }

  const { body } = req.body || {};
  if (typeof body !== 'string' || body.trim().length === 0) {
    return res.status(400).json({ error: 'Message body is required' });
  }

  const info = db
    .prepare('INSERT INTO messages (thread_id, sender_id, body) VALUES (?, ?, ?)')
    .run(thread.id, req.user.id, body.trim());

  res.status(201).json({ ok: true, messageId: info.lastInsertRowid });
});

module.exports = router;
