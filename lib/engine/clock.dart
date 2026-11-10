/// Injectable clock abstraction so engine timers, rate limiters, expiry, and
/// simulator steps can run deterministically without real wall-clock waits.
abstract interface class Clock {
  int nowSeconds();
  int nowMillis();
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  int nowMillis() => DateTime.now().millisecondsSinceEpoch;

  @override
  int nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

final class FakeClock implements Clock {
  int _nowMillis;

  FakeClock({int initialMillis = 1731200000000}) : _nowMillis = initialMillis;

  factory FakeClock.fromSeconds(int seconds) =>
      FakeClock(initialMillis: seconds * 1000);

  @override
  int nowMillis() => _nowMillis;

  @override
  int nowSeconds() => _nowMillis ~/ 1000;

  void setMillis(int millis) {
    _nowMillis = millis;
  }

  void setSeconds(int seconds) {
    _nowMillis = seconds * 1000;
  }

  void advanceMillis(int deltaMillis) {
    _nowMillis += deltaMillis;
  }

  void advanceSeconds(int deltaSeconds) {
    _nowMillis += deltaSeconds * 1000;
  }
}

