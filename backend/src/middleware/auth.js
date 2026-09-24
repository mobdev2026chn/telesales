const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const presence = require('../services/presence');
const Employee = require('../models/Employee');

const TOKEN_TTL = '30d';

function getSecret() {
  const secret = process.env.JWT_SECRET;
  if (!secret || secret.length < 16) {
    throw new Error('JWT_SECRET is missing or too short (min 16 chars). Set it in backend/.env');
  }
  return secret;
}

// Old app builds send no token. While LEGACY_CLIENT_GRACE=true they may still use the
// caller sync/read endpoints (marked `legacy`) so phones keep working until updated.
function legacyGraceEnabled() {
  return String(process.env.LEGACY_CLIENT_GRACE || 'true').toLowerCase() === 'true';
}

function normalizeRole(role) {
  return (role || 'caller').toString().toLowerCase();
}

function signToken(emp) {
  return jwt.sign(
    {
      sub: emp.id,
      role: normalizeRole(emp.role),
      name: emp.name,
      phone: emp.phone || '',
      team: emp.team || '',
    },
    getSecret(),
    { expiresIn: TOKEN_TTL }
  );
}

function isHashed(stored) {
  return typeof stored === 'string' && /^\$2[aby]\$\d{2}\$/.test(stored);
}

async function hashPassword(plain) {
  return bcrypt.hash(String(plain), 10);
}

// Verifies a password against the stored value. Legacy plaintext passwords are accepted once
// and immediately replaced with a bcrypt hash ("hash on next login").
async function verifyAndUpgradePassword(emp, plain) {
  const stored = emp.password;
  if (!plain || !stored) return false;
  if (isHashed(stored)) return bcrypt.compare(String(plain), stored);
  if (String(plain).trim() !== String(stored).trim()) return false;
  emp.password = await hashPassword(String(plain).trim());
  await emp.save({ validateBeforeSave: false });
  return true;
}

function readToken(req) {
  const header = req.headers.authorization || '';
  if (header.startsWith('Bearer ')) return header.slice(7).trim();
  // <audio src> cannot send headers, so audio URLs carry the token as a query parameter
  if (req.query && typeof req.query.token === 'string') return req.query.token;
  return null;
}

// The token only proves WHO is signed in. Role / team / name come from the account as it is now,
// so a caller promoted to manager (or a manager moved back) gets the new access without logging
// out. Looked up at most every few seconds per user; changes via the users API apply at once.
const PROFILE_TTL_MS = 15 * 1000;
const profileCache = new Map(); // id -> { at, emp | null }

async function currentProfile(id) {
  const hit = profileCache.get(id);
  if (hit && Date.now() - hit.at < PROFILE_TTL_MS) return hit.emp;
  const emp = await Employee.findOne({ id }).select('id role team name phone').lean();
  profileCache.set(id, { at: Date.now(), emp: emp || null });
  if (profileCache.size > 5000) profileCache.delete(profileCache.keys().next().value);
  return emp || null;
}

function forgetProfile(id) {
  if (id) profileCache.delete(String(id)); else profileCache.clear();
}

// Global, non-blocking: attaches req.user when a valid token is present and pins the
// scoping parameters the routes read to the account's identity (clients can't claim another role).
async function authenticate(req, res, next) {
  req.user = null;
  const token = readToken(req);
  if (token) {
    try {
      const payload = jwt.verify(token, getSecret());
      req.user = {
        id: payload.sub,
        role: normalizeRole(payload.role),
        name: payload.name,
        phone: payload.phone,
        team: payload.team,
      };
    } catch (_) {
      req.tokenInvalid = true;
    }
  }
  if (req.user) {
    try {
      const emp = await currentProfile(req.user.id);
      if (!emp) {
        // Account deleted: the token no longer signs anyone in
        req.user = null;
        req.tokenInvalid = true;
      } else {
        req.user.role = normalizeRole(emp.role);
        req.user.team = emp.team || '';
        req.user.name = emp.name || req.user.name;
        req.user.phone = emp.phone || req.user.phone;
      }
    } catch (_) {
      // Database unreachable: keep what the token says rather than failing every request
    }
  }
  if (req.user) {
    const pin = (obj) => {
      if (!obj || typeof obj !== 'object') return;
      obj.loggedInRole = req.user.role;
      obj.loggedInUserId = req.user.id;
      obj.loggedInTeam = req.user.team;
      delete obj.userRole;
      if (req.user.role === 'caller') {
        // A caller only ever sees their own data
        obj.userId = req.user.id;
        delete obj.callerIds;
        delete obj.callerPhone;
        delete obj.callerName;
        delete obj.callerId;
        delete obj.team;
        delete obj.managerId;
      }
    };
    pin(req.query);
    if (req.body && typeof req.body === 'object' && !Array.isArray(req.body)) pin(req.body);
    // Any signed-in request means the user is active (the logout request itself does not count)
    if (!/\/auth\/logout$/.test(req.path)) presence.touch(req.user.id);
  }
  next();
}

// requireAuth({ roles, legacy }) — roles: allowed roles (default: any signed-in user);
// legacy: allow token-less old app builds during the grace period.
function requireAuth({ roles = null, legacy = false } = {}) {
  return (req, res, next) => {
    if (req.user) {
      if (roles && !roles.includes(req.user.role)) {
        return res.status(403).json({ success: false, message: 'You do not have permission for this action.' });
      }
      return next();
    }
    if (legacy && !req.tokenInvalid && legacyGraceEnabled()) {
      req.legacyClient = true;
      return next();
    }
    return res.status(401).json({ success: false, message: 'Please log in again.', code: 'AUTH_REQUIRED' });
  };
}

const MANAGERS = ['admin', 'manager', 'jr_manager', 'team_leader'];

module.exports = {
  signToken,
  hashPassword,
  isHashed,
  verifyAndUpgradePassword,
  authenticate,
  forgetProfile,
  requireAuth,
  legacyGraceEnabled,
  MANAGERS,
};
