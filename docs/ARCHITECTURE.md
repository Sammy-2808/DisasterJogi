# MeshRescue: Architecture

An offline, infrastructure-free mesh network for disaster communication. Android phones discover each other over Bluetooth/Wi-Fi, form a local mesh, and relay SOS alerts, hazard reports and verified shelter listings hop-by-hop with **no internet and no servers**.

> Verify all third-party package APIs against the current pub.dev documentation before coding. Nothing in this file should be treated as a guaranteed API signature.

---

## 1. Design goals (in priority order)

1. **Works with zero infrastructure.** No cell, no Wi-Fi router, no cloud, no accounts, no login.
2. **Multi-hop delivery.** A message from phone A must reach phone C even when A and C are out of radio range, relayed through B.
3. **Store-and-forward.** Phones move. A message must survive until a new neighbour appears (delay-tolerant networking).
4. **Trust without internet.** A fake "safe shelter" can get people killed. Shelters must be cryptographically verifiable offline.
5. **Graceful under abuse and scale.** Rate limits, TTL caps, bounded storage, bounded connection degree.
6. **Battery-aware.** Phones may need to last days.
7. **Demoable.** A built-in simulator shows multi-hop behaviour even with only 2-3 physical phones.

## 2. System context

```
 Stranded civilian ──┐                          ┌── First responder (signed authority)
  (SOS, hazards)     │                          │   (shelters, SOS ACKs)
                     ▼                          ▼
              ┌────────────────────────────────────────┐
              │   Phone mesh (Nearby Connections)      │
              │   A ◄──► B ◄──► C ◄──► D               │
              │   gossip: store-and-forward, TTL       │
              └────────────────────────────────────────┘
                 no internet / no servers / no accounts
```

Each phone is simultaneously a **client** (user UI), a **node** (stores messages) and a **relay** (forwards messages).

## 3. Layered architecture

```
┌───────────────────────────────────────────────────────────┐
│ UI layer (Flutter, Riverpod)                              │
│ Home · Feed · Map/Radar · SOS · Hazard · Shelters ·       │
│ Responder panel · Simulator view                          │
├───────────────────────────────────────────────────────────┤
│ Application services                                      │
│ MeshController · MessageRepository · TrustService ·       │
│ LocationService · ExpiryService · NotificationService     │
├───────────────────────────────────────────────────────────┤
│ MESH ENGINE (pure Dart, no Flutter imports)               │
│ pipeline: decode→validate→dedup→verify→store→apply→fwd    │
│ outbox scheduler · anti-entropy sync · rate limiter       │
├───────────────────────────────────────────────────────────┤
│ MeshTransport (abstract interface)                        │
│ ┌──────────────────┐   ┌──────────────────────────────┐  │
│ │ NearbyTransport  │   │ SimTransport (virtual radios)│  │
│ └──────────────────┘   └──────────────────────────────┘  │
├───────────────────────────────────────────────────────────┤
│ Data: drift/SQLite · crypto (Ed25519) · geolocator        │
└───────────────────────────────────────────────────────────┘
```

**Key rule:** the Mesh Engine is pure Dart and depends only on interfaces (`MeshTransport`, `Clock`, `MessageStore`, `Signer`). This lets the identical engine run on real phones, in unit tests, and in the simulator with 20 virtual nodes.

## 4. Components

| Component | Responsibility |
|---|---|
| `MeshTransport` | Abstract: start/stop, peer events, `send(peerId, bytes)`, incoming byte stream |
| `NearbyTransport` | Nearby Connections implementation (advertise + discover, connect, framing) |
| `SimTransport` | In-memory virtual radios with position, range and loss probability |
| `MeshEngine` | Core protocol logic: dedup, TTL forwarding, priority outbox, sync |
| `MessageStore` | Persistence interface; `DriftMessageStore` and `InMemoryMessageStore` |
| `TrustService` | Signature verification, trust tier assignment, responder key list |
| `Signer` | Device keypair management, sign/verify |
| `LocationService` | GPS fix (offline), last-known position cache |
| `ExpiryService` | Periodic purge based on local `received_at` |
| `MeshController` | Riverpod-facing facade combining the above |

## 5. Transport layer (Nearby Connections)

**Why Nearby Connections:** it abstracts BLE discovery plus Bluetooth/Wi-Fi upgrade, needs no router, and the `nearby_connections` Flutter plugin exposes it. **Strategy: `P2P_CLUSTER`** (M-to-N topology), the right choice for a mesh.

**Known constraints (design around them):**
- Android only; requires **Google Play Services**. Devices without it will not work.
- Bytes payloads are limited to about 32 KB. Keep every frame under 4 KB.
- iOS does not interoperate. Out of scope.

### 5.1 Roles
Every node advertises **and** discovers concurrently, using one shared `serviceId` constant (e.g. `com.meshrescue.mesh.v1`). The advertised endpoint name encodes the short device ID.

### 5.2 Connection collision avoidance
If both sides see each other and both call `requestConnection`, Nearby produces conflicting connection attempts. Use a **deterministic tie-break**: only the node with the lexicographically **smaller** device ID initiates; the other waits and auto-accepts.

### 5.3 Degree cap
Cap simultaneous connections (default **4**). Prefer peers that bring new coverage: if full, ignore new discoveries until a link drops. This bounds radio load and prevents dense clusters from melting.

### 5.4 Framing
Each payload is one **frame**: 1 byte frame type + UTF-8 JSON body (see `PROTOCOL.md`). One frame per Nearby payload, no streaming.

### 5.5 Reconnect and backoff
On disconnect: mark the peer lost, retry on rediscovery with exponential backoff (2s → 4s → 8s, cap 60s) per endpoint. Never block the UI on transport errors.

### 5.6 Duty cycling
Continuous advertising and discovery drains the battery. Policy:
- **Seeking mode** (0-1 peers): continuous.
- **Connected mode** (2+ peers): discovery paused in a 20s-on / 40s-off cycle, advertising continues.
- **Battery saver** (user toggle or battery < 20%): longer off windows, SOS rebroadcast every 60s instead of 30s.

## 6. Mesh engine

### 6.1 Receive pipeline

```
bytes ─► decode ─► validate ─► dedup ─► verify ─► store ─► apply ─► forward
          │          │          │         │         │        │         │
        drop bad   drop bad   drop if   drop bad  persist  update    enqueue to
        frame      fields/    id seen   signature  w/ recv  domain    outbox for
                   size/TTL                        time     state     all peers
                                                                       except sender
```

Every step can drop the message. Drops are logged with a reason code (used by the debug screen and tests).

### 6.2 Send pipeline
Locally created messages are signed, stored, and enqueued in the outbox exactly like received ones (origin = self).

### 6.3 Outbox scheduler
- Priority order: `SOS` > `ACK` > `SHELTER` > `HAZARD`.
- One in-flight frame per peer at a time, with a small send delay to avoid radio saturation.
- Per-(message, peer) delivery tracking so the same message is never sent twice to the same peer.
- **SOS persistence:** locally originated, unACKed SOS is re-broadcast every 30s (60s in battery saver) until ACKed, cancelled or expired.

### 6.4 Anti-entropy sync (catch-up for new neighbours)
When a link comes up, nodes exchange state instead of blindly dumping everything:
1. Both send `HELLO` (protocol version, device ID, capabilities).
2. Both send `INV`: list of `{id, type, ts}` for non-expired messages (capped to most recent 200, SOS first).
3. Each side replies `REQ` with the IDs it lacks.
4. The holder sends the requested messages as `MSG` frames.

This gives eventual consistency across any set of nodes that ever touch each other, including nodes that were never simultaneously connected (a "data mule" phone carries messages between islands).

### 6.5 Rate limiting and abuse control
- Per-origin token bucket (default 10 msgs/min). Excess is dropped.
- Max stored messages (default 2,000). On overflow evict expired, then lowest-priority oldest. SOS and verified shelters are evicted last.
- TTL hard cap of 10 regardless of what the envelope claims.

## 7. Data model (SQLite via drift)

```sql
CREATE TABLE messages (
  id           TEXT PRIMARY KEY,      -- uuid v4
  type         TEXT NOT NULL,         -- SOS | HAZARD | SHELTER | ACK
  origin       TEXT NOT NULL,         -- device id (public key fingerprint)
  origin_pub   TEXT NOT NULL,         -- base64 Ed25519 public key
  ts           INTEGER NOT NULL,      -- sender clock, epoch seconds (UNTRUSTED)
  received_at  INTEGER NOT NULL,      -- local clock, used for expiry
  lat          REAL, lng REAL,
  geohash      TEXT,                  -- precision 7
  ttl          INTEGER NOT NULL,      -- remaining hops when received
  hops         INTEGER NOT NULL DEFAULT 0,
  ref_id       TEXT,                  -- ACK -> SOS id; confirmations -> hazard id
  payload      TEXT NOT NULL,         -- canonical JSON
  sig          TEXT NOT NULL,         -- base64 signature
  trust        TEXT NOT NULL,         -- VERIFIED_RESPONDER | SIGNED_PEER | UNVERIFIED
  is_local     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_messages_type_recv ON messages(type, received_at);
CREATE INDEX idx_messages_geohash   ON messages(geohash);
CREATE INDEX idx_messages_ref       ON messages(ref_id);

CREATE TABLE outbox (
  message_id TEXT NOT NULL,
  peer_id    TEXT NOT NULL,
  sent_at    INTEGER,
  PRIMARY KEY (message_id, peer_id)
);

CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
```

**Clock warning:** phones have unsynchronised clocks offline. `ts` is informational only. **All expiry logic uses `received_at`.**

## 8. Domain behaviour

### 8.1 SOS lifecycle

```
 ACTIVE ──(responder ACK: RECEIVED)──► ACKNOWLEDGED
   │                                       │
   │                          (ACK: DISPATCHED)
   │                                       ▼
   ├──(origin cancels: "I'm safe")──►  RESOLVED ◄──(ACK: RESOLVED)
   └──(24h since received_at)────────► EXPIRED
```

State is **derived** from SOS + ACK messages (`ref_id`), not stored separately. ACKs from a verified responder, or a cancel signed by the SOS origin key, are the only transitions accepted.

### 8.2 Hazards
- Kinds: `flood`, `fire`, `collapse`, `road_blocked`, `landslide`, `other`. Severity 1-5.
- **Clustering:** same `kind` + same geohash-7 cell (about 150 m) merge into one map pin.
- **Confirmation:** a hazard is `CONFIRMED` once 2+ distinct origins have reported or confirmed it. Single reports show as `REPORTED`.
- Expiry: 12h by default; each confirmation extends it by 6h; a responder-signed hazard lasts 48h.

### 8.3 Shelters
- Must carry a signature from a key in the trusted responder list to display as **Verified**. Otherwise they are shown as "Unverified (community reported)" with a warning, or hidden behind a toggle.
- Payload: name, capacity, services (water, medical, food), contact note, `status` (OPEN / FULL / CLOSED). Newer signed `status` updates supersede older ones by `(origin, shelter_key, seq)`.

## 9. Location and map

- GPS works offline (satellite only). Cache the last fix.
- **Primary view:** `flutter_map` with **bundled offline tiles** (an MBTiles/raster region prepared in advance for the demo area).
- **Fallback view (always available): Radar.** A `CustomPainter` showing the user at centre, with every message plotted by distance and bearing, colour-coded by type. This needs no tiles and is the safe demo path.
- Distance via haversine; bearing via initial great-circle bearing.

## 10. UI

| Screen | Content |
|---|---|
| Home | Mesh status (peers, relayed count), huge SOS button (hold 2s), quick actions |
| Feed | Priority-sorted, distance-aware list with trust badges and age |
| Map / Radar | Pins for SOS, hazards, shelters; tap for details |
| Report Hazard | One-tap presets, severity, optional note |
| Shelters | Verified list with status, distance, services |
| Responder panel | Unlock via key file or PIN; create signed shelters; ACK SOS |
| Debug / Sim | Peer table, drop reasons, simulator toggle |

Riverpod providers: `meshStatusProvider`, `peersProvider`, `messagesProvider(type)`, `sosStateProvider`, `locationProvider`.

Accessibility: large touch targets, high contrast, minimal text, no dependence on colour alone (icons plus labels). Users will be stressed and possibly injured.

## 11. Simulator

`SimTransport` plus a `SimWorld`:
- N virtual nodes with `(x, y)` positions and radio range R. Links exist only within R.
- Each node runs a real `MeshEngine` instance with an `InMemoryMessageStore`.
- Configurable packet-loss probability, node movement (random walk) and node failure.
- A visualisation (`CustomPainter`) animates message propagation hop by hop.
- Used for: automated tests (deterministic seeds), and live demo ("here is a 20-phone network").

## 12. Background operation

Android kills background work. For real use, run the mesh inside a **foreground service** with a persistent notification (stretch goal: `flutter_foreground_task` or equivalent). For the hackathon demo the app is kept in the foreground with the screen on; do not spend core time on this.

## 13. Failure modes

| Failure | Behaviour |
|---|---|
| No peers nearby | Messages stored; SOS keeps rebroadcasting; UI shows "Searching…" |
| Peer drops mid-send | Frame treated as undelivered; retried on reconnect via INV/REQ |
| Malformed/oversized frame | Dropped with reason code; peer penalised after repeated offences |
| Invalid signature | Dropped; never displayed |
| Flood from one origin | Token bucket drops excess |
| GPS unavailable | Use last known fix; mark `stale`; allow manual location note |
| Storage full | Evict expired, then low-priority oldest |
| Permissions denied | Blocking onboarding screen explaining what is needed and why |
| Device lacks Google Play Services | Detect at startup, show unsupported-device message |

## 14. Project structure

```
lib/
  main.dart
  app/                    # routing, theme, providers wiring
  engine/                 # PURE DART (no flutter imports)
    mesh_engine.dart
    outbox.dart
    sync.dart
    rate_limiter.dart
    models/               # Envelope, Frame, enums
  transport/
    mesh_transport.dart   # abstract
    nearby_transport.dart
    sim/                  # SimTransport, SimWorld
  data/
    db.dart               # drift
    message_store.dart
  crypto/
    signer.dart
    trust_service.dart
  domain/
    sos_state.dart
    hazard_cluster.dart
    shelter_logic.dart
  services/               # location, expiry, notifications, battery
  ui/
    home/ feed/ map/ radar/ sos/ hazard/ shelters/ responder/ debug/
test/
  engine/ domain/ crypto/ sim/
assets/
  trusted_responders.json
  tiles/                  # optional offline region
docs/
.agent/skills/
```

## 15. Tech stack

| Concern | Choice | Notes |
|---|---|---|
| Framework | Flutter, Android only | Verify current stable SDK |
| Transport | `nearby_connections` | Verify API against pub.dev |
| State | `flutter_riverpod` | |
| DB | `drift` (+ `sqlite3_flutter_libs`) | |
| Crypto | `cryptography` (Ed25519) | |
| Location | `geolocator` | |
| Map | `flutter_map` + offline tiles | Radar fallback mandatory |
| Geohash | `dart_geohash` or ~40-line own impl | |
| IDs | `uuid` | |
| Tests | `flutter_test`, `test` | Engine tests run with plain `dart test` |

## 16. Honest limitations (put these in the pitch; judges respect it)

- Android + Google Play Services only. iOS needs a separate transport.
- Radio range is limited (roughly 30-100 m indoors, further outdoors). Mesh coverage depends on phone density.
- Gossip flooding does not scale to thousands of nodes without smarter routing (e.g. spray-and-wait, geographic routing).
- Broadcast SOS reveals location to every node in the mesh by design. No content encryption in v1.
- Trust model relies on pre-provisioned responder keys; no revocation list in v1.
- Phone battery and background restrictions limit real-world uptime without a foreground service.

## 17. Future work

Foreground service, LoRa/ESP32 long-range bridge nodes, spray-and-wait routing, signed key revocation, encrypted direct messages, satellite/internet gateway nodes that sync the mesh to a cloud dashboard when connectivity returns.
