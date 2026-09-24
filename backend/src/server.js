const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const fs = require('fs');
const path = require('path');
const connectDB = require('./config/db');
const seedAdminUsers = require('./config/seedAdmin');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { authenticate, requireAuth, MANAGERS } = require('./middleware/auth');

const envCandidates = [
  path.join(__dirname, '../uploads/.env'),
  path.join(__dirname, '../.env'),
];
const envPath = envCandidates.find((candidate) => fs.existsSync(candidate));
if (envPath) {
  dotenv.config({ path: envPath });
} else {
  dotenv.config();
}

const adminRoutes = require('./routes/admin');
const userRoutes = require('./routes/user');
const authRoutes = require('./routes/auth');
const recordingRoutes = require('./routes/recordings');
const leadRoutes = require('./routes/leads');
const notificationRoutes = require('./routes/notifications');
const diagnosticsRoutes = require('./routes/diagnostics');
const demoRoutes = require('./routes/demos');

// Connect to MongoDB, then create the first admin if (and only if) there is none
connectDB().then((connected) => {
  if (connected) seedAdminUsers().catch((err) => console.error('Admin seed failed:', err.message));
});

const app = express();
const PORT = process.env.PORT || 5000;

app.set('trust proxy', 1);

// Security headers. CSP stays off because the admin page uses inline scripts/handlers.
app.use(helmet({ contentSecurityPolicy: false, crossOriginResourcePolicy: { policy: 'same-site' } }));

// CORS: the admin web is same-origin and the mobile app is not a browser, so only explicitly
// configured origins (CORS_ORIGIN, comma separated; '*' ignored) and localhost in development.
const allowedOrigins = (process.env.CORS_ORIGIN || '').split(',').map(o => o.trim()).filter(o => o && o !== '*');
app.use(cors({
  origin: (origin, cb) => {
    if (!origin) return cb(null, true);
    if (allowedOrigins.includes(origin)) return cb(null, true);
    if (process.env.NODE_ENV !== 'production' && /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) return cb(null, true);
    return cb(null, false);
  },
}));

// Large bodies only where base64 audio is uploaded; everything else stays small
const uploadPaths = ['/api/recordings', '/api/user/recordings/upload', '/api/admin/recordings'];
app.use(uploadPaths, express.json({ limit: '60mb' }));
app.use(['/api/admin/users/photo', '/api/user/photo', '/api/users/photo'], express.json({ limit: '5mb' }));
app.use('/api/admin/leads/import', express.json({ limit: '5mb' }));
app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ limit: '2mb', extended: true }));

// Auth: attach req.user from the Bearer token, throttle login attempts
app.use('/api', authenticate);
app.use(['/api/auth/login', '/api/auth/admin-login', '/api/auth/caller-verify', '/api/auth/check-phone'],
  rateLimit({ windowMs: 15 * 60 * 1000, limit: 30, standardHeaders: true, legacyHeaders: false,
    message: { success: false, message: 'Too many attempts. Please wait a few minutes and try again.' } }));

// Permission table for every /api route. First match wins; anything unlisted needs a signed-in user.
// legacy: token-less old app builds may keep using it during the grace period (LEGACY_CLIENT_GRACE).
const ANY = null;
const ROUTE_RULES = [
  { test: (m, p) => p === '/health' || p.startsWith('/auth/'), rule: 'public' }, // auth routes guard themselves
  { test: (m, p) => m === 'DELETE' && /^\/admin\/users\//.test(p) && !/photo/.test(p), rule: requireAuth({ roles: ['admin'] }) },
  { test: (m, p) => /^\/(admin\/)?users?\/photo$|^\/admin\/users\/[^/]+\/photo$/.test(p), rule: requireAuth({ roles: ANY, legacy: true }) },
  // No legacy access: old app builds log in by downloading this list and checking passwords on the phone,
  // so they can no longer start NEW sessions. Already-signed-in old builds keep syncing via the rules below.
  { test: (m, p) => m === 'GET' && p === '/admin/users', rule: requireAuth({ roles: MANAGERS }) },
  { test: (m, p) => /^\/admin\/users/.test(p), rule: requireAuth({ roles: MANAGERS }) },
  { test: (m, p) => m === 'GET' && p === '/admin/calls', rule: requireAuth({ roles: MANAGERS }) },
  { test: (m, p) => /\/recordings\/[^/]+\/comment$/.test(p), rule: requireAuth({ roles: MANAGERS, legacy: true }) },
  { test: (m, p) => /\/recordings\/[^/]+\/review$/.test(p), rule: requireAuth({ roles: MANAGERS }) },
  { test: (m, p) => /\/recordings\/[^/]+\/pin$/.test(p), rule: requireAuth({ roles: MANAGERS }) },
  { test: (m, p) => m === 'DELETE' && /recordings\//.test(p), rule: requireAuth({ roles: MANAGERS }) },
  { test: (m, p) => /^\/(user\/)?calls\/sync$/.test(p), rule: requireAuth({ roles: ANY, legacy: true }) },
  { test: (m, p) => /recordings/.test(p), rule: requireAuth({ roles: ANY, legacy: true }) },
  { test: (m, p) => /notifications/.test(p), rule: requireAuth({ roles: ANY, legacy: true }) },
  { test: (m, p) => /^\/(admin\/)?dashboard|^\/dashboard\/stats|leaderboard/.test(p), rule: requireAuth({ roles: ANY, legacy: true }) },
  // Lead writes: create / import / distribute are for managers; PUT /admin/leads/:id checks per-lead permissions itself
  { test: (m, p) => m === 'POST' && /^\/admin\/leads(\/import|\/distribute)?\/?$/.test(p), rule: requireAuth({ roles: MANAGERS }) },
  { test: (m, p) => m === 'DELETE' && /^\/admin\/leads\/batch\//.test(p), rule: requireAuth({ roles: MANAGERS }) },
  { test: (m, p) => m === 'PUT' && /^\/admin\/leads\/[^/]+\/?$/.test(p) && !/\/status\/?$/.test(p), rule: requireAuth({ roles: ANY }) },
  { test: (m, p) => /leads|contacts/.test(p), rule: requireAuth({ roles: ANY, legacy: true }) },
];
app.use('/api', (req, res, next) => {
  const hit = ROUTE_RULES.find(r => r.test(req.method, req.path));
  if (hit && hit.rule === 'public') return next();
  return (hit ? hit.rule : requireAuth())(req, res, next);
});

// Admin web: serve ONLY the portal's own files. admin_web/ also holds internal documents
// and shortcuts that must never be downloadable from the public site.
const ADMIN_WEB_DIR = path.join(__dirname, '../../admin_web');
const ADMIN_WEB_FILES = new Set([
  'index.html', 'manifest.json', 'favicon.ico', 'apple-touch-icon.png',
  'ask_eva_logo.png', 'ask_eva_logo.jpg', 'ask_eva_logo_192.png', 'ask_eva_logo_512.png',
]);
function serveAdminWeb(req, res, next) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return next();
  const name = req.path === '/' ? 'index.html' : req.path.replace(/^\//, '');
  if (!ADMIN_WEB_FILES.has(name)) return next();
  res.sendFile(path.join(ADMIN_WEB_DIR, name));
}
app.use(['/admin', '/web'], serveAdminWeb);
app.use(serveAdminWeb);
app.use('/assets/images', express.static(path.join(__dirname, '../../telesales_monitor/assets/images')));
// Call audio is NOT served statically: it goes through the authenticated /api/recordings/:id/audio route only.

// Health check endpoint
app.get(['/health', '/api/health'], (req, res) => {
  res.json({ success: true, status: 'ok', domain: 'telesales', timestamp: Date.now() });
});

// Direct logo handler
app.get(['/ask_eva_logo.jpg', '/ask_eva_logo.png', '/admin/ask_eva_logo.jpg', '/admin/ask_eva_logo.png', '/web/ask_eva_logo.png'], (req, res) => {
  const p1 = path.join(__dirname, '../../admin_web/ask_eva_logo.png');
  if (fs.existsSync(p1)) return res.sendFile(p1);
  const p2 = path.join(__dirname, '../../admin_web/ask_eva_logo.jpg');
  if (fs.existsSync(p2)) return res.sendFile(p2);
  const p3 = path.join(__dirname, '../uploads/ask_eva_logo.jpg');
  if (fs.existsSync(p3)) return res.sendFile(p3);
  res.status(404).send('Logo not found');
});

// Feature routers (absolute paths; one implementation per endpoint, all URL aliases included)
app.use(recordingRoutes);
app.use(leadRoutes);
app.use(notificationRoutes);
app.use(diagnosticsRoutes);
app.use(demoRoutes);
app.use(userRoutes);

// Aliases used by the mobile app
app.use('/api/dashboard/stats', (req, res, next) => {
  req.url = '/dashboard' + (req.url === '/' ? '' : req.url);
  adminRoutes(req, res, next);
});
app.use('/api/employees/leaderboard', (req, res, next) => {
  req.url = '/leaderboard' + (req.url === '/' ? '' : req.url);
  adminRoutes(req, res, next);
});

app.use('/api/admin', adminRoutes);
app.use('/api/auth', authRoutes);

// Unknown API routes: JSON 404 instead of the HTML page
app.use('/api', (req, res) => res.status(404).json({ success: false, message: 'Not found' }));

// Last-resort error handler (malformed JSON, oversized bodies, unexpected errors): never leak internals
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  const status = err && (err.status || err.statusCode);
  if (status && status >= 400 && status < 500) {
    return res.status(status).json({ success: false, message: status === 413 ? 'Request too large' : 'Invalid request' });
  }
  console.error('[unhandled]', err && err.stack ? err.stack : err);
  return res.status(500).json({ success: false, message: 'Something went wrong. Please try again.' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Telesales Backend API running on http://0.0.0.0:${PORT}`);
});
