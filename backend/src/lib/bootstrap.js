const fs = require('fs');
const path = require('path');
const { nanoid } = require('nanoid');
const db = require('./db');
const { STORAGE_ROOT, assetsDir } = require('./paths');

// Where sample assets ship inside the deployed image/repo, regardless of
// STORAGE_ROOT — this is the source to seed a fresh empty volume from.
const SHIPPED_ASSETS_DIR = path.join(__dirname, '..', '..', 'assets');

const SAMPLE_ASSETS = [
  { type: 'image', title: 'Sample Screenshot', file_path: 'assets/images/sample.png' },
  { type: 'snippet', title: 'Sample Snippet', file_path: 'assets/snippets/sample.py' },
];

function copyDirRecursive(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDirRecursive(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

// On a fresh persistent volume (STORAGE_ROOT set and its assets/ dir is
// empty/missing), seed it from the sample assets shipped in the image, and
// register them in the DB if not already present. No-op on repeat boots
// once the volume already has content — this only bootstraps an empty
// deploy, it never overwrites real uploaded assets.
function bootstrapStorageIfEmpty() {
  const usingExternalStorage = STORAGE_ROOT !== path.join(__dirname, '..', '..');
  if (!usingExternalStorage) return; // local dev: assets/ already lives here

  const assetsDirIsEmpty = !fs.existsSync(assetsDir) || fs.readdirSync(assetsDir).length === 0;
  if (assetsDirIsEmpty && fs.existsSync(SHIPPED_ASSETS_DIR)) {
    console.log(`Seeding empty storage volume at ${assetsDir} from shipped sample assets...`);
    copyDirRecursive(SHIPPED_ASSETS_DIR, assetsDir);
  }

  const assetCount = db.prepare('SELECT COUNT(*) AS count FROM assets').get().count;
  if (assetCount === 0) {
    const insert = db.prepare(
      'INSERT INTO assets (id, type, title, file_path) VALUES (?, ?, ?, ?)'
    );
    for (const sample of SAMPLE_ASSETS) {
      const absolutePath = path.join(STORAGE_ROOT, sample.file_path);
      if (!fs.existsSync(absolutePath)) continue;
      insert.run(nanoid(10), sample.type, sample.title, sample.file_path);
      console.log(`Registered sample asset "${sample.title}"`);
    }
  }
}

module.exports = { bootstrapStorageIfEmpty };
