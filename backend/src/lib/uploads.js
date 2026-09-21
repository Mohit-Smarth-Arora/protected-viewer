const fs = require('fs');
const path = require('path');
const multer = require('multer');
const { nanoid } = require('nanoid');
const { adminPhotosDir } = require('./paths');

for (const dir of [adminPhotosDir]) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

const MAX_PHOTO_BYTES = 5 * 1024 * 1024; // 5MB — a passport-size photo, not a video

// Admin-request verification photos: stored to disk under adminPhotosDir,
// original filename discarded (nanoid-generated name) to avoid path
// traversal / collisions, extension kept from the original for viewability.
const adminPhotoStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, adminPhotosDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase() || '.jpg';
    cb(null, `${nanoid(16)}${ext}`);
  },
});

const uploadAdminPhoto = multer({
  storage: adminPhotoStorage,
  limits: { fileSize: MAX_PHOTO_BYTES },
  fileFilter: (req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png', 'image/webp'];
    if (!allowed.includes(file.mimetype)) {
      return cb(new Error('Photo must be JPEG, PNG, or WebP'));
    }
    cb(null, true);
  },
});

// Asset uploads (images, snippets) are handled in memory — small enough,
// and the route decides the final on-disk path based on asset type/id
// rather than multer's generic disk storage.
const MAX_ASSET_BYTES = 25 * 1024 * 1024; // 25MB — covers images/snippets; video will need its own path later
const uploadAssetToMemory = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_ASSET_BYTES },
});

module.exports = { uploadAdminPhoto, uploadAssetToMemory };
