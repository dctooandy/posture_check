import 'package:flutter_test/flutter_test.dart';
import 'package:posture_check/exercise_analyzer.dart';

void main() {
  group('RepCounter', () {
    // downThreshold=100, upThreshold=150, goodRangeMin=70, goodRangeMax=100.
    const analyzer = SquatAnalyzer();

    test('counts one rep after a full down-then-up cycle', () {
      final counter = RepCounter(analyzer, requiredConsecutiveFrames: 3);

      for (final angle in <double>[170.0, 95, 95, 95, 80, 160, 160, 160]) {
        counter.update(angle);
      }

      expect(counter.reps, 1);
      expect(counter.completedReps.single.minAngle, 80);
      expect(counter.completedReps.single.status, RepQualityStatus.good);
    });

    test('a single noisy frame past the down threshold does not start a rep', () {
      final counter = RepCounter(analyzer, requiredConsecutiveFrames: 3);

      for (final angle in <double>[170.0, 170, 95, 170, 170, 160, 160, 160]) {
        counter.update(angle);
      }

      expect(counter.reps, 0);
      expect(counter.completedReps, isEmpty);
    });

    test('fluctuating below the up threshold never completes a rep', () {
      final counter = RepCounter(analyzer, requiredConsecutiveFrames: 3);

      // Enter the down phase, then bounce between two angles that never
      // reach upThreshold (150).
      for (final angle in <double>[95.0, 95, 95, 90, 100, 95, 105, 95, 100]) {
        counter.update(angle);
      }

      expect(counter.reps, 0);
    });

    test('records the deepest angle reached during the rep, not the last one', () {
      final counter = RepCounter(analyzer, requiredConsecutiveFrames: 3);

      for (final angle in <double>[170.0, 95, 95, 95, 75, 90, 160, 160, 160]) {
        counter.update(angle);
      }

      expect(counter.reps, 1);
      expect(counter.completedReps.single.minAngle, 75);
    });

    test('classifies a shallow rep as tooShallow', () {
      final counter = RepCounter(analyzer, requiredConsecutiveFrames: 3);

      // Dips into the down phase (<= downThreshold 115) but never reaches
      // goodRangeMax (100), so it should still complete as a counted rep,
      // just classified tooShallow rather than good.
      for (final angle in <double>[170.0, 110, 110, 110, 160, 160, 160]) {
        counter.update(angle);
      }

      expect(counter.reps, 1);
      expect(counter.completedReps.single.status, RepQualityStatus.tooShallow);
    });

    test('null readings do not advance the pending-frame counter', () {
      final counter = RepCounter(analyzer, requiredConsecutiveFrames: 3);

      counter.update(95);
      counter.update(null); // dropout frame, should not count toward debounce
      counter.update(95);
      counter.update(95);
      // Only two consecutive valid sub-threshold frames landed after the
      // null reset the pending counter, so the rep should not have started.
      counter.update(160);
      counter.update(160);
      counter.update(160);

      expect(counter.reps, 0);
    });

    test('reset clears completed reps and in-progress state', () {
      final counter = RepCounter(analyzer, requiredConsecutiveFrames: 3);
      for (final angle in <double>[95.0, 95, 95, 160, 160, 160]) {
        counter.update(angle);
      }
      expect(counter.reps, 1);

      counter.reset();

      expect(counter.reps, 0);
      expect(counter.completedReps, isEmpty);

      // Counter should behave like new after reset.
      for (final angle in <double>[95.0, 95, 95, 160, 160, 160]) {
        counter.update(angle);
      }
      expect(counter.reps, 1);
    });
  });
}
