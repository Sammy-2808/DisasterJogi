---
name: android-device-testing
description: Use at every human checkpoint and whenever radio, permission or multi-device behaviour must be validated on physical Android phones.
---

# Physical device testing protocol

The agent cannot test Bluetooth, Wi-Fi Direct or Nearby Connections. Only the human with real phones can. Never claim radio functionality works without the human's confirmation.

## Setup (tell the human)
1. Enable Developer options and USB debugging on each phone.
2. `adb devices` should list every phone. For wireless: `adb pair` then `adb connect`.
3. Install on a specific phone: `flutter run -d <deviceId>` (one terminal per phone) or `flutter install -d <deviceId>`.
4. Grant all runtime permissions on first launch; confirm Location is ON.
5. Test with airplane mode ON and Bluetooth + Wi-Fi turned back ON, to mimic a dead network.

## Logs
- Per-phone: `adb -s <deviceId> logcat -s flutter`
- Transport debug lines should be prefixed `[MESH]` so they can be filtered: `adb -s <deviceId> logcat | grep MESH`
- Ask the human to paste logs from ALL phones for the same time window when something fails.

## Checkpoint protocol
At each HUMAN CHECKPOINT the agent must:
1. STOP coding.
2. State the exact test: which phones, where they stand, what to tap, what should appear.
3. List what failure looks like and which logs to paste.
4. Wait for the human's result before continuing.

## Standard tests
- **2 phones:** both show each other as peers within about 30 seconds, one connection each, no flapping. A test message from A appears on B.
- **3-phone line:** A and C out of range (different rooms or about 15 m with a wall), B between. A sends a message; C receives it with hops = 1.
- **Reconnect:** turn Bluetooth off and on on B; mesh recovers without restarting the app.
- **Late joiner:** phone D joins after messages exist and receives them through sync.

## Common failures to check first
Location services off, permission denied or only "approximate", Google Play Services missing, battery optimisation killing the app, both devices initiating connections (tie-break bug), stale advertising after hot restart (fully stop the app between runs).
