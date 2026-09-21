const app = require('./app');
const { bootstrapStorageIfEmpty } = require('./lib/bootstrap');

const PORT = process.env.PORT || 4000;

bootstrapStorageIfEmpty();

app.listen(PORT, () => {
  console.log(`Backend listening on http://localhost:${PORT}`);
});
