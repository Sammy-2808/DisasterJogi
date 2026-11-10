# MeshRescue: Wire Protocol v1

Defines frames, message envelopes, validation, forwarding and sync. This is the source of truth for the mesh engine and its tests.

## 1. Frame layer

Each Nearby payload carries exactly one frame:

```
[ 1 byte: frame type ][ UTF-8 JSON body ]
```

| Type byte | Name | Body |
|---|---|---|
| `0x01` | HELLO | `{ "v":1, "deviceId":"...", "pub":"base64", "caps":["sos","hazard","shelter"] }` |
| `0x02` | INV | `{ "items":[ {"id":"...","type":"SOS","ts":1731200000}, ... ] }` (max 50 items per frame, up to 200 items total across up to 4 frames per sync round so every frame stays < 4096 B) |
| `0x03` | REQ | `{ "ids":["...","..."] }` (max 50 ids) |
| `0x04` | MSG | one **Envelope** (see below) |
| `0x05` | PING | `{}` (optional liveness check) |

Max frame size: **4096 bytes**. Larger frames are dropped.
Unknown frame types are ignored (forward compatibility). A HELLO with an unsupported `v` closes the link.

## 2. Envelope

```json
{
  "id": "3f2b8c1e-....",
  "type": "SOS",
  "origin": "a1b2c3d4",
  "originPub": "base64-ed25519-public-key",
  "ts": 1731200000,
  "lat": 21.4669,
  "lng": 83.9812,
  "refId": null,
  "payload": { },
  "sig": "base64",
  "ttl": 10,
  "hops": 0
}
```

| Field | Notes |
|---|---|
| `id` | UUID v4, globally unique, dedup key |
| `type` | `SOS`, `HAZARD`, `SHELTER`, `ACK` |
| `origin` | Short ID = first 8 hex chars of SHA-256(originPub) |
| `originPub` | Ed25519 public key (32 bytes, base64). Lets any node verify offline |
| `ts` | Sender clock, epoch seconds. **Untrusted, informational only** |
| `lat`, `lng` | WGS84, 5 decimal places max. Nullable for ACK |
| `refId` | Target message id (ACK→SOS, confirmation→HAZARD) |
| `payload` | Type-specific JSON object (section 3) |
| `sig` | Ed25519 signature over the **signed bytes** (section 4) |
| `ttl` | **Mutable.** Remaining hops. Not signed |
| `hops` | **Mutable.** Hops travelled so far. Not signed |

## 3. Payload schemas

**SOS**
```json
{ "category": "trapped|medical|fire|flood|lost|other",
  "people": 3, "note": "2nd floor, stairs blocked", "contact": "optional free text" }
```
Default TTL 10. Rebroadcast by origin every 30s until ACKed, cancelled, or 24h.

**HAZARD**
```json
{ "kind": "flood|fire|collapse|road_blocked|landslide|other",
  "severity": 3, "note": "water waist-deep" }
```
Default TTL 6. A confirmation is a new HAZARD with `refId` = original hazard id and the same `kind`.

**SHELTER** (only trusted when signed by a responder key)
```json
{ "key": "school-ward-12", "name": "Govt High School",
  "status": "OPEN|FULL|CLOSED", "capacity": 200,
  "services": ["water","medical","food"], "note": "Gate 2", "seq": 4 }
```
Default TTL 10. For the same `(origin, key)`, the highest `seq` wins.

**ACK** (SOS lifecycle)
```json
{ "status": "RECEIVED|DISPATCHED|RESOLVED|CANCELLED", "note": "Team 3 en route" }
```
`refId` = SOS id. Accepted only if signed by a trusted responder, **or** (`CANCELLED`/`RESOLVED`) signed by the same key as the referenced SOS origin.

## 4. Canonical signing

To avoid cross-device JSON differences, signed bytes are produced as:

```
signedMap = { id, type, origin, originPub, ts, lat, lng, refId, payload }   // NOT ttl, hops, sig
signedBytes = utf8( canonicalJson(signedMap) )
```

`canonicalJson`: object keys sorted lexicographically at every depth, no whitespace, numbers in shortest form, `null` kept explicitly, strings UTF-8 with standard JSON escaping. Implement once in `engine/canonical_json.dart` and test it with fixed vectors.

## 5. Validation (receive side)

Apply in order. First failure drops the message and records a reason.

| # | Check | Reason code |
|---|---|---|
| 1 | Frame <= 4096 bytes, valid JSON | `BAD_FRAME` |
| 2 | Required fields present, types correct | `BAD_SCHEMA` |
| 3 | `type` known, payload matches schema | `BAD_PAYLOAD` |
| 4 | `lat` in [-90,90], `lng` in [-180,180] | `BAD_COORDS` |
| 5 | `ttl` clamped to [0,10] | (clamp, no drop) |
| 6 | `id` not already stored | `DUPLICATE` |
| 7 | `origin` equals first 8 hex of SHA-256(`originPub`) | `BAD_ORIGIN` |
| 8 | Signature valid over signed bytes | `BAD_SIG` |
| 9 | Origin under rate limit | `RATE_LIMITED` |
| 10 | Type-specific authority (SHELTER needs trusted key for Verified; ACK rules above) | `UNAUTHORIZED` (ACK) or downgrade trust tier (SHELTER) |

Do **not** reject on `ts` skew. Store `received_at = localNow`.

## 6. Trust tiers

| Tier | Meaning | UI |
|---|---|---|
| `VERIFIED_RESPONDER` | Valid signature and `originPub` in `trusted_responders.json` | Green badge, shown first |
| `SIGNED_PEER` | Valid signature from any device key | Normal |
| `UNVERIFIED` | n/a for stored messages (invalid sigs are dropped); used for shelters that fail the authority check | Warning label, hidden by default |

## 7. Forwarding policy

After a message is accepted and stored:
1. If `ttl - 1 <= 0`: do not forward (still stored and displayed).
2. Set `ttl = ttl - 1`, `hops = hops + 1`.
3. Enqueue for every connected peer **except** the peer it arrived from, skipping peers already known to hold it (per INV/outbox tracking).
4. Outbox priority: `SOS(0) > ACK(1) > SHELTER(2) > HAZARD(3)`; within a class, newest first.

Locally originated messages start with `hops = 0` and the type's default TTL.

## 8. Sync sequence

```
 A                                B
 │── HELLO ───────────────────────►│
 │◄────────────────────── HELLO ───│
 │── INV [ids A has] ─────────────►│
 │◄───────────── INV [ids B has] ──│
 │── REQ [ids A lacks] ───────────►│
 │◄──────────── REQ [ids B lacks] ─│
 │── MSG, MSG, MSG ───────────────►│
 │◄─────────────── MSG, MSG ───────│
```

INV is sent on connect and again every 60s while connected (cheap, catches anything missed). Messages received via sync are forwarded onward like any other (so A→B→C propagation continues).

## 9. Multi-hop example

```
 A ◄─► B ◄─► C         A and C out of range
 
 t0  A creates SOS (ttl 10, hops 0)
 t1  A → B   MSG (ttl 10, hops 0)    B stores, sets ttl 9 hops 1
 t2  B → C   MSG (ttl 9,  hops 1)    C stores, displays SOS from A
 t3  C → B   not sent: B already has id (INV shows it)
 t4  Responder near C creates ACK(refId=SOS) → C → B → A
     A sees "Help acknowledged"
```

## 10. Expiry (local `received_at`)

| Type | Default lifetime |
|---|---|
| SOS | 24h, or until ACK status RESOLVED/CANCELLED |
| HAZARD | 12h, +6h per distinct confirmation, 48h if responder-signed |
| SHELTER | 72h, refreshed by a higher `seq` from the same `(origin,key)`; `CLOSED` hides it |
| ACK | Lives as long as its SOS |

## 11. Limits summary

| Limit | Default |
|---|---|
| Frame size | 4096 B |
| TTL cap | 10 |
| INV items | 200 total (50 per frame) |
| REQ ids | 50 |
| Messages stored | 2000 |
| Rate limit per origin | 10 / min |
| Peer connections | 4 |
| SOS rebroadcast | 30s (60s battery saver) |

## 12. Test vectors required

The engine MUST ship with tests for: canonical JSON determinism, signature verify/fail, dedup, TTL decrement and stop at 0, priority ordering, rate limiting, INV/REQ completeness, SOS lifecycle transitions, hazard clustering and confirmation, shelter seq supersession, and a 5-node line topology (A-B-C-D-E) delivering A's SOS to E in the simulator.
