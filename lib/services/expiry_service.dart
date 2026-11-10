import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/engine/clock.dart';

/// Periodic expiry helper purging expired records based on local `received_at`.
class ExpiryService {
  final MessageStore store;
  final Clock clock;
  final int checkIntervalSeconds;

  int _lastPurgeSec = 0;

  ExpiryService({
    required this.store,
    required this.clock,
    this.checkIntervalSeconds = 60,
  });

  Future<int> purgeIfDue({bool force = false}) async {
    final now = clock.nowSeconds();
    if (!force && now - _lastPurgeSec < checkIntervalSeconds) {
      return 0;
    }
    _lastPurgeSec = now;
    return store.purgeExpired(now);
  }
}

