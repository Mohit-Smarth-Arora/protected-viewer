// Dev-only convenience script: registers a couple of sample assets that
// point at files under backend/assets/. Run with: node scripts/seed.js
// Put real files in backend/assets/{images,videos,snippets} before running,
// or edit the list below to match what you actually have.
require('dotenv').config();
const path = require('path');
const fs = require('fs');
const { nanoid } = require('nanoid');
const db = require('../src/lib/db');

const samples = [
  { type: 'image', title: 'Sample Screenshot', file_path: 'assets/images/sample.png' },
  { type: 'snippet', title: 'Sample Snippet', file_path: 'assets/snippets/sample.py' },
];

const insert = db.prepare(
  'INSERT INTO assets (id, type, title, file_path) VALUES (?, ?, ?, ?)'
);

for (const sample of samples) {
  const absolutePath = path.join(__dirname, '..', sample.file_path);
  if (!fs.existsSync(absolutePath)) {
    console.warn(`Skipping "${sample.title}" — file not found at ${absolutePath}`);
    continue;
  }
  const id = nanoid(10);
  insert.run(id, sample.type, sample.title, sample.file_path);
  console.log(`Registered ${sample.type} asset "${sample.title}" (id=${id})`);
}

console.log('Seed complete.');
