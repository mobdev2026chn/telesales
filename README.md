# Telesales Application

This repository contains the complete source code for the **Telesales Platform**, including the Flutter mobile application and the Express/Node.js backend server.

---

## 📁 Repository Structure

```
.
├── backend/            # Express.js + MongoDB Backend API
└── telesales_monitor/  # Flutter Mobile App for Android/iOS
```

---

## 🚀 Quick Start

### 1. Backend (`/backend`)
The backend provides REST APIs for authentication, call log telemetry sync, CRM lead management, and admin dashboard reporting.

```bash
cd backend
npm install
npm run dev
```

Server runs by default at `http://localhost:5000`. Refer to [`backend/README.md`](file:///backend/README.md) for full API documentation.

### 2. Flutter App (`/telesales_monitor`)
The mobile application monitors call logs, records telemetry, and synchronizes call activities with the backend server.

```bash
cd telesales_monitor
flutter pub get
flutter run
```

---

## 🔐 Environment Setup

Make sure to create a `.env` file in the `backend/` directory based on `backend/.env.example`:

```env
PORT=5000
MONGODB_URI=mongodb://127.0.0.1:27017/telesales_db
JWT_SECRET=your_jwt_secret_here
CORS_ORIGIN=*
```
