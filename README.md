# Protected Viewer

A web-first (Flutter Web → Android → optional iOS) app for sharing screenshots,
video, and Python code with people who should be able to **view** but not
**freely copy or redistribute** the content. Access is admin-controlled:
an owner approves admins, admins upload assets and grant specific viewers
access to specific assets.

**Live deployment:**
- Frontend: https://mohit-smarth-arora.github.io/protected-viewer/
- Backend API: https://protected-viewer-backend-production.up.railway.app
- Repo: https://github.com/Mohit-Smarth-Arora/protected-viewer

## Threat model (read this first)

Protection here means **deterrence + traceability**, not prevention. On open
platforms (web/Android/iOS) a determined viewer can always photograph the
screen. The design goal is: stop casual copy/redistribution, and make any
leak traceable back to the specific person and moment it came from.

Phases:
- **Phase 1 (done): backend core** — auth, per-asset short-lived signed
  tokens, server-side watermarking, access logging. All security-critical
  logic lives here, not in the client.
- **Phase 2 (done): Flutter Web client** — thin renderer only, no security
  decisions of its own.
- **Phase 3 (done): real hosting** — backend on Railway (persistent volume
  for SQLite + assets), frontend on GitHub Pages via GitHub Actions.
- **Phase 3.5 (done): admin panel** — owner-reviewed admin requests,
  per-user/per-asset access grants, in-app asset upload. See below.
- **Phase 3.6 (done): folders, messaging, user activity** — Google-Drive-style
  folders with cascading access grants, an admin/viewer chat system, and an
  admin view of accounts/sign-ins/who's online. See below.
- **Phase 3.7 (done): mandatory email verification + referral/approval gate**
  — every viewer must verify their email; registering with a valid referral
  code skips admin approval, otherwise the account waits for any admin to
  approve it. See below.
- **Next**: tighten CORS to the real Pages origin, video pipeline.

## Roles

- **viewer** (default on signup): sees only assets an admin has explicitly
  granted them. No admin powers.
- **admin**: can upload assets (image/Python snippet) and manage which
  viewers can see which assets. Approved by the owner or a master-access
  admin, via an in-app request form.
- **admin + master access**: everything a plain admin can do, plus can
  review/approve/reject admin requests and toggle master access on other
  admins. Off by default when an admin is approved — the owner grants it
  explicitly, per admin, and can revoke it later.
- **owner**: exactly one account (you). Implicit master access. Cannot be
  demoted or have its access modified via the API.

### Becoming an admin

Any signed-in viewer can request admin access from the account menu
(top-right, "Request admin access"). The form collects full legal name,
phone number, organization (optional), a reason, and a passport-size photo
— submitted as a pending request. An owner/master-access admin reviews it
in-app ("Review admin requests"), views the photo, and approves (choosing
whether to also grant master access) or rejects.

### Promoting the owner account

There's exactly one owner. Two ways to set it:

**Locally** (has direct filesystem/DB access):
```bash
cd backend
node scripts/seed_owner.js you@example.com [password] [displayName]
# omit password/displayName if the account already exists — it just
# promotes the existing account's role to 'owner'
```

**On a deploy without shell access** (e.g. Railway without SSH set up):
temporarily set the `SETUP_SECRET` env var on the platform, then:
```bash
curl -X POST https://your-backend-url/api/setup/owner \
  -H "Content-Type: application/json" \
  -d '{"secret":"<SETUP_SECRET value>","email":"you@example.com"}'
```
Unset `SETUP_SECRET` afterward — the route 404s (fully inert) whenever
`SETUP_SECRET` isn't set, so leaving it unset is the safe default.

## Viewer signup: email verification + referral/approval

Every new account goes through this sequence:

1. **Register** (email, password, display name, optional referral code).
   Account is created immediately but can't do anything yet.
2. **Verify email**: a 6-digit code is emailed (see "Email delivery"
   below). The app blocks on this screen until the correct code is entered.
3. **Branch on referral code**:
   - **Valid, active referral code supplied** → account goes straight to
     `signup_status = 'active'`. Done, full viewer access immediately.
   - **No code, or an invalid/inactive one at registration** (registration
     itself rejects an invalid code outright) — account becomes
     `signup_status = 'pending_approval'` and a `signup_requests` row is
     created. The viewer sees a "waiting for approval" screen. **Any**
     admin (not master-access-gated — lower stakes than admin_requests)
     can approve or reject from "Signup requests".

Admins/owner are exempt from this whole gate (`requireActiveAccount`
middleware) — their accounts either predate this feature or came through
the admin-approval path already.

**Referral codes** are created/deactivated/reactivated only by the owner or
a master-access admin ("Referral codes" in the menu). A code is a short
uppercase alphanumeric string (ambiguous characters like `0`/`O`, `1`/`I`
excluded), reusable until deactivated, with a use counter.

### Email delivery (Resend)

Verification codes are sent via Resend (`backend/src/lib/email.js`).
Configure with two env vars:
```
RESEND_API_KEY=re_xxxxx
RESEND_FROM_EMAIL=onboarding@resend.dev   # or a domain you've verified in Resend
```
**If these are unset** (the local dev default), the module logs the code to
the console instead of sending a real email (`[email:dev-mode] Verification
code for x@example.com: 123456`) — lets the whole flow be tested without a
real Resend account. Resend's free tier is 3,000 emails/month (100/day), no
cost, no credit card required for that tier.

## Folders

Folders are hierarchical (like a simple file browser) and access grants
happen **at the folder level**: granting a viewer a folder gives them
everything inside it, including subfolders, without needing a grant per
asset. An asset can still be granted individually if it sits at the root
(no folder) or you want to share just that one file without sharing its
whole folder. See `backend/src/lib/folders.js` for the access-check logic
(`hasAccessToFolder` walks the ancestor chain; a viewer's folder listing
also shows a folder they weren't granted directly if something inside it
was).

Both the viewer's browse screen and the admin's manage-assets screen are
folder browsers with breadcrumb navigation. Admins create/rename/delete
folders and manage per-folder grants from the manage-assets screen's
per-folder menu.

## Messaging

Viewers **request** a chat from the account menu ("Message an admin") —
an optional message, no identity form. Any admin (or master-access/owner)
sees pending requests under "Chat requests" and can approve (opening a
thread) or reject. Admins can also message a specific viewer directly with
no request needed, either from "Users & activity" → accounts tab, or once
a thread exists, from "Messages". There's no viewer-to-viewer messaging.

Threads are simple request/response, refreshed by pull-to-refresh or on
sending a message — not real-time/websocket-based, kept deliberately
simple for now.

## User activity (admin-only)

"Users & activity" has three tabs:
- **Accounts** — every registered account, role, and join date. Tap the
  chat icon next to a viewer to message them directly.
- **Sign-in history** — a log of every successful login (`login_events`
  table), most recent first.
- **Active now** — accounts with a heartbeat in the last 2 minutes
  (`user_presence` table + `ONLINE_WINDOW_MINUTES` in
  `backend/src/routes/admin.js`). The Flutter client pings
  `POST /api/auth/heartbeat` every 45s while signed in
  (`frontend/lib/state/session.dart`); this is an approximation, not a
  websocket-based live presence system.

### Deleting an account

Owner/master-access admins can delete a non-owner account from the
Accounts tab (`DELETE /api/admin/users/:id`). This is destructive and hard
to reverse, so it's gated at the master-access tier, not plain admin.
Policy:
- **Owner** can never be deleted via this route.
- **Content the deleted user created or uploaded** (assets, folders,
  referral codes) is **kept** — only the "created by"/"uploaded by"
  attribution is cleared to `NULL`. Deleting an admin's account doesn't
  remove content other people may still have access to.
- **`access_log` rows are kept** — the leak-traceability record must
  survive the account that generated it, same principle as asset deletion
  (see below). The viewer's email is snapshotted into `access_log.user_email`
  at write time, so the log stays attributable after the account is gone.
- Everything that only makes sense tied to that specific account (grants,
  pending admin/signup/chat requests, chat threads and their messages,
  agreements, login history, verification codes, presence) is deleted
  outright.

Verified by direct testing: a viewer with a grant, view history, an
approved chat thread, and messages was deleted, and the access log
survived (with email intact) while everything else specific to that
account was removed; a separate admin who'd created a folder and uploaded
an asset was deleted, and both survived with `created_by`/`uploaded_by`
set to `null`.

## Repo layout

```
backend/
  src/
    app.js                 Express app wiring, multer error handling
    server.js               Entry point
    lib/
      db.js                  SQLite schema + forward-compatible column migrations
      auth.js                Password hashing, session JWTs, per-asset signed tokens
      permissions.js          Role logic: isAdmin / hasMasterAccess / canManageAdmins
      paths.js                STORAGE_ROOT-based paths (data/assets/admin_photos)
      uploads.js              multer config for admin photos + asset uploads
      watermark.js            Server-side image & code-snippet watermarking (sharp),
                               always appends the ownership line to every render
      fonts.js                Must load before 'sharp' — bundles fonts so rendering
                               doesn't depend on host OS fonts (see git history)
      bootstrap.js             Seeds a fresh empty storage volume on first boot
      folders.js               Folder access-check logic (ancestor-chain grant walk)
    middleware/
      requireAuth.js          Verifies session JWT
      requireAgreement.js     Blocks access until click-through agreement accepted
      requireAdmin.js          role in (admin, owner)
      requireMasterAccess.js   owner, or admin with has_master_access
    routes/
      auth.js                  /register /login /me /agreement/accept /admin-request
                                /heartbeat
      assets.js                 /assets (folder-aware listing), /assets/:id/token,
                                 /assets/:id/content
      admin.js                  Request review, admin management, folders, asset
                                 upload/grants, user activity (accounts/logins/online)
      chat.js                   Chat requests, threads, messages
      setup.js                  One-time owner bootstrap (see above), inert by default
  assets/                   Asset source files (sample.png/sample.py tracked;
                             anything else here — real uploads — is gitignored)
  admin_photos/             Admin-request verification photos (gitignored entirely)
  data/                     SQLite DB file (gitignored)
  scripts/
    seed.js                  Registers the sample assets
    seed_owner.js             Promotes/creates the one owner account

frontend/                  Flutter app (web + android platforms scaffolded)
  lib/
    theme.dart                Central ColorScheme (light+dark, seeded, Material 3)
                               + component themes (cards, inputs, buttons, etc.) —
                               the one place to touch to re-skin the app
    api/api_client.dart      Talks to the backend; no security logic of its own
    state/session.dart       Auth/role/agreement status, session token (in-memory),
                              heartbeat timer while signed in
    screens/
      login_screen.dart, agreement_screen.dart, asset_list_screen.dart
        (folder browser w/ breadcrumbs), asset_viewer_screen.dart,
      admin_request_screen.dart, admin_review_screen.dart,
      manage_admins_screen.dart, manage_assets_screen.dart
        (folder browser + folder/asset CRUD + grants),
      user_activity_screen.dart (accounts/logins/online tabs),
      chat_screens.dart (request, review, threads, conversation)
    widgets/
      protected_image_view.dart  Canvas-painted image renderer (not Image/<img>,
                                   no long-press/right-click save affordance) —
                                   UX friction, not real security; see threat
                                   model above
      state_views.dart            Shared LoadingState/EmptyState/ErrorState used
                                   by every list/data screen instead of each
                                   screen hand-rolling its own placeholder
      app_drawer.dart              App-wide nav drawer, grouped by section
                                   (Library / People / Owner controls / Get help)
                                   — replaced a PopupMenuButton overflow menu that
                                   had outgrown a popup once the admin surface
                                   passed ~10 destinations
      auth_scaffold.dart           Shared branded shell (gradient backdrop, card,
                                   BrandMark) for the pre-signed-in gate screens
                                   (login, email verification, pending approval,
                                   agreement)

.github/workflows/deploy-frontend.yml   Builds + deploys frontend to GitHub Pages
```

## How the security model works

1. Client logs in → gets a session JWT (`/api/auth/login`).
2. Client must accept the no-redistribution agreement once before any asset
   route works.
3. To view an asset, client first requests a **short-lived, single-asset**
   token (`POST /api/assets/:id/token`, ~2 min TTL). Viewers only get a
   token for assets explicitly granted to them (`asset_grants` table);
   admins/owner can request a token for anything. The token is useless for
   any other asset and expires quickly.
4. Client fetches content with that token. The server **always**
   watermarks before sending — every image and code-snippet render gets a
   tiled diagonal watermark with the viewer's email, the exact timestamp,
   and "Solely Owned by Mohit Smarth Arora" baked into the pixels
   server-side. Raw source (e.g. `.py` text) never leaves the server.
5. Every token issuance and content fetch is logged (`access_log`: user,
   asset, timestamp, IP, user agent) — the traceability net if something
   leaks.

There is **no route that serves a raw file** to a viewer. Admin-request
verification photos are the one exception, served unwatermarked but only
to master-access accounts, for manual identity review — never exposed
through the public asset routes.

## Running locally

```bash
cd backend
cp .env.example .env        # then edit JWT_SECRET to a long random value
npm install
node scripts/seed.js        # registers sample assets from backend/assets/
node scripts/seed_owner.js you@example.com yourpassword123 "Your Name"
npm run dev                 # or: npm start
```

Server listens on `http://localhost:4000`. Try `GET /health`.

In a second terminal:

```bash
cd frontend
flutter pub get
flutter run -d chrome     # requires CHROME_EXECUTABLE if Chrome isn't on
                           # PATH as `google-chrome` — see setup notes below
```

### First-time Flutter/Chrome setup on this machine

- Flutter SDK installed via `git clone -b stable https://github.com/flutter/flutter.git ~/flutter`,
  with `~/flutter/bin` added to `PATH` in `~/.bashrc`.
- Chrome: this machine only has `chromium` (snap), not `google-chrome`, so
  `CHROME_EXECUTABLE=/snap/bin/chromium` is set in `~/.bashrc`.
- Android toolchain (cmdline-tools, `ANDROID_HOME`) is **not** set up yet —
  deferred, since web is priority #1.

## Deployment

- **Backend (Railway)**: deployed via `railway up` from `backend/`. Env vars
  set on Railway: `JWT_SECRET`, `JWT_EXPIRES_IN`, `ASSET_TOKEN_TTL_SECONDS`,
  `NODE_ENV=production`, `STORAGE_ROOT=/app/storage`. A persistent volume is
  mounted at `/app/storage` (holds `data/`, `assets/`, `admin_photos/` — the
  one volume Railway allows per service, so all three share it via
  `STORAGE_ROOT`). On a fresh empty volume, `bootstrap.js` seeds the sample
  assets automatically on first boot.
- **Frontend (GitHub Pages)**: `.github/workflows/deploy-frontend.yml` builds
  on push to `main` (when `frontend/**` changes) and deploys automatically.
  `BACKEND_URL` is a repo variable baked in at build time via
  `--dart-define`. Base href is set to `/protected-viewer/` since Pages
  serves this as a project site, not a root domain.

## Before sharing this with real outside viewers (not yet done)

- Switch `/api/auth/register` from open self-signup to invite-only account
  creation, or otherwise gate who can create viewer accounts at all.
- Tighten CORS from `cors()` (wide open) to the real Pages origin.
- Video watermarking/streaming is not implemented yet — `/content` returns
  501 for video assets.
- Session token is in-memory only in the Flutter client (lost on page
  refresh) — deliberate for now; add persistence later as a considered
  decision, not a default.
- `ProtectedImageView`'s gesture-blocking (no long-press/right-click save) is
  UX friction only, not a security boundary — see threat model above. The
  real protection is that bytes are already watermarked server-side before
  they reach the client.
