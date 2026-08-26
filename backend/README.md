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

1. Open a terminal in `d:/Projects/Telesales/backend`:
   ```powershell
   npm install
   npm start
   ```
2. The server runs at `http://localhost:5000`.

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
