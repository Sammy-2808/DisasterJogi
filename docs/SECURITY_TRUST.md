# MeshRescue: Security and Trust Model

## 1. Why this matters
In a disaster, wrong information kills: a fake shelter sends people to a collapsed building; a flood of fake SOS buries real ones. The mesh has no server to police it, so trust must be built into the data itself.

## 2. Assets and threats

| Threat | Example | Mitigation |
|---|---|---|
| Fake shelter | Malicious phone broadcasts "Safe shelter at X" | Shelters only shown as Verified if signed by a trusted responder key |
| Message tampering | A relay edits coordinates in transit | Every message signed over its content; relays cannot alter signed fields |
| Spam / flooding | One device sends thousands of SOS | Per-origin token bucket, TTL cap, bounded storage |
| Fake ACK ("rescue is coming") | Hostile actor marks a real SOS as resolved | ACK accepted only from trusted responder or the SOS origin key |
| Replay | Old SOS re-injected to cause confusion | Dedup by id, expiry by local `received_at`, SOS cancellable by origin |
| Identity forgery | Claiming someone else's origin | `origin` must equal hash of `originPub`; signature must verify |
| Location privacy | SOS location visible to all nodes | Accepted by design for v1 (life safety > privacy). Documented in UI |
| Malformed input crashes | Fuzzed frames | Strict validation pipeline, size caps, reason-coded drops |
| Sybil hazard confirmation | One person fakes "2 confirmations" with many keys | Known limitation: confirmations count distinct keys, not people. Responder-signed hazards outrank crowd ones |

## 3. Keys

**Device key (every phone):**
- Ed25519 keypair generated on first launch, stored in Android Keystore-backed secure storage (`flutter_secure_storage`).
- `originPub` is included in every message so any node can verify offline.
- `origin` = first 8 hex chars of SHA-256(originPub).

**Responder keys (authorities):**
- A small set of Ed25519 public keys shipped in `assets/trusted_responders.json`:
  ```json
  { "version": 1, "responders": [
      { "name": "District Control Room", "pub": "base64..." } ] }
  ```
- Matching private keys are held by responders only, loaded in **Responder mode** via an encrypted key file plus PIN (or, for the hackathon demo, a bundled demo key unlocked with a PIN, clearly labelled DEMO).
- Demo keys must be regenerated before any real use. Never commit real private keys.

## 4. Trust tiers (UI contract)

| Tier | Badge | Behaviour |
|---|---|---|
| Verified Responder | Green shield + name | Sorted first; shelters shown as "Verified safe" |
| Signed Peer | Neutral | Normal display |
| Unverified | Amber warning | Shelter lists hide these by default behind "Show community-reported" |

The UI must never use the words "safe" or "verified" for anything outside the Verified Responder tier.

## 5. What is NOT protected in v1 (state this openly)

- **No confidentiality.** All content is readable by any node. Do not put sensitive personal data in notes.
- **No revocation.** A leaked responder key stays trusted until the app is updated. Future: signed revocation lists propagated over the mesh.
- **No protection against a compromised responder device.**
- **Key distribution is out-of-band.** The trust list ships with the app. In production, a CA-style chain (root key signs responder certificates) would allow onboarding responders without app updates.
- **Radio-layer attacks** (jamming, Bluetooth sniffing) are out of scope.
- **Sybil resistance is weak** for crowd hazard confirmation.

## 6. Abuse handling inside the engine

- Token bucket per origin: 10 messages/minute.
- Peers sending 5+ invalid frames in 60s are disconnected and ignored for 5 minutes.
- Storage eviction order: expired → oldest low-priority hazards → oldest unverified → never evict active SOS or verified shelters unless over the hard cap.
- Debug screen lists drop counts by reason code, useful for the demo to show the network rejecting forged messages live.

## 7. Demo-able security moment (recommended for judges)

Include a debug button "Inject forged shelter". It broadcasts an unsigned shelter and a shelter signed by a non-trusted key. Show that the mesh relays or stores them as UNVERIFIED but they never appear as Verified, then show the genuine responder-signed shelter appearing with the green badge.

## 8. Privacy notes for the pitch

- No accounts, no phone numbers, no server, no analytics.
- Only data the user chooses to broadcast leaves the phone.
- Location is broadcast only inside SOS and reports, never continuously.
