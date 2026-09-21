# Telesales Monitor - Logical Codebase Analysis

Date: 2026-09-18

## 1. Executive Summary

This workspace contains one Express/MongoDB backend and three client surfaces:

1. `telesales_monitor`: the primary Flutter mobile application, with Android-native call monitoring and recording.
2. `admin_web`: the operational browser console for administrators and managers.
3. Root HTML/PWA files: a static AskEVA design/prototype surface, not the same implementation as the production Flutter client.

The backend is the system of record for employees, calls, recordings, leads, and notifications. Flutter collects device-side activity and presents caller workflows. The admin portal manages users, reviews activity, manages leads, and reviews recordings.

The strongest parts of the design are shared server-side aggregation, normalized phone matching, idempotent call synchronization, persisted Android upload queues, and authenticated audio streaming. The highest risks are exposed production secrets, residual tokenless legacy access, incomplete manager hierarchy enforcement, local-disk audio storage, and the lack of backend/native/end-to-end tests.

## 2. System Boundaries and Runtime Entry Points

### Backend

- `backend/src/server.js` is the Express entry point.
- It loads environment variables, starts MongoDB connection, seeds an initial admin, installs security/body/auth middleware, registers routes, serves selected admin assets, and starts listening.
- Production configuration expects `MONGODB_URI`, `JWT_SECRET`, `PORT`, `CORS_ORIGIN`, and administrator bootstrap settings.
- The server listens on all interfaces and defaults to port 5000 when `PORT` is absent. The supplied environment uses port 5004.

### Flutter

- `telesales_monitor/lib/main.dart` starts the app and provides `TeleProvider`.
- `splash_screen.dart` restores persisted state and chooses onboarding, login, or the main shell.
- `main_shell.dart` selects the manager/caller navigation experience.
- `TeleProvider` is the central client state owner and calls `ApiService` for server operations.

### Android native layer

- `MainActivity.kt` exposes Flutter method-channel operations.
- `CallMonitorService.kt` watches phone state and coordinates recording discovery/fallback capture.
- `CallRecorder.kt` records fallback audio.
- `BuiltInRecordingFinder.kt` searches for recordings made by the device dialer.
- `RecordingCandidateRanker.kt` chooses the most likely matching built-in recording.
- `RecordingUploads.kt` persists and retries uploads.
- `CallMonitorStore.kt` persists native monitoring configuration/state.
- `BootReceiver.kt` handles device restart recovery.
- `CallAccessibilityService.kt` supports device/OEM call-state behavior.
- `DeviceSetupHelper.kt` provides setup and device capability checks.
- `RecordingDiagnostics.kt` writes recording diagnostics.

### Browser clients

- `admin_web/index.html` is a large single-file operational portal.
- `Telesales Monitor App.dc.html`, `support.js`, `ios-frame.jsx`, `sw.js`, and the root `manifest.json` form a separate static/PWA prototype using sample data and design-system runtime behavior.
- The backend intentionally serves only an allowlist of admin portal files, not every file under `admin_web`.

## 3. Backend Module Logic

### Configuration

- `config/db.js` connects Mongoose to MongoDB, applies production requirements, and retries production connections.
- `config/seedAdmin.js` creates the first admin only when no admin exists, using environment-provided bootstrap credentials.

### Middleware and authorization

- `middleware/auth.js` verifies JWTs, creates tokens, supports bcrypt password verification, and performs legacy password upgrades.
- It pins authenticated identity to the signed-in employee, preventing ordinary callers from changing their own user ID, role, team, or ownership filters.
- Audio playback can accept a token query parameter because native/browser media elements cannot always attach bearer headers.
- `server.js` contains the route permission table. First match wins; unlisted API routes require authentication.
- `MANAGERS` covers manager and junior-manager roles. The authorization boundary is therefore role-based first, with team scoping implemented in service/route logic.

### Shared utilities and services

- `utils/common.js`: phone normalization, regex escaping, safe ObjectId handling, pagination, date parsing, and common error responses.
- `services/scope.js`: resolves visibility for admins, managers/junior managers, and callers. It supports reporting-tree/team scope and legacy identity derivation.
- `services/matching.js`: normalizes call types/numbers, defines the five-minute call/recording matching window, builds deduplication keys, transitions lead status, and parses HTTP byte ranges.
- `services/callStats.js`: performs India-time date range calculation, Mongo aggregations, per-caller metrics, call-log synchronization, recording linking, lead creation, and status updates.

### Routes

- `routes/auth.js`: login, admin login, caller verification, current-user lookup, phone checks, and phone linking.
- `routes/admin.js`: dashboards, hourly activity, leaderboard, employee management, admin-scoped calls/recordings/leads, profile/photo operations, and administrative reporting behavior.
- `routes/user.js`: caller-facing call synchronization, recordings upload aliases, caller dashboard/history data, and caller profile operations.
- `routes/recordings.js`: recording list/detail/audio streaming, comments, reviews, deletion, and upload handling.
- `routes/leads.js`: lead listing, creation/update, assignment, status/outcome updates, import, filters, and caller-specific views.
- `routes/notifications.js`: notification listing, read-state updates, and caller/manager notification behavior.
- `routes/diagnostics.js`: operational diagnostics and recording troubleshooting data; this route should be treated as sensitive production observability.

The server registers route modules both at their canonical paths and through aliases used by older mobile builds. This reduces duplicate implementations, but makes the route permission table and alias behavior important to test together.

## 4. Persistence Model and Relationships

MongoDB collections are represented by Mongoose models:

- `Employee.js`: identity, phone/email, role, team, manager relationship, target, counters, avatar, and password. Passwords are excluded from normal output.
- `CallLog.js`: caller identity, customer number, call type, timestamp, duration, SIM slot, notes, deduplication key, and optional recording link.
- `Recording.js`: caller/customer metadata, local filename or audio payload, call time/duration/type, transcript, review criteria, rating, status, and optional call-log link.
- `Lead.js`: customer contact, normalized `phoneLast10`, CRM status, attempts, assignment, notes, source, and last-call time.
- `Notification.js`: review feedback and recipient identity, with current ID plus legacy phone/name fallbacks.

Most relationships are application-level rather than MongoDB populate relationships:

- Employee to calls/recordings uses employee ID, phone, or legacy name matching.
- Employee to leads uses assigned caller ID or legacy assigned name.
- CallLog and Recording cross-link through `recordingId` and `callLogId`.
- Recording review creates a Notification for the caller.

Lead phone uniqueness is primarily application-enforced, so concurrent creation can still produce duplicates unless a database constraint is added.

## 5. Authentication and Authorization Flow

1. A client calls an auth endpoint.
2. The backend verifies credentials or caller/device data.
3. A JWT is returned and stored by the client.
4. Subsequent requests use `Authorization: Bearer <token>`.
5. `authenticate` attaches `req.user` when a token is present.
6. The route permission table applies role and legacy rules.
7. `scope.js` converts identity into employee/team ownership filters.
8. Route handlers query or mutate only the resulting scope.

Public or semi-public behavior includes health and authentication endpoints. The current environment has `LEGACY_CLIENT_GRACE=true`; selected old-client paths can derive identity from request parameters without a valid token. This is a compatibility mechanism, not a secure identity mechanism, and must be removed after old clients are retired.

The current code appears to enforce admin-only user deletion, but user-management hierarchy checks require special attention: junior managers are admitted to manager routes and must not be able to modify users outside their reporting scope or promote users beyond their authority.

## 6. End-to-End Call Synchronization

1. Android obtains device call-log entries.
2. Flutter filters by authenticated session and selected/work SIM.
3. `TeleProvider` sends entries newer than its persisted acknowledgement point.
4. `ApiService` posts a batch to the call-sync endpoint.
5. The backend resolves the authenticated or legacy caller.
6. `callStats.js` normalizes numbers/types and creates employee-aware deduplication keys.
7. Existing legacy rows are recognized where possible.
8. Calls are bulk upserted.
9. Nearby recordings are linked using the five-minute matching window.
10. Leads are created or updated and call-related status/attempt fields change.
11. Aggregated statistics are recalculated/read by dashboards.

Connected-call metrics are based on positive duration. Missed, rejected, incoming, outgoing, and never-attended values are derived from normalized call types and Mongo aggregation.

Failure points include duplicate or delayed device sync, clock/time-zone differences, partial success between call upsert and lead update, and records that cannot be associated because phone normalization or caller identity is incomplete.

## 7. Recording Lifecycle

### Capture and queue

- The Android service detects call transitions and excluded SIMs.
- It first searches for the phone dialer's native recording.
- If no usable built-in recording is found, it starts fallback microphone capture and writes AAC/M4A.
- A native JSON queue stores pending uploads in private app storage.
- WorkManager retries while network connectivity is available.
- Legacy Flutter preference entries can be migrated into the native queue.

### Upload and persistence

- The client submits recording metadata and base64 audio through the recording upload route.
- The backend accepts larger JSON bodies only on upload paths.
- Filenames are sanitized and recordings are stored below `backend/uploads/recordings`.
- Duplicate caller/filename submissions are handled to reduce repeat records.
- The recording is linked to the nearest call log within five minutes and its lead is updated.

### Playback and review

- Audio is never served as an unrestricted static directory.
- `GET /api/recordings/:id/audio` performs authentication/scope checks and supports byte ranges.
- Manager review can add comments, criteria, ratings, approval/flag status, and notifications.
- Manager-only deletion removes the recording according to route authorization.

Important operational limits are base64 memory/CPU overhead, local-disk durability, weak content-type/file-signature validation, Android OEM differences, and possible microphone-only capture on newer Android versions.

## 8. Flutter Application Logic

### State and transport

- `providers/tele_provider.dart` owns authentication, persisted session, onboarding state, SIM choice, calls, statistics, leads, recordings, notifications, callbacks, playback, and active call sessions.
- `services/api_service.dart` centralizes HTTP calls, bearer headers, timeouts, host failover, session expiry, and response parsing.
- `services/api_parsers.dart` contains pure parsing and matching logic for employees, calls, leads, recordings, callbacks, and phone numbers.
- `services/call_recording_setup.dart` wraps the Android method channel.
- `models/` contains `CallLog`, `Recording`, `Lead`, `Employee`, `Notification`, and `SimCardInfo` data types.

### Screens and workflows

- Onboarding: `onboarding/callyzer_setup_flow.dart`.
- Device setup: `setup/sim_setup_screen.dart` and `setup/call_recording_setup_screen.dart`.
- Authentication: `login_screen.dart` and `splash_screen.dart`.
- Caller dashboard/history/profile: `screens/caller/*`.
- Caller outcome workflow: `call_session_screen.dart`, `log_outcome_screen.dart`, and `scheduled_callbacks_screen.dart`.
- Manager dashboard/team views: `screens/manager/*`.
- Shared lead and recording workflows: `screens/shared/leads_screen.dart` and `recordings_screen.dart`.
- Shared settings/actions: `screens/shared/more_screen.dart`.
- Reusable UI and workflow components: `widgets/` including cards/buttons, filters, dialer, lead dialogs, user creation, contact history, rescheduling, notifications, and setup controls.
- `theme/app_theme.dart` defines the Flutter visual system; the remaining widgets implement the shared Neo-style UI.

Managers can enter a caller-like mode. The provider must narrow data and recording behavior during that mode so the manager does not accidentally operate on unrestricted team data.

## 9. Admin Web Logic

`admin_web/index.html` is a single-file application that combines layout, styling, API calls, state, and event handlers. Its main workflows are:

- admin/manager login and token persistence;
- dashboard KPIs, date/team/user filters, and hourly activity;
- call-log browsing;
- CSV/XLSX lead import;
- lead assignment, pipeline status, and notes;
- employee creation/edit/delete, role/team/manager assignment, targets, and photos;
- leaderboard and view-as-user behavior;
- recording search, playback, review criteria, comments, approval/flagging, deletion, and export;
- profile/avatar management;
- periodic refresh.

The portal stores bearer tokens in `localStorage`, uses query-token audio URLs for media playback, and escapes API-derived HTML in the places where dynamic markup is built. The external SheetJS dependency includes an integrity hash.

Because this is a large single-file client, browser-level tests are particularly important for authorization-sensitive controls, refresh races, import validation, and stale local tokens.

## 10. Root PWA and Design System

The root prototype uses `_ds/askeva-design-system-f369da11-358d-4fcb-8a05-42d32204ae78/`:

- `_ds_bundle.js`: runtime/component bundle.
- `_ds_manifest.json`: component metadata.
- `styles.css` and `tokens/*.css`: design tokens, typography, colors, spacing.
- `readme.md`: component/design usage notes.

`Telesales Monitor App.dc.html` contains prototype manager/caller views, leads, recordings, and onboarding screens. `support.js` and `ios-frame.jsx` support the prototype/runtime. `manifest.json` configures install metadata and `sw.js` provides service-worker caching.

This surface should be treated as a prototype unless it is explicitly connected to the production API. Its cache-first service worker must not cache authenticated API responses if deployed on the same origin.

## 11. Platform and Deployment Logic

- Backend audio is stored on local disk. A multi-instance deployment, redeploy, or disk failure can lose or partition recordings.
- No migration runner, object storage integration, process manager configuration, container definition, backup policy, or retention policy is present in the source tree.
- The mobile recording implementation is Android-specific.
- iOS has no equivalent call-monitoring/recording implementation and should not be represented as feature-equivalent without additional native work.
- Flutter Android release configuration should be checked: the current project report indicates release may use debug signing.
- Production and documentation ports differ: README examples use 5000 while the supplied environment uses 5004.
- The service starts listening independently of asynchronous database readiness; requests can arrive before MongoDB is usable.

## 12. Tests and Verification Coverage

Existing tests:

- `test/api_parsers_test.dart`: phone normalization, lead status conversion, JSON parsing, recording matching, callback times, and API host fallback.
- `test/call_recording_setup_test.dart`: monitor activation, legacy upload migration, OEM recording guidance, and setup status parsing.
- `test/widget_test.dart`: splash/onboarding and invalid legacy-session cleanup.

Missing high-value coverage:

- backend route and middleware integration tests;
- authentication and role/team authorization matrix tests;
- MongoDB persistence, indexes, aggregation, and migration tests;
- upload, range streaming, path safety, deletion, and retry tests;
- concurrency tests for lead uniqueness and call/recording linking;
- Android service, permissions, candidate ranking, queue recovery, WorkManager, and boot tests;
- admin browser and end-to-end tests;
- Flutter-to-backend-to-device synchronization tests;
- iOS behavior tests.

## 13. Security and Reliability Priorities

### Immediate

1. Rotate the MongoDB Atlas password, JWT secret, and admin passcode from `backend/.env`; treat them as compromised because they were exposed in the workspace context.
2. Revoke/invalidate existing JWTs after rotating the signing secret.
3. Set `LEGACY_CLIENT_GRACE=false` after all old builds are upgraded and verify that every sync, recording, lead, notification, and dashboard route rejects unauthenticated impersonation.
4. Add explicit hierarchy checks for junior managers on every user-management and assignment mutation.

### Near term

5. Replace local recording storage with durable object storage or a documented persistent volume, plus backups and retention limits.
6. Validate audio by size, declared type, file signature, duration, and safe decoding; avoid large base64 JSON where multipart or resumable upload is practical.
7. Add database-level uniqueness for normalized lead phone identity where business rules permit it.
8. Add backend integration tests for every permission rule and alias route.
9. Replace long-lived query-string media tokens with short-lived signed URLs or authenticated streaming where possible.
10. Reduce phone/account enumeration through the phone-check flow and rate-limit it according to threat model.

### Operational

11. Delay readiness/listening or expose a readiness state until the database connection is usable.
12. Define deployment, process supervision, disk capacity monitoring, backup, restore, and cleanup procedures.
13. Reconcile README, environment, Android fallback, and production port/host configuration.
14. Separate prototype/PWA caching rules from authenticated API traffic.

## 14. Recommended Verification Order

1. Run Flutter unit/widget tests and static analysis.
2. Start a disposable MongoDB and run backend route/auth integration tests.
3. Test the full authorization matrix: admin, manager, junior manager, caller, invalid token, expired token, and legacy request.
4. Test call sync idempotency and delayed recording linking.
5. Test recording upload, range playback, deletion, retry, and path traversal defenses.
6. Test admin browser workflows with an isolated test account.
7. Test Android on the supported OEM/device matrix, including reboot, excluded SIM, native recording, fallback recording, offline queue, and token expiry.
8. Validate production backup/restore and recording retention before release.

## 15. Overall Assessment

The product has a coherent operational concept: Android captures activity, Flutter provides caller workflows, Express centralizes business rules, MongoDB stores operational data, and the admin portal reviews and manages it. The codebase is more mature than the minimal README suggests, particularly around matching, scoping, retries, and audio access control.

It is not yet production-hardened. Credential rotation, retirement of tokenless compatibility, hierarchy enforcement, durable audio storage, and integration/security testing should be treated as release-blocking work. The root PWA and iOS targets should be documented as prototype/non-equivalent surfaces until their runtime behavior is connected and verified.
