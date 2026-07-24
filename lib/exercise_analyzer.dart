import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

enum ExerciseType { squat, pushUp, bicepCurl }

/// Quality of a single completed rep, judged against [ExerciseAnalyzer]'s
/// good-range thresholds.
enum RepQualityStatus { tooShallow, good, tooDeep }

/// Live (per-frame) feedback status shown while the user is mid-rep.
enum LiveFeedbackStatus { noPoseDetected, resting, tooShallow, good, tooDeep }

/// One completed rep: the deepest angle reached and its quality.
class RepRecord {
  const RepRecord({required this.minAngle, required this.status});

  final double minAngle;
  final RepQualityStatus status;
}

class ExerciseFeedback {
  const ExerciseFeedback({required this.status, this.angle});

  final LiveFeedbackStatus status;
  final double? angle;
}

/// Defines how to extract the one joint angle that drives rep detection and
/// depth/range-of-motion judgement for a given exercise, plus the thresholds
/// that turn that angle into real-time feedback. Adding a new exercise means
/// writing a new implementation of this — nothing else in the pipeline
/// (rep counting, live feedback, workout summary, coaching prompt) needs to
/// change.
abstract class ExerciseAnalyzer {
  const ExerciseAnalyzer();

  ExerciseType get type;
  String get displayName;

  /// Angle at/above which the limb is considered back at the rest position
  /// (e.g. standing tall, arms extended).
  double get restThreshold;

  /// Angle at/below which a rep is considered to have started.
  double get downThreshold;

  /// Angle at/above which a rep is considered complete (back near rest).
  double get upThreshold;

  double get goodRangeMin;
  double get goodRangeMax;

  /// The joint angle driving this exercise's analysis, or null if the
  /// required landmarks aren't confidently visible in [pose].
  double? primaryAngle(Pose pose);

  RepQualityStatus classify(double minAngle) {
    if (minAngle > goodRangeMax) return RepQualityStatus.tooShallow;
    if (minAngle >= goodRangeMin) return RepQualityStatus.good;
    return RepQualityStatus.tooDeep;
  }

  static const minLandmarkLikelihood = 0.5;

  /// Averages the vertex angle across however many of [sides] have all
  /// three landmarks visible (e.g. both left and right knee), so a single
  /// occluded side doesn't zero out the whole reading.
  static double? averageAngleAcrossSides(
    Pose pose,
    List<(PoseLandmarkType, PoseLandmarkType, PoseLandmarkType)> sides,
  ) {
    final angles = <double>[];
    for (final (a, vertex, c) in sides) {
      final pa = pose.landmarks[a];
      final pv = pose.landmarks[vertex];
      final pc = pose.landmarks[c];
      if (pa == null || pv == null || pc == null) continue;
      if (pa.likelihood < minLandmarkLikelihood ||
          pv.likelihood < minLandmarkLikelihood ||
          pc.likelihood < minLandmarkLikelihood) {
        continue;
      }
      angles.add(_angleAtVertex(pa, pv, pc));
    }
    if (angles.isEmpty) return null;
    return angles.reduce((x, y) => x + y) / angles.length;
  }

  /// Angle at [vertex] formed by rays toward [a] and [c], in degrees.
  static double _angleAtVertex(PoseLandmark a, PoseLandmark vertex, PoseLandmark c) {
    final radians = math.atan2(c.y - vertex.y, c.x - vertex.x) -
        math.atan2(a.y - vertex.y, a.x - vertex.x);
    final degrees = (radians * 180 / math.pi).abs();
    return degrees > 180 ? 360 - degrees : degrees;
  }
}

/// Squat depth judged by the hip-knee-ankle angle. Camera should face the
/// user (front or back camera, standing upright in frame).
class SquatAnalyzer extends ExerciseAnalyzer {
  const SquatAnalyzer();

  @override
  ExerciseType get type => ExerciseType.squat;
  @override
  String get displayName => '深蹲';
  @override
  double get restThreshold => 160;
  // Deliberately above goodRangeMax: a rep that dips into the down phase
  // but never gets past this without reaching goodRangeMax still completes
  // and gets classified tooShallow, rather than silently not counting.
  @override
  double get downThreshold => 115;
  @override
  double get upThreshold => 150;
  @override
  double get goodRangeMin => 70;
  @override
  double get goodRangeMax => 100;

  @override
  double? primaryAngle(Pose pose) {
    return ExerciseAnalyzer.averageAngleAcrossSides(pose, const [
      (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
      (
        PoseLandmarkType.rightHip,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.rightAnkle
      ),
    ]);
  }
}

/// Push-up depth judged by the shoulder-elbow-wrist angle. Camera should be
/// positioned to the side, at roughly torso height, since the elbow bend
/// isn't readable head-on.
class PushUpAnalyzer extends ExerciseAnalyzer {
  const PushUpAnalyzer();

  @override
  ExerciseType get type => ExerciseType.pushUp;
  @override
  String get displayName => '伏地挺身';
  @override
  double get restThreshold => 160;
  // See SquatAnalyzer.downThreshold: kept above goodRangeMax so a shallow
  // push-up still completes as a counted (tooShallow) rep.
  @override
  double get downThreshold => 130;
  @override
  double get upThreshold => 150;
  @override
  double get goodRangeMin => 70;
  @override
  double get goodRangeMax => 110;

  @override
  double? primaryAngle(Pose pose) {
    return ExerciseAnalyzer.averageAngleAcrossSides(pose, const [
      (
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.leftWrist
      ),
      (
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.rightWrist
      ),
    ]);
  }
}

/// Bicep curl depth judged by the shoulder-elbow-wrist angle: large when the
/// arm hangs extended, small at the top of the curl. Same landmark triple as
/// [PushUpAnalyzer] but the rest/contracted ends are swapped in emphasis and
/// the thresholds are tuned for a curl's range of motion rather than a
/// push-up's. Like push-ups, the elbow bend reads best from a side-on
/// camera angle rather than head-on.
class BicepCurlAnalyzer extends ExerciseAnalyzer {
  const BicepCurlAnalyzer();

  @override
  ExerciseType get type => ExerciseType.bicepCurl;
  @override
  String get displayName => '啞鈴彎舉';
  @override
  double get restThreshold => 150;
  @override
  double get downThreshold => 120;
  @override
  double get upThreshold => 140;
  @override
  double get goodRangeMin => 30;
  @override
  double get goodRangeMax => 70;

  @override
  double? primaryAngle(Pose pose) {
    return ExerciseAnalyzer.averageAngleAcrossSides(pose, const [
      (
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.leftWrist
      ),
      (
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.rightWrist
      ),
    ]);
  }
}

const kExerciseAnalyzers = <ExerciseType, ExerciseAnalyzer>{
  ExerciseType.squat: SquatAnalyzer(),
  ExerciseType.pushUp: PushUpAnalyzer(),
  ExerciseType.bicepCurl: BicepCurlAnalyzer(),
};

/// Turns the live pose stream into real-time feedback for whichever
/// [analyzer] is currently selected. Split into [rawAngle] + [classify] so a
/// smoother (see [AngleSmoother]) can sit between raw extraction and
/// threshold classification.
class ExerciseFeedbackEngine {
  static double? rawAngle(List<Pose> poses, ExerciseAnalyzer analyzer) {
    if (poses.isEmpty) return null;
    return analyzer.primaryAngle(poses.first);
  }

  static ExerciseFeedback classify(double? angle, ExerciseAnalyzer analyzer) {
    if (angle == null) {
      return const ExerciseFeedback(status: LiveFeedbackStatus.noPoseDetected);
    }

    final LiveFeedbackStatus status;
    if (angle >= analyzer.restThreshold) {
      status = LiveFeedbackStatus.resting;
    } else if (angle > analyzer.goodRangeMax) {
      status = LiveFeedbackStatus.tooShallow;
    } else if (angle >= analyzer.goodRangeMin) {
      status = LiveFeedbackStatus.good;
    } else {
      status = LiveFeedbackStatus.tooDeep;
    }

    return ExerciseFeedback(status: status, angle: angle);
  }
}

/// Exponential moving average over the per-frame angle reading. ML Kit's
/// landmark coordinates carry frame-to-frame noise even when the person
/// holds still, which otherwise shows up as a jittery angle number and can
/// nudge [RepCounter] across a threshold on a single noisy frame.
///
/// A missing reading (no confident pose) doesn't reset the average
/// immediately: a person briefly stepping out of frame, or ML Kit dropping a
/// single frame, shouldn't flash the live feedback banner to "no pose
/// detected" and back. Up to [missedFrameTolerance] consecutive misses hold
/// the last known value instead; only a longer gap resets to null, so a
/// genuinely absent person is still reported correctly.
class AngleSmoother {
  AngleSmoother({this.alpha = 0.4, this.missedFrameTolerance = 5});

  final double alpha;
  final int missedFrameTolerance;

  double? _value;
  int _missedFrames = 0;

  double? smooth(double? raw) {
    if (raw == null) {
      _missedFrames++;
      if (_missedFrames > missedFrameTolerance) {
        _value = null;
        return null;
      }
      return _value;
    }

    _missedFrames = 0;
    final previous = _value;
    _value = previous == null ? raw : alpha * raw + (1 - alpha) * previous;
    return _value;
  }

  void reset() {
    _value = null;
    _missedFrames = 0;
  }
}

/// Counts reps from the angle stream using a two-threshold state machine.
/// The gap between [ExerciseAnalyzer.downThreshold] and `.upThreshold` is
/// hysteresis: without it, an angle hovering near one cutoff would
/// double-count reps on landmark jitter alone. Also tracks each rep's
/// deepest angle for the end-of-workout quality breakdown.
///
/// [requiredConsecutiveFrames] adds a second layer of debounce on top of the
/// hysteresis gap: a state flip only commits once the angle has stayed past
/// the relevant threshold for that many updates in a row, so one noisy frame
/// landing just past a threshold can't flip state by itself.
class RepCounter {
  RepCounter(this.analyzer, {this.requiredConsecutiveFrames = 3});

  final ExerciseAnalyzer analyzer;
  final int requiredConsecutiveFrames;

  final List<RepRecord> completedReps = [];
  bool _isDown = false;
  double? _minAngleThisRep;
  int _pendingFrames = 0;

  int get reps => completedReps.length;

  void update(double? angle) {
    if (angle == null) {
      _pendingFrames = 0;
      return;
    }

    if (!_isDown) {
      if (angle <= analyzer.downThreshold) {
        _pendingFrames++;
        if (_pendingFrames >= requiredConsecutiveFrames) {
          _isDown = true;
          _minAngleThisRep = angle;
          _pendingFrames = 0;
        }
      } else {
        _pendingFrames = 0;
      }
      return;
    }

    final minSoFar = _minAngleThisRep;
    if (minSoFar == null || angle < minSoFar) {
      _minAngleThisRep = angle;
    }

    if (angle >= analyzer.upThreshold) {
      _pendingFrames++;
      if (_pendingFrames >= requiredConsecutiveFrames) {
        final min = _minAngleThisRep!;
        completedReps.add(RepRecord(minAngle: min, status: analyzer.classify(min)));
        _isDown = false;
        _minAngleThisRep = null;
        _pendingFrames = 0;
      }
    } else {
      _pendingFrames = 0;
    }
  }

  void reset() {
    completedReps.clear();
    _isDown = false;
    _minAngleThisRep = null;
    _pendingFrames = 0;
  }
}
