# SmartHome — Light Web (Vanilla + HTMX + Firebase)

How to run locally:

1. Install a simple static server or use Python.

- Node:
  ```bash
  npm install -g http-server
  http-server web -p 5000
  ```
- Python:
  ```bash
  python -m http.server 5000 --directory web
  ```

2. Open the site in your browser:

```bash
http://localhost:5000
```

Firebase setup:

1. Open Firebase Console for `smarthome-47214`.
2. In Authentication, enable **Email/Password** sign-in.
3. Create a user with the email you want to use.
4. In Realtime Database, verify your user is approved under `/users/<uid>/status` = `Approved`.

Important config:

- The web app uses the Firebase config in `web/src/firebase-config.js`.
- This file is ignored by Git. You must create it by copying `web/src/firebase-config.example.js` and filling in your credentials.
- If you change Firebase projects, update the config object in `web/src/firebase-config.js`.
- The app reads from `/devices` in the Realtime Database.

Troubleshooting:

- `auth/invalid-login-credentials` means the email/password are not valid for Firebase Authentication.
- `auth/user-not-found` means the user account does not exist in Firebase Auth.
- `auth/network-request-failed` means the browser cannot reach Firebase (check internet/Wi-Fi).
- If devices do not appear, ensure the authenticated user has `/users/<uid>/status` set to `Approved`.

Deployment:

1. Install Firebase CLI and login:
   ```bash
   npm install -g firebase-tools
   firebase login
   ```
2. Initialize hosting in the repo root if not yet done:
   ```bash
   firebase init hosting
   ```
   - Set the public directory to `web`
   - Choose `No` for single-page app rewrite only if prompted, because this is a static app.
3. Deploy:
   ```bash
   firebase deploy --only hosting
   ```

Notes:

- This web app is intentionally lightweight and uses Firebase client SDK directly.
- The login page is styled for a more professional web experience.
- I only modified files under `web/` and did not change other project folders.
