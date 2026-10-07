# Telesales Admin Portal — React

React version of `admin_web/index.html`. It uses the same backend API and has the same pages and behaviour.
`admin_web/` remains the reference, and the backend is unchanged.

## Run

```bash
# 1. backend (port 5000)
cd backend && npm run dev

# 2. portal (port 5173) — /api is proxied to the backend
cd frontend && npm install && npm run dev
```

Open http://localhost:5173 and sign in with an admin / manager / team-leader account.
Settings are in `.env`, the frontend's only env file (backend URL for the proxy, API base for a hosted build).

## Structure (`src/`)

| Folder | What lives there |
| --- | --- |
| `data/` | Constants, navigation items, every API endpoint path |
| `utils/` | API client (`api.js`), one function per endpoint (`services.js`), formatters, mappers, scope/role rules, Excel, audio player controller |
| `utils/actions/` | The calls the pages make (load, save, sync, refresh): plain async functions that call `services` and put the result in the store with slice actions |
| `redux/` | Store and state only: one slice of plain reducers per area (auth, users, calls, leads, recordings, dashboard, leaderboard, demos, userDetail, ui) + selectors. No thunks (the thunk middleware is off) |
| `routes/` | Page routes + role guard (User Management: admin/manager, Demo Bookings: not callers) |
| `components/common/` | Reusable UI: badges, KPI tiles, tables, pager, chips, avatar, user link… |
| `components/layout/` | Sidebar, header, mobile bar, "view as" banner, docked audio player, main layout (refresh timers) |
| `components/modals/` | Dial outcome, add lead, uploaded-file details |
| `pages/` | One file per screen |
| `styles/global.css` | `:root` colour / font / spacing tokens + base styles |
| `style.css` | Component styles (imports `global.css`, uses only its variables) |

Data flow: `data` → `utils/services` → `utils/actions` → `redux` store (slice actions) → pages/components read it with `useSelector`.
