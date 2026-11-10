---
name: signed-records
description: Use when implementing message signing, canonical JSON, key management, responder trust list, trust tiers or the forged-shelter demo.
---

# Signed records and trust

Source of truth: `docs/SECURITY_TRUST.md` and section 4 of `docs/PROTOCOL.md`.

## Rules
- Algorithm: Ed25519 via the `cryptography` package. Verify the package API from its current docs first.
- `origin` = first 8 hex chars of SHA-256(`originPub`). Reject if it does not match.
- Signed bytes = UTF-8 of canonical JSON of `{id,type,origin,originPub,ts,lat,lng,refId,payload}`. Not `ttl`, `hops` or `sig`.
- Canonical JSON: keys sorted at every depth, no whitespace, explicit nulls. Implement once in `engine/canonical_json.dart`, test with fixed vectors, and test that two differently-ordered maps give identical bytes.
- Device private key lives in `flutter_secure_storage`. Never log it. Never put it in the DB.
- Responder trust list: `assets/trusted_responders.json`. A message is `VERIFIED_RESPONDER` only if the signature is valid AND `originPub` is in the list.
- ACKs: accepted only from a trusted responder, or (CANCELLED/RESOLVED) from the same key as the referenced SOS origin.
- Shelters failing the authority check are `UNVERIFIED`, hidden by default, and never labelled "safe" or "verified" in the UI.
- Demo responder private key: generated for the hackathon, clearly named DEMO, PIN-gated, never presented as production-grade.

## Tests required
Valid signature, tampered payload, tampered coordinates, wrong key, origin/pub mismatch, forged shelter (valid sig, untrusted key) is UNVERIFIED, fake ACK rejected, canonical JSON determinism.
