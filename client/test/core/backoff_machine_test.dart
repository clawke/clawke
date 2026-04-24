import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/backoff_machine.dart';

void main() {
  group('BackoffMachine', () {
    test('first wait is short', () async {
      final bm = BackoffMachine();
      final sw = Stopwatch()..start();
      await bm.wait();
      sw.stop();
      // 第一次应该很短 (100ms ± 25% jitter = 75-125ms)
      expect(sw.elapsedMilliseconds, lessThan(200));
    });

    test('subsequent waits increase', () async {
      final bm = BackoffMachine();
      await bm.wait(); // ~100ms
      final sw = Stopwatch()..start();
      await bm.wait(); // ~200ms
      sw.stop();
      expect(sw.elapsedMilliseconds, greaterThan(100));
    });

    test('reset brings duration back to short', () async {
      final bm = BackoffMachine();
      await bm.wait();
      await bm.wait();
      await bm.wait();
      bm.reset();
      final sw = Stopwatch()..start();
      await bm.wait();
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(200));
    });
  });
}
