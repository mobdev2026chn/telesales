# Telesales Monitor

## Connect to a local backend

Run the backend on port `5000`. Debug builds use `http://10.0.2.2:5000/api` first
when no `API_URL` is supplied, so an Android emulator shares the local backend and
admin portal data. If the local backend is unavailable, sign-in fails instead of
silently switching to a different production database.

For a physical Android device on the same network as the computer, run the app with
the computer's LAN address:

```powershell
flutter run --dart-define=API_URL=http://<COMPUTER-LAN-IP>:5000/api
```

The backend must be reachable from the device (including through the Windows
firewall). Before building, `scripts/build_testing_apk.ps1` checks
`http://<COMPUTER-LAN-IP>:5000/api/health` from the computer. This confirms the
backend endpoint is up, but the phone must also be able to reach it: keep both
devices on the same Wi-Fi and allow inbound TCP port 5000 through Windows
Firewall. Open the same health URL in the phone's browser to diagnose the
phone-to-PC network path. Mobile sign-ins, presence, and synced calls will then
use the same local database. Open the admin portal at `http://localhost:5000`.

The app does not retry a custom backend URL against the emulator or production
server. This prevents a local testing build from silently sending requests to a
different database.

Release builds continue to use the configured HTTPS production API by default.
