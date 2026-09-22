# Protected Viewer — Session Summary

A record of what was built, decided, and where things stand. For setup/usage instructions see `README.md`; this file is a narrative log of the build process and key decisions.

**Live deployment:**
- Frontend: https://mohit-smarth-arora.github.io/protected-viewer/
- Backend: https://protected-viewer-backend-production.up.railway.app
- Repo: https://github.com/Mohit-Smarth-Arora/protected-viewer

---

## Origin

User wanted to share screenshots, Python code, and video with people who should be able to **view but not freely copy/redistribute** the content — a Flutter app (cross-platform: web/Android/iOS) they'd build themselves, with web as the top priority.

## Core threat model (established early, holds throughout)

Protection = **deterrence + traceability**, not prevention. On open platforms (web/Android/iOS) a determined viewer can always photograph the screen. No client-side trick changes this. The actual design goal: stop casual copy/redistribution, and make any leak traceable back to the specific person and moment it came from.

Key architectural consequence: **all security-critical logic lives server-side.** Flutter is a thin renderer that makes no security decisions of its own — watermarking, access control, and token issuance all happen on the backend.

## Roadmap phases (all shipped)

1. **Backend core** — Express + SQLite, auth (JWT + bcrypt), per-asset short-lived signed tokens, server-side watermarking, access logging.
2. **Flutter Web client** — login, agreement gate, asset browser, canvas-painted viewer (not `Image`/`<img>`, no long-press/right-click save — UX friction, not real security).
3. **Real hosting** — backend on Railway (persistent volume for SQLite + assets), frontend on GitHub Pages via GitHub Actions.
4. **Admin panel** — owner-reviewed admin requests (with passport-photo identity verification), per-user/per-asset access grants, in-app asset upload, tiered admin model (plain admin vs. master-access admin vs. owner).
5. **Folders, messaging, user activity** — Google-Drive-style folders with cascading access grants, admin↔viewer chat system, admin view of accounts/logins/who's-online (heartbeat-based).
6. **Mandatory email verification + referral/approval gate** — every viewer must verify email; a valid referral code skips admin approval, otherwise any admin approves.
7. **Account deletion** — master-access-only, preserves traceability log and others' content on delete.

## Key technical decisions and why

- **Watermarking**: every image/code-snippet render gets a tiled diagonal watermark (viewer email + exact timestamp + "Solely Owned by Mohit Smarth Arora") baked into pixels server-side, before bytes ever leave the server. Code snippets are rendered to images too — raw `.py` text never reaches the client.
- **Signed asset tokens**: short-lived (~2 min), single-asset-scoped. Client must request a token, then fetch content with it — prevents bookmarking/sharing raw URLs.
- **Role model**: `viewer` (default, sees only granted content) → `admin` (upload + manage grants) → `admin + master_access` (also reviews admin requests, toggles others' master access) → `owner` (exactly one, immutable via API).
- **Folders**: hierarchical; granting a folder grants everything inside including subfolders (ancestor-chain walk at check time, not per-descendant grant rows).
- **Messaging**: viewers must request a chat (admin approves); admins can message any viewer directly with no request.
- **Email verification + referral codes**: registration → 6-digit emailed code → verify → (valid referral code ⇒ instant active) or (no code ⇒ pending admin approval). Admins/owner exempt from this whole gate.
- **Account deletion policy**: destructive, so master-access-only. Content a deleted user created (assets/folders/referral codes) is **kept**, only ownership attribution nulled. `access_log` rows are **kept** (traceability must outlive the account) — required removing hard FKs on `access_log.user_id`/`asset_id` and snapshotting `user_email`/`asset_title` at write time.

## Real bugs found and fixed during testing (not just inspected — reproduced then fixed)

1. **Font rendering on Railway**: watermark text rendered as empty boxes in production because Railway's minimal container had no system fonts. Fixed by bundling DejaVu fonts in the repo and pointing sharp's fontconfig at them explicitly via a generated config at startup.
2. **Foreign key crash on delete**: deleting a folder/asset that had ever been viewed threw `SQLITE_CONSTRAINT_FOREIGNKEY` because `access_log` had hard FKs to `assets`/`users`. Fixed by removing those FKs (access_log is meant to outlive the things it references) and snapshotting `asset_title`/`user_email` at write time.
3. **Admin-photo upload rejected valid JPEGs**: Dart's `http` package wasn't reliably inferring `Content-Type` for multipart uploads, defaulting to `application/octet-stream`, which the backend's mimetype allowlist correctly rejected. Fixed by setting `MediaType` explicitly by file extension on the client. Reproduced the exact bug against the live backend before and after the fix to confirm.
4. **Grandfathering logic**: initial "don't lock out pre-existing accounts" migration used a time-based heuristic (`created_at < now - 1 minute`) which incorrectly left freshly-seeded local dev accounts unverified. Fixed by making `ensureColumn` report whether it actually added a column, and only backfilling on a genuine schema upgrade, never on a fresh install.

## Infrastructure / operational notes

- **Flutter SDK**: installed via `git clone -b stable` to `~/flutter`, added to `PATH`.
- **Chrome**: this machine only has `chromium` via snap; `CHROME_EXECUTABLE` set accordingly for `flutter run -d chrome`.
- **Android toolchain**: deliberately not set up — web was priority #1, Android deferred.
- **Railway volume**: one volume per service constraint meant `data/`, `assets/`, and `admin_photos/` all share a single mounted volume via a `STORAGE_ROOT` env var abstraction, rather than separate volumes.
- **Owner bootstrapping**: two paths — a local script (`scripts/seed_owner.js`) and a temporary HTTP endpoint (`/api/setup/owner`, guarded by `SETUP_SECRET`, inert/404 unless that env var is explicitly set, unset again immediately after use). Chosen over SSH after Railway SSH hit host-key-verification friction not worth resolving for a one-time task.
- **Password reset**: same inert-by-default `/api/setup/reset-password` pattern, used once already to recover the owner account whose original password (set during Phase 1 testing) was never actually communicated to the user.
- **Email delivery**: originally wired to SendGrid, then swapped to **Resend** at user's request (preferred not to use a Twilio-owned product, even though SendGrid's free tier is genuinely free). Both follow the same inert-by-default pattern: unset API key/from-email → codes log to console instead of sending, so the whole flow is testable without a real provider account. Resend is now live and configured on Railway (`RESEND_API_KEY` / `RESEND_FROM_EMAIL=onboarding@resend.dev`).
- **GitHub Pages deploy** occasionally hung on the `deploy-pages` step for several minutes with no real progress (confirmed via GitHub's deployments API showing zero deployment records the whole time) — resolved by cancelling and re-triggering, which then completed normally in under 2 minutes. Not a recurring issue, treated as a one-off platform hiccup both times it happened.

## Known open items / explicitly deferred

- **CORS is still wide open** (`cors()` with no origin restriction) — flagged repeatedly as a to-do before real public sharing, not yet tightened.
- **Video upload/watermarking**: not implemented — `/api/assets/:id/content` returns 501 for video assets. Images and Python snippets were prioritized first.
- **Session token is in-memory only** in the Flutter client (lost on page refresh) — deliberate, not yet upgraded to persistent storage.
- **Railway hosting is on a free trial credit ($5, one-time, not indefinite)** — this is a real constraint the user was in the middle of checking (via the Railway dashboard, which isn't accessible to Claude) when this summary was requested. No payment method is on file. When the trial credit is exhausted, the backend goes offline until upgraded (~$5/month usage-based Hobby plan). GitHub Pages (frontend) has no such limit and will run indefinitely for free.
- **Database size**: SQLite on the Railway volume, 500MB cap, ~40MB used at last check — size is not the near-term constraint, account/billing standing is.

## Files/structure reference

See `README.md` in the repo root for the full, current repo layout, API surface, and "how the security model works" explanation — that document is kept up to date as the source of truth and is more detailed than this summary.
