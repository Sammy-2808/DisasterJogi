---
name: flutter-nearby-mesh
description: Use when implementing or debugging the Nearby Connections transport in the Flutter mesh app (Android permissions, advertising, discovery, connection handling, reconnects, framing).
---

# Nearby Connections transport rules

Always verify the `nearby_connections` plugin API against its current README and example before coding. Do not guess method names.

## Permissions (Android)
Declare in `AndroidManifest.xml` and request at runtime BEFORE starting advertising/discovery:
- Android 12+ (API 31+): `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`
- Android 13+ (API 33+): `NEARBY_WIFI_DEVICES` (use `neverForLocation` flag only if location is not derived from Wi-Fi scans)
- All versions: `ACCESS_FINE_LOCATION` (and `ACCESS_COARSE_LOCATION`)
- Legacy (<= API 30): `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`
- Location services (the device toggle) must be ON for discovery on many devices. Check and prompt.
- Show a blocking onboarding screen that explains why each permission is needed.

## Connection rules
- One shared constant `serviceId` (e.g. `com.meshrescue.mesh.v1`). Never inline it.
- `Strategy.P2P_CLUSTER` only.
- Every node advertises AND discovers.
- **Tie-break:** only the node with the lexicographically smaller deviceId calls `requestConnection`. The other waits and auto-accepts. This prevents simultaneous-request conflicts.
- Auto-accept connections. No dialogs.
- Degree cap: 4 simultaneous connections; ignore new discoveries when full.
- Reconnect with exponential backoff (2s, 4s, 8s, cap 60s) per endpoint.
- Duty-cycle discovery when connected to 2+ peers (20s on / 40s off). Advertising stays on.

## Framing
- One protocol frame per Nearby bytes payload: 1 type byte + UTF-8 JSON. See `docs/PROTOCOL.md`.
- Hard cap 4096 bytes. Bytes payloads over ~32 KB are not allowed by Nearby.
- Never block the UI isolate on transport callbacks; hand frames to the engine via a stream.

## Environment
- Requires Google Play Services. Detect absence and show an "unsupported device" screen.
- Transport code lives in `lib/transport/nearby_transport.dart` and implements `MeshTransport`. No protocol logic here; it only moves bytes and reports peer up/down.

## Testing
Radio behaviour cannot be validated in an emulator. After any change to this layer, STOP and ask the human to test on two real phones per the `android-device-testing` skill.
