import 'package:flutter_test/flutter_test.dart';
import 'package:posture_check/exercise_analyzer.dart';
import 'package:posture_check/workout_summary.dart';

void main() {
  group('WorkoutSummary.fromReps', () {
    test('an empty rep list produces all-zero stats', () {
      final summary = WorkoutSummary.fromReps('深蹲', []);

      expect(summary.totalReps, 0);
      expect(summary.goodReps, 0);
      expect(summary.tooShallowReps, 0);
      expect(summary.tooDeepReps, 0);
      expect(summary.averageMinAngle, 0);
    });

    test('tallies quality counts and averages the min angle', () {
      final reps = [
        const RepRecord(minAngle: 80, status: RepQualityStatus.good),
        const RepRecord(minAngle: 110, status: RepQualityStatus.tooShallow),
        const RepRecord(minAngle: 60, status: RepQualityStatus.tooDeep),
        const RepRecord(minAngle: 90, status: RepQualityStatus.good),
      ];

      final summary = WorkoutSummary.fromReps('深蹲', reps);

      expect(summary.totalReps, 4);
      expect(summary.goodReps, 2);
      expect(summary.tooShallowReps, 1);
      expect(summary.tooDeepReps, 1);
      expect(summary.averageMinAngle, closeTo((80 + 110 + 60 + 90) / 4, 0.0001));
    });

    test('toJson rounds the average angle to one decimal place', () {
      final reps = [
        const RepRecord(minAngle: 80, status: RepQualityStatus.good),
        const RepRecord(minAngle: 81, status: RepQualityStatus.good),
        const RepRecord(minAngle: 81, status: RepQualityStatus.good),
      ];

      final summary = WorkoutSummary.fromReps('深蹲', reps);
      final json = summary.toJson();

      expect(json['exercise'], '深蹲');
      expect(json['total_reps'], 3);
      expect(json['good_reps'], 3);
      expect(json['average_min_angle_degrees'], closeTo(80.7, 0.0001));
    });
  });
}
