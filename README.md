# MeshRescue

Offline, infrastructure-free peer-to-peer disaster mesh communication app for Android. Phones discover one another over Bluetooth and Wi-Fi Direct (`nearby_connections`, `Strategy.P2P_CLUSTER`) and relay SOS alerts, hazard reports, and cryptographically verified shelter listings hop-by-hop with **no internet, no cellular signal, and no servers**.

---

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│ UI Layer (Flutter, Riverpod)                              │
│ Home · Feed · Radar/Map · SOS · Hazard · Shelters ·       │
│ Responder Panel · Debug & Security Demo · 20-Node Sim     │
├───────────────────────────────────────────────────────────┤
│ Application Services                                      │
│ MeshController · LocationService · ExpiryService          │
├───────────────────────────────────────────────────────────┤
│ MESH ENGINE (pure Dart — zero Flutter imports)            │
│ decode → validate → dedup → verify → store → apply → fwd  │
│ Priority Outbox · HELLO/INV/REQ/MSG Sync · Rate Limiter   │
├───────────────────────────────────────────────────────────┤
│ MeshTransport (abstract interface)                        │
│   ├── NearbyTransport (Android P2P_CLUSTER)               │
│   └── SimTransport / SimWorld (virtual radios)            │
├───────────────────────────────────────────────────────────┤
│ Storage & Crypto                                          │
│ Drift (SQLite) · Ed25519 + SHA-256 (`cryptography`)       │
└───────────────────────────────────────────────────────────┘
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/PROTOCOL.md](docs/PROTOCOL.md), [docs/SECURITY_TRUST.md](docs/SECURITY_TRUST.md), and [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for the full specification.

---

## Key Features Implemented

- **Multi-hop Store-and-Forward Gossip:** `TTL` cap `10`, per-message UUID deduplication, priority outbox (`SOS > ACK > SHELTER > HAZARD`), per-origin token-bucket rate limiting (`10/min`), and `HELLO / INV / REQ / MSG` anti-entropy sync (with `50`-item `INV` frame chunking under the `4096 B` cap).
- **SOS Lifecycle:** Hold-2s emergency SOS button with progress ring and haptic feedback; derived states `ACTIVE → ACKNOWLEDGED (RECEIVED / DISPATCHED) → RESOLVED / EXPIRED`; local `"I'm Safe"` cancellation signed by origin key; automatic rebroadcast every `30s` (`60s` in Battery Saver).
- **Hazard Clustering & Confirmation:** Merges hazards by `(kind, geohash-7)` and promotes single reports (`REPORTED`) to `CONFIRMED` at `2+` distinct origins (`+6h` expiry per confirmation; `48h` for responder-signed hazards).
- **Offline Cryptographic Trust:** Ed25519 signatures over canonical JSON (`engine/canonical_json.dart`). Shelters show **Verified** only when signed by a public key in `assets/trusted_responders.json`; untrusted or forged shelters are downgraded to `UNVERIFIED` and hidden by default.
- **Zero-Tile Radar View + Pin Canvas:** `CustomPainter` radar plots SOS, hazards, and verified shelters by Haversine distance and great-circle bearing without needing map tiles.
- **Built-in 20-Node Simulator:** Visualizes hop-by-hop propagation, random walk movement, node failures, and partition healing via a moving "data mule" node.
- **Demo Responder Mode & Security Demo:** PIN-gated (`2026`, clearly marked **DEMO ONLY**) responder signing panel plus `"Inject Forged Shelter"` debug tool to demonstrate rejection of unsigned (`BAD_SIG`) and untrusted (`UNVERIFIED`) shelters.

---

## How to Test (Headless Engine, Crypto, Domain, Drift & Simulator)

No physical phones or emulator needed for the automated test suite:

```powershell
flutter analyze
flutter test --reporter expanded
```

Key test suites:
- `test/engine/canonical_json_test.dart` — canonical JSON determinism and key-order invariance
- `test/crypto/signer_and_trust_test.dart` — Ed25519 sign/verify, tamper detection, origin/key match, trust tiers
- `test/engine/mesh_engine_test.dart` — validation drop reason codes, dedup, TTL clamp/stop, outbox priority, rate limit, storage eviction, abuse blocking
- `test/engine/sync_test.dart` — `HELLO/INV/REQ/MSG` convergence, >50-item `INV` chunking, version mismatch disconnect
- `test/domain/domain_logic_test.dart` — SOS lifecycle, hazard clustering/confirmation, shelter `seq` supersession
- `test/sim/simulator_test.dart` — **5-node line (`A-B-C-D-E`) SOS & ACK trace**, **partition healing via data mule**, packet-loss recovery
- `test/data/drift_message_store_test.dart` — SQLite/Drift schema, outbox persistence, expiry purge, DEMO responder key match
- `test/transport/nearby_transport_test.dart` — tie-break rule, degree cap of 4, exponential backoff, frame size cap (mocked `NearbyApi`)
- `test/widget_test.dart` — bottom navigation, accidental SOS tap guard, Verified vs. Forged shelter UI safety rules

---

## How to Run on Android Phones

Requires Android `7.0+` (`minSdk = 24`) with **Google Play Services**.

```powershell
flutter build apk --debug
adb -s <deviceId> install -r build/app/outputs/flutter-apk/app-debug.apk
```

For offline mesh testing on physical phones:
1. Enable Airplane Mode, then turn **Bluetooth** and **Wi-Fi** back ON.
2. Grant all runtime permissions (including **Precise** location) and ensure the device **Location** toggle is ON.
3. Monitor transport logs via `adb -s <deviceId> logcat | findstr MESH` (or `grep MESH`).

---

## Honest Limitations (v1)

- **Android + Google Play Services only.** iOS and de-Googled Android devices are not supported by `nearby_connections`.
- **Radio range is limited** (roughly 30–100 m indoors, further outdoors); mesh coverage depends on phone density.
- **Gossip flooding** does not scale to thousands of concurrent nodes without geographic or spray-and-wait routing.
- **No confidentiality in v1.** Broadcast SOS reveals location to every node in the mesh by design (life safety over privacy).
- **Pre-provisioned trust list.** `assets/trusted_responders.json` ships with the app; there is no dynamic responder revocation list in v1.
- **Demo responder key is for hackathon testing only.** Replace `assets/trusted_responders.json` and distribute real keys out-of-band before any real deployment.
- **Foreground execution.** Without a dedicated Android foreground service, Android OS power management may suspend background mesh relaying when the screen is off.
