require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const multer = require('multer');

const authRoutes = require('./routes/auth');
const assetRoutes = require('./routes/assets');
const adminRoutes = require('./routes/admin');
const setupRoutes = require('./routes/setup');

const app = express();

app.use(helmet());
app.use(cors()); // tighten to your Flutter web origin before going public
app.use(express.json());

app.get('/health', (req, res) => res.json({ ok: true }));

app.use('/api/auth', authRoutes);
app.use('/api/assets', assetRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/setup', setupRoutes);

app.use((req, res) => res.status(404).json({ error: 'Not found' }));

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    return res.status(400).json({ error: `Upload error: ${err.message}` });
  }
  // fileFilter rejections (uploads.js) throw plain Errors, not MulterError
  if (err && err.message && /must be (JPEG|PNG|WebP)/.test(err.message)) {
    return res.status(400).json({ error: err.message });
  }
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
});

module.exports = app;
