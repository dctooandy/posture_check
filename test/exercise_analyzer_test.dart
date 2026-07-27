import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:posture_check/exercise_analyzer.dart';

PoseLandmark _landmark(PoseLandmarkType type, double x, double y, {double likelihood = 1.0}) {
  return PoseLandmark(type: type, x: x, y: y, z: 0, likelihood: likelihood);
}

void main() {
  group('ExerciseAnalyzer.averageAngleAcrossSides', () {
    test('computes 90 degrees for a right angle', () {
      final pose = Pose(landmarks: {
        PoseLandmarkType.leftHip: _landmark(PoseLandmarkType.leftHip, 1, 0),
        PoseLandmarkType.leftKnee: _landmark(PoseLandmarkType.leftKnee, 0, 0),
        PoseLandmarkType.leftAnkle: _landmark(PoseLandmarkType.leftAnkle, 0, 1),
      });

      final angle = ExerciseAnalyzer.averageAngleAcrossSides(pose, const [
        (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
      ]);

      expect(angle, closeTo(90, 0.001));
    });

    test('computes 180 degrees for a straight line', () {
      final pose = Pose(landmarks: {
        PoseLandmarkType.leftHip: _landmark(PoseLandmarkType.leftHip, 1, 0),
        PoseLandmarkType.leftKnee: _landmark(PoseLandmarkType.leftKnee, 0, 0),
        PoseLandmarkType.leftAnkle: _landmark(PoseLandmarkType.leftAnkle, -1, 0),
      });

      final angle = ExerciseAnalyzer.averageAngleAcrossSides(pose, const [
        (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
      ]);

      expect(angle, closeTo(180, 0.001));
    });

    test('averages both sides when both are visible', () {
      final pose = Pose(landmarks: {
        // Left side: 90 degrees.
        PoseLandmarkType.leftHip: _landmark(PoseLandmarkType.leftHip, 1, 0),
        PoseLandmarkType.leftKnee: _landmark(PoseLandmarkType.leftKnee, 0, 0),
        PoseLandmarkType.leftAnkle: _landmark(PoseLandmarkType.leftAnkle, 0, 1),
        // Right side: 180 degrees.
        PoseLandmarkType.rightHip: _landmark(PoseLandmarkType.rightHip, 1, 0),
        PoseLandmarkType.rightKnee: _landmark(PoseLandmarkType.rightKnee, 0, 0),
        PoseLandmarkType.rightAnkle: _landmark(PoseLandmarkType.rightAnkle, -1, 0),
      });

      final angle = ExerciseAnalyzer.averageAngleAcrossSides(pose, const [
        (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
        (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
      ]);

      expect(angle, closeTo(135, 0.001));
    });

    test('falls back to the visible side when the other is missing', () {
      final pose = Pose(landmarks: {
        PoseLandmarkType.leftHip: _landmark(PoseLandmarkType.leftHip, 1, 0),
        PoseLandmarkType.leftKnee: _landmark(PoseLandmarkType.leftKnee, 0, 0),
        PoseLandmarkType.leftAnkle: _landmark(PoseLandmarkType.leftAnkle, 0, 1),
      });

      final angle = ExerciseAnalyzer.averageAngleAcrossSides(pose, const [
        (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
        (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
      ]);

      expect(angle, closeTo(90, 0.001));
    });

    test('returns null when a landmark is below the confidence threshold', () {
      final pose = Pose(landmarks: {
        PoseLandmarkType.leftHip: _landmark(PoseLandmarkType.leftHip, 1, 0, likelihood: 0.2),
        PoseLandmarkType.leftKnee: _landmark(PoseLandmarkType.leftKnee, 0, 0),
        PoseLandmarkType.leftAnkle: _landmark(PoseLandmarkType.leftAnkle, 0, 1),
      });

      final angle = ExerciseAnalyzer.averageAngleAcrossSides(pose, const [
        (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
      ]);

      expect(angle, isNull);
    });

    test('returns null when no side has all three landmarks', () {
      final pose = Pose(landmarks: {
        PoseLandmarkType.leftHip: _landmark(PoseLandmarkType.leftHip, 1, 0),
        PoseLandmarkType.leftKnee: _landmark(PoseLandmarkType.leftKnee, 0, 0),
      });

      final angle = ExerciseAnalyzer.averageAngleAcrossSides(pose, const [
        (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
      ]);

      expect(angle, isNull);
    });
  });

  group('SquatAnalyzer.classify', () {
    const analyzer = SquatAnalyzer();

    test('angle above goodRangeMax is tooShallow', () {
      expect(analyzer.classify(101), RepQualityStatus.tooShallow);
    });

    test('angle at goodRangeMax boundary is good', () {
      expect(analyzer.classify(100), RepQualityStatus.good);
    });

    test('angle at goodRangeMin boundary is good', () {
      expect(analyzer.classify(70), RepQualityStatus.good);
    });

    test('angle below goodRangeMin is tooDeep', () {
      expect(analyzer.classify(69), RepQualityStatus.tooDeep);
    });
  });

  group('PushUpAnalyzer.classify', () {
    const analyzer = PushUpAnalyzer();

    test('angle above goodRangeMax is tooShallow', () {
      expect(analyzer.classify(111), RepQualityStatus.tooShallow);
    });

    test('angle within good range is good', () {
      expect(analyzer.classify(90), RepQualityStatus.good);
    });

    test('angle below goodRangeMin is tooDeep', () {
      expect(analyzer.classify(60), RepQualityStatus.tooDeep);
    });
  });

  group('BicepCurlAnalyzer.classify', () {
    const analyzer = BicepCurlAnalyzer();

    test('angle above goodRangeMax is tooShallow (curl not deep enough)', () {
      expect(analyzer.classify(80), RepQualityStatus.tooShallow);
    });

    test('angle within good range is good', () {
      expect(analyzer.classify(50), RepQualityStatus.good);
    });

    test('angle below goodRangeMin is tooDeep', () {
      expect(analyzer.classify(20), RepQualityStatus.tooDeep);
    });
  });

  group('LungeAnalyzer.classify', () {
    const analyzer = LungeAnalyzer();

    test('angle above goodRangeMax is tooShallow', () {
      expect(analyzer.classify(101), RepQualityStatus.tooShallow);
    });

    test('angle within good range is good', () {
      expect(analyzer.classify(85), RepQualityStatus.good);
    });

    test('angle below goodRangeMin is tooDeep', () {
      expect(analyzer.classify(60), RepQualityStatus.tooDeep);
    });
  });

  group('LungeAnalyzer.primaryAngle', () {
    const analyzer = LungeAnalyzer();

    test('takes the more-bent leg rather than averaging both', () {
      final pose = Pose(landmarks: {
        // Front leg: bent to 90 degrees.
        PoseLandmarkType.leftHip: _landmark(PoseLandmarkType.leftHip, 1, 0),
        PoseLandmarkType.leftKnee: _landmark(PoseLandmarkType.leftKnee, 0, 0),
        PoseLandmarkType.leftAnkle: _landmark(PoseLandmarkType.leftAnkle, 0, 1),
        // Back leg: nearly straight, 180 degrees.
        PoseLandmarkType.rightHip: _landmark(PoseLandmarkType.rightHip, 1, 0),
        PoseLandmarkType.rightKnee: _landmark(PoseLandmarkType.rightKnee, 0, 0),
        PoseLandmarkType.rightAnkle: _landmark(PoseLandmarkType.rightAnkle, -1, 0),
      });

      expect(analyzer.primaryAngle(pose), closeTo(90, 0.001));
    });
  });

  group('ShoulderPressAnalyzer.classify (extension pattern)', () {
    const analyzer = ShoulderPressAnalyzer();

    test('angle below goodRangeMin is tooShallow (did not fully extend)', () {
      expect(analyzer.classify(150), RepQualityStatus.tooShallow);
    });

    test('angle within good range is good', () {
      expect(analyzer.classify(170), RepQualityStatus.good);
    });
  });

  group('ExerciseFeedbackEngine.classify', () {
    test('null angle is noPoseDetected', () {
      final feedback = ExerciseFeedbackEngine.classify(null, const SquatAnalyzer());
      expect(feedback.status, LiveFeedbackStatus.noPoseDetected);
    });

    group('flexion-pattern exercise (contractsToSmallAngle true)', () {
      const analyzer = SquatAnalyzer();

      test('angle at/above restThreshold is resting', () {
        expect(
          ExerciseFeedbackEngine.classify(160, analyzer).status,
          LiveFeedbackStatus.resting,
        );
      });

      test('angle within good range is good', () {
        expect(
          ExerciseFeedbackEngine.classify(90, analyzer).status,
          LiveFeedbackStatus.good,
        );
      });

      test('angle below goodRangeMin is tooDeep', () {
        expect(
          ExerciseFeedbackEngine.classify(60, analyzer).status,
          LiveFeedbackStatus.tooDeep,
        );
      });
    });

    group('extension-pattern exercise (contractsToSmallAngle false)', () {
      const analyzer = ShoulderPressAnalyzer();

      test('angle at/below restThreshold is resting', () {
        expect(
          ExerciseFeedbackEngine.classify(90, analyzer).status,
          LiveFeedbackStatus.resting,
        );
      });

      test('angle within good range is good', () {
        expect(
          ExerciseFeedbackEngine.classify(170, analyzer).status,
          LiveFeedbackStatus.good,
        );
      });

      test('angle below goodRangeMin (but above rest) is tooShallow', () {
        expect(
          ExerciseFeedbackEngine.classify(130, analyzer).status,
          LiveFeedbackStatus.tooShallow,
        );
      });
    });
  });

  group('kExerciseAnalyzers', () {
    test('has an analyzer registered for every ExerciseType', () {
      for (final type in ExerciseType.values) {
        expect(kExerciseAnalyzers.containsKey(type), isTrue, reason: '$type missing an analyzer');
        expect(kExerciseAnalyzers[type]!.type, type);
      }
    });
  });
}
