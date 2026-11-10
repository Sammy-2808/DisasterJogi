import 'dart:math' as math;

import 'package:mesh_rescue/engine/clock.dart';

/// Per-origin token bucket rate limiter (default: 10 messages / 60 seconds).
class RateLimiter {
  final Clock clock;
  final int maxTokens;
  final int windowSeconds;
  final Map<String, _Bucket> _buckets = <String, _Bucket>{};

  RateLimiter({
    required this.clock,
    this.maxTokens = 10,
    this.windowSeconds = 60,
  });

  bool allow(String origin) {
    final nowMs = clock.nowMillis();
    final refillPerMs = maxTokens / (windowSeconds * 1000.0);
    final bucket = _buckets[origin];
    if (bucket == null) {
      _buckets[origin] = _Bucket(
        tokens: (maxTokens - 1).toDouble(),
        lastUpdateMs: nowMs,
      );
      return true;
    }

    final elapsedMs = math.max(0, nowMs - bucket.lastUpdateMs);
    bucket.tokens = math.min(
      maxTokens.toDouble(),
      bucket.tokens + elapsedMs * refillPerMs,
    );
    bucket.lastUpdateMs = nowMs;

    if (bucket.tokens >= 1.0) {
      bucket.tokens -= 1.0;
      return true;
    }
    return false;
  }

  void reset() => _buckets.clear();
}

class _Bucket {
  double tokens;
  int lastUpdateMs;

  _Bucket({required this.tokens, required this.lastUpdateMs});
}

/// Tracks malformed/forged frame offenses per connected peer.
/// Per SECURITY_TRUST.md section 6: 5+ invalid frames in 60s -> block for 5 min.
class PeerAbuseTracker {
  final Clock clock;
  final int threshold;
  final int windowSeconds;
  final int penaltySeconds;

  final Map<String, List<int>> _offenses = <String, List<int>>{};
  final Map<String, int> _blockedUntilSec = <String, int>{};

  PeerAbuseTracker({
    required this.clock,
    this.threshold = 5,
    this.windowSeconds = 60,
    this.penaltySeconds = 300,
  });

  bool isBlocked(String peerId) {
    final until = _blockedUntilSec[peerId];
    if (until == null) return false;
    if (clock.nowSeconds() >= until) {
      _blockedUntilSec.remove(peerId);
      return false;
    }
    return true;
  }

  /// Records one invalid frame offense. Returns true if peer should now be
  /// disconnected and ignored.
  bool recordOffense(String peerId) {
    final now = clock.nowSeconds();
    final list = _offenses.putIfAbsent(peerId, () => <int>[]);
    list.add(now);
    list.removeWhere((t) => now - t > windowSeconds);

    if (list.length >= threshold) {
      _blockedUntilSec[peerId] = now + penaltySeconds;
      list.clear();
      return true;
    }
    return false;
  }
}

