# SmartHome Project Context

## Project scope

This repository is a multi-part smart home system built around:

- `esp32_firmware/`: Arduino IDE firmware for an ESP32 hub that connects to Firebase RTDB and controls relays.
- `flutter_app/`: Flutter mobile companion for Android with Firebase integration.
- `firebase_backend/`: Firebase Realtime Database rules and seed data.
- `web/`: lightweight web frontend built separately to avoid changes in other project folders.

## Current web focus

The current priority is the `web/` frontend:

- A static web app served from `web/`.
- Uses Firebase JS SDK v9 modular imports.
- Supports Firebase Authentication with Email/Password.
- Reads device data from RTDB path `/devices`.
- Displays device cards and status in a dashboard.
- Has a login page with improved UI and error handling.

## Web files

- `web/index.html` — login page and dashboard shell.
- `web/assets/styles.css` — dark theme and responsive layout.
- `web/src/firebase.js` — Firebase initialization config.
- `web/src/main.js` — auth flows, realtime device listener, rendering.
- `web/README.md` — setup guide and troubleshooting for local run and Firebase config.

## Known context and issues

- The web UI must authenticate via Firebase Auth, not only RTDB seed data.
- A login failure was traced to the fact that the seeded RTDB user entry does not guarantee a Firebase Auth account exists.
- The team wants the login page polished and the web setup documented clearly.
- The current web app is intentionally lightweight and does not use a build system.

## Firebase context

- Project: `smarthome-47214` (Firebase Auth + Realtime Database).
- Firebase Auth Email/Password must be enabled.
- RTDB nodes include `/devices/<deviceId>/components/relay_1` and `/devices/<deviceId>/components/relay_2`.
- The web app currently listens to `/devices` and renders device metadata and relay components.
- The web renderer accepts both explicit `type:OUTPUT, ui_element:SWITCH` metadata and auto-detects relay components by key prefix (`relay_*`), so it works with both seeded data and firmware-created data.
- The firmware updates `metadata/status` and `metadata/last_boot_report`.

## Firmware context (related but not the primary web problem)

- `esp32_firmware/src/main/config.h` holds Wi-Fi/Firebase credentials and relay pin configuration.
- `esp32_firmware/src/main/main.ino` implements:
  - dual-core FreeRTOS tasks: network and hardware.
  - NTP-based schedule evaluation.
  - Firebase RTDB stream listener and write queue.
  - persistence of relay state to Preferences with debounce.
- Support for second relay has been added in the firmware logic.

## Brainstorming goals for web

Use this context to discuss and decide:

- What web features are most important now?
  - Login flow? device list? relay control? schedule view?
- What should the web UI look like relative to the Flutter app?
- Which Firebase data paths and security constraints must the web app support?
- Should the web app support both `relay_1` and `relay_2` toggles?
- How to make the web app robust when the device is offline or RTDB rules block access?

## Useful questions for AI brainstorming

- What is the simplest web architecture for this project while keeping Firebase auth and RTDB integration clean?
- How can the web app help verify that Firebase Auth and RTDB are configured correctly?
- What is the best UI pattern for displaying multiple relay components from the device model?
- How can the web page stay lightweight and still support real-time updates from Firebase?
- Which user experience improvements would reduce support friction for login and access issues?

## Current state summary

- The web frontend is present and functional as a simple dashboard.
- The login page has been improved, but final UX and data presentation may still need refinement.
- The overall project still includes Flutter and firmware, but the immediate brainstorming should focus on solving the web layer.
