# Telesales Monitoring Backend API (MongoDB + Express)

A REST API backend built with **Node.js**, **Express**, and **MongoDB (Mongoose)** to support both **Admin / Manager** and **User / Caller** functionalities with shared database synchronization.

---

## 📁 Directory Structure

```
d:/Projects/Telesales/backend/
├── .env                  # MongoDB URI & environment variables
├── .env.example          # Environment template
├── package.json          # Node dependencies (express, mongoose, cors, dotenv)
└── src/
    ├── config/
    │   └── db.js         # MongoDB connection handler
    ├── models/
    │   ├── CallLog.js    # Schema for mobile device call logs
    │   ├── Employee.js   # Schema for caller agents & rankings
    │   ├── Lead.js       # Schema for CRM pipeline leads
    │   └── Recording.js  # Schema for audio call recordings
    ├── routes/
    │   ├── admin.js      # APIs for Admin / Manager
    │   ├── user.js       # APIs for User / Caller
    │   └── auth.js       # Authentication APIs
    └── server.js         # Main Express application entrypoint
```

---

## 🚀 How to Run

1. Open a terminal in the repository's `backend` directory:
   ```powershell
   npm install
   npm start
   ```
2. The backend and admin portal run at `http://localhost:5000` by default. A separately served local frontend can call the API at `http://localhost:5000/api`.

### Realtime updates

Socket.IO shares the Express HTTP server on port `5000` and authenticates with the same JWT as the REST API. The React dev server proxies `/socket.io` to the backend; production reverse proxies must also allow WebSocket upgrades on `/socket.io`. Set `VITE_SOCKET_URL` only when the web client must connect to a different public backend origin.

Clients cannot select room names. Admins join `admin:global`; managers join their server-authorized `scope:<employeeId>` room; every signed-in user joins their own `employee:<employeeId>` room. Events are broadcast to the affected employee, their manager reporting chain, and admins. This uses the existing `managerId` / `managerName` authorization scope rather than broad team-name rooms.

REST remains the source of truth. After reconnect, clients refresh with existing REST endpoints; Socket.IO only delivers updates between refreshes.

For local testing, start MongoDB and then run the backend with `npm start` from this directory. In another terminal start the web client with `npm run dev` from `frontend`; the Android emulator connects to `http://10.0.2.2:5000/api` by default. Log in to the web portal and caller app, change a caller lead status or book a demo, then verify live updates without refreshing. Disconnect/reconnect the caller socket to check employee presence events.

### Cloudinary file storage

Recording audio and profile photos are uploaded to Cloudinary. Configure `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, and `CLOUDINARY_API_SECRET` in the backend environment (`.env` or the hosting provider's environment settings); never commit real credentials. The existing recording API keeps serving audio through its authenticated endpoint, and legacy recordings already on disk or in MongoDB remain readable.

To migrate existing local recordings and base64 profile photos, configure the backend environment and run:

```powershell
npm run migrate:cloudinary
```

The migration skips assets already in Cloudinary, updates MongoDB after a successful upload, and does not delete the original local audio files.

---

## 📊 Admin API Endpoints (`/api/admin`)

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/admin/dashboard` | Aggregated team telemetry (total dials, connected calls, talk time, hourly calls histogram) |
| `GET` | `/api/admin/leaderboard` | Live team caller ranks sorted by talk time and dials |
| `GET` | `/api/admin/recordings` | Recording storage quota (GB used) and recorded audio list |
| `GET` | `/api/admin/leads` | Complete CRM pipeline overview (Won, Interested, Follow-up, Other) |
| `GET` | `/api/admin/export/daily` | Generates and exports daily XLSX/PDF telemetry report |

---

## 📱 User / Caller API Endpoints (`/api/user`)

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/user/calls/sync` | Batch push device call logs from phone to MongoDB |
| `POST` | `/api/user/recordings/upload` | Saves auto-recorded call audio file and metadata |
| `GET` | `/api/user/leads` | Retrieves leads assigned to the active caller |
| `PUT` | `/api/user/leads/:id/status` | Updates lead pipeline status (*Won, Interested, Follow-up, etc.*) and notes |

---

## 🔐 Auth API Endpoints (`/api/auth`)

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/auth/admin-login` | Authenticates administrator with email & passcode |
| `POST` | `/api/auth/caller-verify` | Validates caller SIM hardware & phone number |
