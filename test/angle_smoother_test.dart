import 'package:flutter_test/flutter_test.dart';
import 'package:posture_check/exercise_analyzer.dart';

void main() {
  group('AngleSmoother', () {
    test('first reading passes through unchanged', () {
      final smoother = AngleSmoother(alpha: 0.4);
      expect(smoother.smooth(100), 100);
    });

    test('blends subsequent readings using the alpha weight', () {
      final smoother = AngleSmoother(alpha: 0.4);
      smoother.smooth(100);
      // 0.4 * 150 + 0.6 * 100 = 120
      expect(smoother.smooth(150), closeTo(120, 0.0001));
    });

    test('a lone missed frame holds the last value instead of going null', () {
      final smoother = AngleSmoother(alpha: 0.4, missedFrameTolerance: 5);
      smoother.smooth(100);
      final held = smoother.smooth(150); // 120, per the blending test above.

      expect(smoother.smooth(null), held);
    });

    test('missed frames past the tolerance reset the average', () {
      final smoother = AngleSmoother(alpha: 0.4, missedFrameTolerance: 2);
      smoother.smooth(100);

      smoother.smooth(null); // miss 1: held
      smoother.smooth(null); // miss 2: held
      expect(smoother.smooth(null), isNull); // miss 3: exceeds tolerance

      // Post-reset, the next reading is a fresh baseline, not blended
      // with the pre-reset average.
      expect(smoother.smooth(80), 80);
    });

    test('a non-null reading before the tolerance is exceeded clears the miss streak', () {
      final smoother = AngleSmoother(alpha: 0.4, missedFrameTolerance: 2);
      smoother.smooth(100);
      smoother.smooth(null);
      smoother.smooth(null);
      // Recovers just before hitting the tolerance limit.
      smoother.smooth(150);

      // Two more misses now shouldn't reset, since the streak was cleared.
      smoother.smooth(null);
      expect(smoother.smooth(null), isNotNull);
    });

    test('reset() clears the running average', () {
      final smoother = AngleSmoother(alpha: 0.4);
      smoother.smooth(100);
      smoother.smooth(150);

      smoother.reset();

      expect(smoother.smooth(80), 80);
    });

    test('smooths out a single noisy spike toward the surrounding readings', () {
      final smoother = AngleSmoother(alpha: 0.4);
      double? last;
      for (final raw in <double>[100.0, 100, 100, 40, 100, 100]) {
        last = smoother.smooth(raw);
      }
      // The smoothed value after the spike should be far closer to the
      // steady 100 baseline than to the 40-degree spike itself.
      expect(last, greaterThan(70));
    });
  });
}
