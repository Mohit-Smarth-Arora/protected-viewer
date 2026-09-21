require('./lib/fonts'); // must run before any 'sharp' require, see file for why
const app = require('./app');
const { bootstrapStorageIfEmpty } = require('./lib/bootstrap');

const PORT = process.env.PORT || 4000;

bootstrapStorageIfEmpty();

app.listen(PORT, () => {
  console.log(`Backend listening on http://localhost:${PORT}`);
});
