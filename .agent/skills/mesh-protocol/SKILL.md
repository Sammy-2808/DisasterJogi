---
name: mesh-protocol
description: Use when working on the mesh engine, message envelope, validation, forwarding, outbox, sync (HELLO/INV/REQ/MSG), rate limiting, expiry or the simulator.
---

# Mesh protocol rules

Source of truth: `docs/PROTOCOL.md`. Update that file in the same change if the protocol changes.

## Invariants
- The engine is **pure Dart**: no `package:flutter` imports. Dependencies are injected: `MeshTransport`, `MessageStore`, `Signer`, `Clock`.
- Receive pipeline order: decode, validate, dedup, verify signature, store, apply domain state, forward. Every drop records a reason code.
- `ttl` and `hops` are mutable and NOT signed. Everything else is signed.
- Clamp `ttl` to <= 10. Do not forward when `ttl - 1 <= 0`.
- Never forward a message back to the peer it came from; never send the same message to the same peer twice.
- Outbox priority: SOS > ACK > SHELTER > HAZARD, newest first within a class.
- Expiry uses local `received_at`. Never trust or reject on the sender's `ts`.
- Locally originated, un-ACKed SOS rebroadcasts on a timer (30s, 60s in battery saver).
- Sync on connect: HELLO, INV, REQ, MSG. Re-send INV every 60s while connected.
- Limits: frame 4096 B, INV 200 items, REQ 50 ids, 2000 stored messages, 10 msgs/min per origin.

## Testing requirements
Every change ships with unit tests, using the simulator (`SimWorld`, `SimTransport`) with fixed random seeds. Mandatory scenarios: dedup, TTL stop, priority order, rate limit, INV/REQ convergence, 5-node line A to E delivery, partition healing via a moving node, forbidden SOS transitions.

## Style
- Pure functions for validation and domain derivations (SOS state, hazard clustering, shelter supersession).
- Reason codes are an enum: `BAD_FRAME, BAD_SCHEMA, BAD_PAYLOAD, BAD_COORDS, DUPLICATE, BAD_ORIGIN, BAD_SIG, RATE_LIMITED, UNAUTHORIZED`.
- Do not add protocol features not in `docs/PROTOCOL.md` without asking.
