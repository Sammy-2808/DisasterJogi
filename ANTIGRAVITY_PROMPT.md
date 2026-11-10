# Antigravity Master Prompt: MeshRescue

Paste everything below the line into Antigravity (Planning mode). Put the `docs/` folder and `.agent/skills/` folder in the workspace root first.

---

You are building **MeshRescue**, an offline peer-to-peer disaster communication app, for a hackathon. Phones with no internet or cellular signal form a mesh and relay SOS alerts, hazard reports and responder-verified shelter listings hop by hop.

## Step 0: Read before anything else
Read these files fully, in order:
1. `docs/ARCHITECTURE.md`
2. `docs/PROTOCOL.md`
3. `docs/SECURITY_TRUST.md`
4. `docs/IMPLEMENTATION_PLAN.md`
5. Every `SKILL.md` under `.agent/skills/`

These are the source of truth. If you want to deviate from them, say so explicitly and wait for my approval.

## Step 1: Plan, then stop
Produce an implementation plan and a task list for **Phase 1 and Phase 2 only**, matching `IMPLEMENTATION_PLAN.md`. Do not write application code until I approve the plan.

## Fixed decisions (do not revisit)
- Flutter, **Android only**.
- Transport: `nearby_connections` plugin with `Strategy.P2P_CLUSTER`, behind an abstract `MeshTransport`.
- Routing: store-and-forward gossip with TTL, dedup by message id, and INV/REQ anti-entropy sync.
- Mesh engine is **pure Dart** (no Flutter imports), testable without devices and runnable in a simulator.
- Storage: drift (SQLite). Crypto: Ed25519 via the `cryptography` package. State: Riverpod.
- Shelters count as Verified only if signed by a key in `assets/trusted_responders.json`.
- Expiry uses local `received_at`, never the sender's `ts`.

## Working rules
1. **Order matters.** Build the engine and simulator (Phase 2) and prove them with tests before touching the real radio (Phase 3).
2. **Verify, don't assume, package APIs.** Before using `nearby_connections`, `drift`, `cryptography`, `flutter_map` or `geolocator`, read the package's current README, changelog and example from pub.dev, and note the version you chose. Never invent method names.
3. **You cannot test radios.** Bluetooth/Wi-Fi/Nearby behaviour cannot be validated in an emulator or the Antigravity browser. At every **HUMAN CHECKPOINT** in the plan, stop, tell me exactly what to test on which phones, and wait for my results (including `adb logcat` output). Never claim radio functionality works without my confirmation.
4. **Tests are part of every task.** Each engine/domain feature ships with unit tests. Run `flutter analyze` and the test suite before reporting a task complete, and show the results.
5. **Small, reviewable steps.** After each phase, give me a short walkthrough: what was built, how to run it, what is untested, what is next.
6. **No scope creep.** Follow the scope-cut order in the plan. If you think something extra is valuable, propose it and wait.
7. **No secrets.** Demo responder private keys are clearly labelled DEMO. Never present them as production keys.
8. **Safety-critical UI.** Never label anything "safe" or "verified" unless it is in the Verified Responder tier. SOS must be hard to trigger accidentally (hold 2s) and easy for a stressed person to use (large targets, high contrast, minimal text).
9. **Ask when blocked.** If a requirement is ambiguous or a package behaves differently than the docs assume, stop and ask with a concrete recommendation.
10. **Keep docs in sync.** If implementation forces a protocol or schema change, update the relevant file in `docs/` in the same change.

## Skills
Use these project skills when relevant:
- `flutter-nearby-mesh`: permissions, advertising/discovery, connection rules
- `mesh-protocol`: envelope, validation, forwarding, tests
- `signed-records`: signing, canonical JSON, trust tiers
- `android-device-testing`: adb workflow and the human-checkpoint protocol

If a skill conflicts with the docs, tell me before proceeding.

## Definition of done
- Engine, domain, crypto and simulator tests pass; the 5-node line test delivers A's SOS to E.
- Three physical phones in a line relay messages A→B→C repeatedly.
- SOS lifecycle works end to end (ACTIVE → ACKNOWLEDGED → RESOLVED).
- Responder-signed shelter shows Verified; a forged one does not.
- Radar view works with no map tiles.
- README states limitations honestly.

## First response I expect
1. A short confirmation that you read all docs and skills, plus any questions or risks you see.
2. The Phase 1-2 plan and task list.
3. The exact Flutter/Dart/package versions you intend to use, each verified from pub.dev.

Then wait for my approval.
