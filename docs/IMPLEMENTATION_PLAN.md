# MeshRescue: Implementation Plan

Read `ARCHITECTURE.md`, `PROTOCOL.md` and `SECURITY_TRUST.md` first. This plan sequences the work. Phases must be done in order; each ends with acceptance criteria and, where marked, a **HUMAN CHECKPOINT**, a point where the agent must stop and ask the human to test on physical phones.

## Time budgeting

Percentages scale to any hackathon length.

| Phase | Share | If 9h total | If 24h total |
|---|---|---|---|
| 1 Skeleton | 8% | 45 min | 2 h |
| 2 Engine + simulator (pure Dart) | 25% | 2 h | 6 h |
| 3 Real transport | 20% | 1 h 45 min | 5 h |
| 4 Features and UI | 27% | 2 h 15 min | 6 h 30 min |
| 5 Trust and responder mode | 10% | 1 h | 2 h 30 min |
| 6 Polish, demo, README | 10% | 1 h | 2 h |

**Strategy note:** the engine and simulator come *before* the real radio. They can be tested without phones, so the agent can make real progress while humans wait on devices. Real Nearby transport is then a thin adapter.

---

## Phase 1: Skeleton

**Tasks**
- `flutter create` (Android only). Set `minSdkVersion` per the `nearby_connections` plugin requirement (verify; typically 21+).
- Add dependencies: `flutter_riverpod`, `drift`, `sqlite3_flutter_libs`, `cryptography`, `geolocator`, `uuid`, `nearby_connections`, `flutter_map`, `latlong2`, `flutter_secure_storage`, `permission_handler` (verify each on pub.dev).
- Create the folder structure from `ARCHITECTURE.md` section 14.
- Declare Android permissions in `AndroidManifest.xml` per the `flutter-nearby-mesh` skill.
- Theme: high contrast, large targets.
- App shell with bottom navigation (Home, Feed, Map, Shelters) and empty screens.

**Acceptance:** `flutter analyze` clean; app launches on a phone; navigation works.

---

## Phase 2: Engine and simulator (pure Dart)

**Tasks**
1. `engine/models/`: `Envelope`, `Frame`, enums, JSON (de)serialisation.
2. `engine/canonical_json.dart` + fixed test vectors.
3. `crypto/signer.dart`: Ed25519 sign/verify via `cryptography`; origin derivation.
4. `engine/mesh_engine.dart`: receive pipeline, send pipeline, validation with reason codes, forwarding policy.
5. `engine/outbox.dart`: priority queue, per-peer delivery tracking, SOS rebroadcast timer (injectable `Clock`).
6. `engine/sync.dart`: HELLO/INV/REQ/MSG flow.
7. `engine/rate_limiter.dart`.
8. `data/message_store.dart`: interface + `InMemoryMessageStore` (drift implementation comes later in this phase or Phase 4).
9. `transport/mesh_transport.dart` abstract interface.
10. `transport/sim/`: `SimWorld`, `SimTransport` (positions, range, loss, deterministic seed).
11. `domain/`: SOS state derivation, hazard clustering and confirmation, shelter supersession.

**Tests (all run with `dart test` / `flutter test`, no devices)**
- Canonical JSON determinism
- Signature valid / tampered / wrong key
- Dedup, TTL decrement, no-forward at 0, TTL clamp
- Priority ordering in the outbox
- Rate limit per origin
- INV/REQ gives full convergence between two nodes with disjoint histories
- **Line topology A-B-C-D-E: SOS from A reaches E**
- **Partition healing: two islands, a mobile node bridges them, both converge**
- SOS lifecycle transitions and forbidden ones (fake ACK rejected)
- Hazard clustering + 2-origin confirmation

**Acceptance:** all tests green; a CLI or test prints a propagation trace for the 5-node line.

---

## Phase 3: Real transport (Nearby Connections)

**Tasks**
- `NearbyTransport implements MeshTransport` using the plugin: advertise + discover with one `serviceId`, the connection tie-break rule, auto-accept, degree cap of 4, backoff reconnect, one-frame-per-payload, frame size guard.
- Runtime permission flow screen (Android 12+ and legacy), plus location services enabled check.
- Detect missing Google Play Services and show an unsupported-device message.
- Wire `MeshController` → `MeshEngine` → `NearbyTransport`.
- Debug screen: peer list with connection state, last frame time, drop counts by reason.

**HUMAN CHECKPOINT 3a (2 phones):** both phones see each other, connect once (no duplicate or flapping connections), and exchange a test message. Human pastes `adb logcat` output on any failure.

**HUMAN CHECKPOINT 3b (3 phones):** place phones in a line, A and C out of range of each other. A sends a test message, C must receive it via B.

**Acceptance:** 3b passes at least 3 times in a row.

---

## Phase 4: Features and UI

**Tasks**
- Home: mesh status card (peers, messages relayed), SOS button (hold 2s with haptic and progress ring), quick actions.
- SOS flow: category, number of people, note; auto-attach GPS; show live status (ACTIVE / ACKNOWLEDGED / RESOLVED) derived from ACKs; "I'm safe" cancel.
- Hazard report: preset tiles, severity, note; confirm-hazard action on others' pins.
- Feed: priority + distance sorted, trust badges, relative age, hops count ("relayed through 2 phones").
- **Radar view** (mandatory): CustomPainter plotting items by distance and bearing.
- Map view with `flutter_map` and bundled offline tiles if time allows; otherwise Radar only.
- Shelters list with status, distance, services, Verified badge.
- Local notifications for nearby SOS and new verified shelters.
- Drift-backed `MessageStore` with the schema from `ARCHITECTURE.md` and `ExpiryService`.

**Acceptance:** full flow works on 3 phones: hazard created on A appears on C with hop count 2; SOS from A shows ACKNOWLEDGED after a responder ACK.

---

## Phase 5: Trust and responder mode

**Tasks**
- `TrustService` with `trusted_responders.json`; tier assignment.
- Responder mode: PIN-gated unlock of a demo responder private key; screens to create/update signed shelters (with `seq`) and ACK SOS.
- Debug "Inject forged shelter" tool (see `SECURITY_TRUST.md` section 7).
- UI never labels non-Verified shelters as safe.

**Acceptance:** forged shelter never shows Verified; genuine one does, even when relayed through untrusting intermediaries.

---

## Phase 6: Polish, demo, README

**Tasks**
- **Simulator screen:** 20 virtual nodes, animated propagation, "trigger SOS at node N", failure and movement toggles.
- Battery-saver toggle (duty cycling and rebroadcast interval).
- Onboarding (3 screens max) explaining permissions and the offline mesh.
- App icon, name, splash.
- `README.md`: problem, architecture diagram, how to run, how to test, limitations (copy from `ARCHITECTURE.md` section 16).
- Record a fallback demo video in case live radios misbehave at the venue.

---

## Scope cuts, in this order

1. Offline map tiles (keep Radar)
2. Foreground service (never started anyway)
3. Hazard confirmation extensions and clustering polish
4. Battery saver
5. Simulator animation polish (keep the headless tests)
6. Notifications

**Never cut:** multi-hop relay, SOS lifecycle with ACK, signed shelters, Radar view, simulator test for the 5-node line.

## Demo script (5 minutes)

1. **Problem (30s):** after floods and cyclones, towers fail exactly when people need them.
2. **Airplane mode on, Bluetooth and Wi-Fi on** (show it). Three phones in a line.
3. Phone A: hold SOS. Phone C (out of A's range) receives it, with "relayed through 1 phone".
4. Phone B: report a flooded road. It appears on both others, and a second confirmation turns it CONFIRMED.
5. Responder phone: publish a signed shelter. It appears with the green badge on all phones.
6. **Security moment:** inject the forged shelter, show it rejected from Verified.
7. Responder ACKs the SOS. Phone A shows "Help acknowledged".
8. **Simulator:** scale to 20 nodes, show a partition healing via a moving "data mule" phone.
9. Honest limitations and the roadmap (LoRa bridges, spray-and-wait routing).

## Risk register

| Risk | Mitigation |
|---|---|
| Nearby flakiness at the venue (RF noise) | Simulator + recorded video fallback; test early; keep phones close for the live demo |
| Plugin API differs from assumptions | Agent reads plugin README and example before coding; keep adapter thin |
| Permissions on Android 12+/13+ | Dedicated skill file; test on the newest phone first |
| Phones without Google Play Services | Detect and message; use GMS phones for the demo |
| Duplicate/flapping connections | Deterministic tie-break rule (section 5.2) |
| Agent claims radio code works without testing | Human checkpoints are mandatory; agent must not proceed past them without human confirmation |
| Time overrun on UI | Radar + lists first; map last |

## Definition of done

- Tests green for engine, domain, crypto, simulator
- 3-phone line demo works repeatedly
- Responder-signed shelter shows Verified; forged does not
- SOS lifecycle works end to end
- README and limitations written
- Demo video recorded
