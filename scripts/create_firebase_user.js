#!/usr/bin/env node
/**
 * Usage:
 *   node scripts/create_firebase_user.js /path/to/serviceAccountKey.json uid email password
 * OR set env GOOGLE_APPLICATION_CREDENTIALS to the service account json path and run:
 *   node scripts/create_firebase_user.js uid email password
 *
 * This script will:
 *  - create a Firebase Auth user with the given uid/email/password if missing
 *  - copy the matching user entry from firebase_backend/seed.json into Realtime Database under /users/<uid>
 *
 * WARNING: keep your service account JSON private. Do not commit it to the repo.
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const arg0 = process.argv[2];
let serviceKeyPath = null;
let uid = 'user_owner_nadif123';
let email = 'nadiffijri64@gmail.com';
let password = 'suprax125';

if (arg0 && arg0.endsWith('.json') && fs.existsSync(arg0)) {
  serviceKeyPath = arg0;
  uid = process.argv[3] || uid;
  email = process.argv[4] || email;
  password = process.argv[5] || password;
} else if (process.env.GOOGLE_APPLICATION_CREDENTIALS && fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS)) {
  serviceKeyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  uid = arg0 || uid;
  email = process.argv[3] || email;
  password = process.argv[4] || password;
} else {
  console.error('Provide service account JSON path as first arg or set GOOGLE_APPLICATION_CREDENTIALS');
  console.error('Usage: node scripts/create_firebase_user.js /path/to/serviceAccountKey.json uid email password');
  process.exit(1);
}

const key = require(path.resolve(serviceKeyPath));

admin.initializeApp({ credential: admin.credential.cert(key), databaseURL: 'https://smarthome-47214-default-rtdb.asia-southeast1.firebasedatabase.app' });

async function main() {
  try {
    let userExists = true;
    try {
      await admin.auth().getUser(uid);
      console.log('Auth user exists:', uid);
    } catch (e) {
      if (e.code && e.code === 'auth/user-not-found') {
        userExists = false;
      } else {
        throw e;
      }
    }

    if (!userExists) {
      const created = await admin.auth().createUser({ uid, email, password });
      console.log('Created auth user:', created.uid);
    }

    // Try to copy seed user node if present
    const seedPath = path.resolve(__dirname, '..', 'firebase_backend', 'seed.json');
    if (fs.existsSync(seedPath)) {
      const seed = JSON.parse(fs.readFileSync(seedPath, 'utf8'));
      // Find first matching user entry by email or fallback to user_owner_nadif123
      let seedEntry = null;
      if (seed.users) {
        // Try find by email
        for (const keyId of Object.keys(seed.users)) {
          const u = seed.users[keyId];
          if (u.email === email) { seedEntry = u; break; }
        }
        if (!seedEntry && seed.users[uid]) seedEntry = seed.users[uid];
      }
      if (seedEntry) {
        await admin.database().ref(`/users/${uid}`).set(seedEntry);
        console.log('Wrote /users/' + uid + ' from seed.json');
      } else {
        console.log('No matching user entry found in firebase_backend/seed.json to copy');
      }
    } else {
      console.log('seed.json not found at', seedPath);
    }

    console.log('Done. You can now sign in with the created credentials.');
    process.exit(0);
  } catch (err) {
    console.error('Error:', err);
    process.exit(1);
  }
}

main();
