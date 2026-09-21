# Protected Viewer

A web-first (Flutter Web → Android → optional iOS) app for sharing screenshots,
video, and Python code with people who should be able to **view** but not
**freely copy or redistribute** the content.

## Threat model (read this first)

Protection here means **deterrence + traceability**, not prevention. On open
platforms (web/Android/iOS) a determined viewer can always photograph the
screen. The design goal is: stop casual copy/redistribution, and make any
leak traceable back to the specific person and moment it came from.

See project memory / prior discussion for the full roadmap and phase
breakdown. Short version:

- **Phase 1 (done): backend core** — auth, per-asset short-lived
  signed tokens, server-side watermarking (images + code snippets rendered
  as watermarked images), access logging. All security-critical logic lives
  here, not in the client.
- **Phase 2 (done): Flutter Web client** — thin renderer only. Login,
  click-through agreement, asset browser, and a canvas-painted viewer for
  watermarked images/snippets. Makes no security decisions itself — see
  `frontend/README section` below.
- **Phase 3+**: real hosting, Android port, optional iOS, optional video DRM
  upgrade. See roadmap for details.

## Repo layout

```
backend/
  src/
    app.js              Express app wiring
    server.js            Entry point
    lib/
      db.js               SQLite schema (users, assets, access_log, agreements)
      auth.js             Password hashing, session JWTs, per-asset signed tokens
      watermark.js         Server-side image & code-snippet watermarking (sharp)
    middleware/
      requireAuth.js       Verifies session JWT
      requireAgreement.js  Blocks access until click-through agreement accepted
    routes/
      auth.js              /register /login /me /agreement/accept
      assets.js             /assets, /assets/:id/token, /assets/:id/content
  assets/                 Local asset files (gitignored contents in practice;
                          sample placeholders included for testing)
  data/                   SQLite DB file (gitignored)
  scripts/seed.js         Registers sample assets from backend/assets/

frontend/                Flutter app (web + android platforms scaffolded)
  lib/
    api/api_client.dart     Talks to the backend; no security logic of its own
    state/session.dart      Auth/agreement status, session token (in-memory only)
    screens/                Login, agreement gate, asset list, asset viewer
    widgets/
      protected_image_view.dart  Canvas-painted image renderer (not Image/<img>,
                                   no long-press/right-click save affordance) —
                                   UX friction, not real security; see threat
                                   model above
```

## How the security model works

1. Client logs in → gets a session JWT (`/api/auth/login`).
2. Client must accept the no-redistribution agreement once
   (`/api/auth/agreement/accept`) before any asset route works.
3. To view an asset, client first requests a **short-lived, single-asset**
   token (`POST /api/assets/:id/token`, ~2 min TTL by default). This token is
   useless for any other asset and expires quickly, so it can't usefully be
   bookmarked or shared.
4. Client fetches content with that token
   (`GET /api/assets/:id/content?token=...`). The server **always**
   watermarks before sending — images get a tiled diagonal watermark with the
   viewer's email + exact timestamp baked into the pixels; Python snippets
   are rendered to a watermarked PNG server-side, so raw source text never
   leaves the server.
5. Every token issuance and every content fetch is written to `access_log`
   (user, asset, timestamp, IP, user agent) — this is the traceability net
   if something leaks.

There is **no route that serves a raw file** — this was verified directly
(no token / bad token / token-for-wrong-asset / direct static path are all
rejected).

## Running locally

```bash
cd backend
cp .env.example .env        # then edit JWT_SECRET to a long random value
npm install
node scripts/seed.js        # registers sample assets from backend/assets/
npm run dev                 # or: npm start
```

Server listens on `http://localhost:4000`. Try `GET /health`.

In a second terminal:

```bash
cd frontend
flutter pub get
flutter run -d chrome     # requires CHROME_EXECUTABLE set if Chrome isn't
                           # on PATH as `google-chrome` — see setup notes below
```

### First-time Flutter/Chrome setup on this machine

- Flutter SDK installed via `git clone -b stable https://github.com/flutter/flutter.git ~/flutter`,
  with `~/flutter/bin` added to `PATH` in `~/.bashrc`.
- Chrome: this machine only has `chromium` (snap), not `google-chrome`, so
  `CHROME_EXECUTABLE=/snap/bin/chromium` is set in `~/.bashrc` so Flutter can
  find it for `flutter run -d chrome`.
- Android toolchain (cmdline-tools, `ANDROID_HOME`) is **not** set up yet —
  deferred to Phase 4 per the roadmap, since web is priority #1.

## Before sharing this with real outside viewers (not yet done)

- Switch `/api/auth/register` from open self-signup to invite-only account
  creation — open signup defeats "not full access to just anyone."
- Tighten CORS from `cors()` (wide open) to your actual Flutter web origin.
- Move `JWT_SECRET` and all secrets out of `.env` into real secret management
  for any non-local deployment.
- Video watermarking/streaming is not implemented yet (Phase 1 covered
  images + snippets first, per the roadmap) — the `/content` route currently
  returns 501 for video assets.
- Session token is in-memory only in the Flutter client (lost on page
  refresh) — deliberate for now; add persistence later as a considered
  decision, not a default.
- `ProtectedImageView`'s gesture-blocking (no long-press/right-click save) is
  UX friction only, not a security boundary — see threat model at the top of
  this file. The real protection is that bytes are already watermarked
  server-side before they reach the client.
