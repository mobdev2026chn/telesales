# UI redesign backup (2026-09-24)

A saved copy of the modern SaaS redesign of the admin portal. It is **not** the live portal:
the server only serves files from `admin_web/`, never this folder.

- `admin_web/index.html`, `admin_web/design-system.css` — the redesigned portal page and its design system.
- `backend/src/server.js` — server.js as it was with the redesign (adds `design-system.css` to the served files).
- `index.html.patch` — the redesign as a diff against the portal at that time.
- `original-index.html` — the portal before the redesign.
- `screenshots/` — one screenshot per page (sample data, not real users).

This copy predates the later features (pinned recordings, round-robin assignment, Demo Bookings,
Team Leader role, Managed-by hierarchy / filter, Leads Pipeline "View more"). To use the redesign,
those features must first be rebuilt into it.
