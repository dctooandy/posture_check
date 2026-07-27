import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

enum ExerciseType { squat, pushUp, bicepCurl, lunge, shoulderPress }

/// Groups exercises for the picker UI. Purely presentational — nothing in
/// the analysis pipeline depends on it.
enum ExerciseCategory { lowerBody, upperBody }

extension ExerciseCategoryDisplayName on ExerciseCategory {
  String get displayName => switch (this) {
        ExerciseCategory.lowerBody => '下肢',
        ExerciseCategory.upperBody => '上肢',
      };
}

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
  ExerciseCategory get category;

  /// How to position the camera for this exercise. Some exercises need a
  /// front-on view (squat), others need a side-on view (elbow bend isn't
  /// readable head-on) — shown to the user when they pick the exercise.
  String get cameraGuidance;

  /// Angle at/above which the limb is considered back at the rest position
  /// (e.g. standing tall, arms extended).
  double get restThreshold;

  /// Angle at/below which a rep is considered to have started.
  double get downThreshold;

  /// Angle at/above which a rep is considered complete (back near rest).
  double get upThreshold;

  double get goodRangeMin;
  double get goodRangeMax;

  /// True for exercises whose active/working phase bends the joint to a
  /// SMALLER angle than rest (squat, push-up, bicep curl: rest is limb
  /// extended, the rep works toward flexion). False for exercises whose
  /// working phase is a LARGER angle than rest (shoulder press: rest is the
  /// racked/bent position, the rep works toward extension). Every threshold
  /// comparison in [classify], [ExerciseFeedbackEngine.classify], and
  /// [RepCounter] is mirrored based on this flag.
  bool get contractsToSmallAngle => true;

  /// The joint angle driving this exercise's analysis, or null if the
  /// required landmarks aren't confidently visible in [pose].
  double? primaryAngle(Pose pose);

  /// Classifies the most extreme angle reached during a rep — the smallest
  /// angle for a flexion-pattern exercise, the largest for an
  /// extension-pattern one (see [contractsToSmallAngle]).
  RepQualityStatus classify(double extremeAngle) {
    if (contractsToSmallAngle) {
      if (extremeAngle > goodRangeMax) return RepQualityStatus.tooShallow;
      if (extremeAngle >= goodRangeMin) return RepQualityStatus.good;
      return RepQualityStatus.tooDeep;
    } else {
      if (extremeAngle < goodRangeMin) return RepQualityStatus.tooShallow;
      if (extremeAngle <= goodRangeMax) return RepQualityStatus.good;
      return RepQualityStatus.tooDeep;
    }
  }

  static const minLandmarkLikelihood = 0.5;

  /// Angles from however many of [sides] have all three landmarks
  /// confidently visible (e.g. both left and right knee) — a single
  /// occluded side doesn't zero out the whole reading.
  static List<double> _visibleAngles(
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
    return angles;
  }

  /// Averages the vertex angle across [sides] — for exercises where both
  /// limbs move together (e.g. a two-legged squat), so a single occluded
  /// side doesn't zero out the whole reading.
  static double? averageAngleAcrossSides(
    Pose pose,
    List<(PoseLandmarkType, PoseLandmarkType, PoseLandmarkType)> sides,
  ) {
    final angles = _visibleAngles(pose, sides);
    if (angles.isEmpty) return null;
    return angles.reduce((x, y) => x + y) / angles.length;
  }

  /// The smallest vertex angle across [sides] — for exercises where only one
  /// side is meaningfully bent at a time (e.g. the front leg in a lunge),
  /// so averaging with the other, mostly-extended side wouldn't reflect the
  /// actual depth reached.
  static double? minAngleAcrossSides(
    Pose pose,
    List<(PoseLandmarkType, PoseLandmarkType, PoseLandmarkType)> sides,
  ) {
    final angles = _visibleAngles(pose, sides);
    if (angles.isEmpty) return null;
    return angles.reduce(math.min);
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
  ExerciseCategory get category => ExerciseCategory.lowerBody;
  @override
  String get cameraGuidance => '請將手機正面對著你,確保全身(頭到腳)都在畫面裡。';
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
  ExerciseCategory get category => ExerciseCategory.upperBody;
  @override
  String get cameraGuidance => '請將手機立在身體「側邊」、與腰部同高,手肘彎曲角度側面拍才準。';
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
  ExerciseCategory get category => ExerciseCategory.upperBody;
  @override
  String get cameraGuidance => '請將手機立在身體「側邊」、與腰部同高,手肘彎曲角度側面拍才準。';
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

/// Lunge depth judged by the front leg's hip-knee-ankle angle. Only one leg
/// bends deeply at a time (the other stays closer to extended), so unlike
/// [SquatAnalyzer] this takes the smaller of the two knee angles rather than
/// averaging them — averaging would blend the bent front knee with the
/// nearly-straight back one and understate how deep the lunge actually went.
class LungeAnalyzer extends ExerciseAnalyzer {
  const LungeAnalyzer();

  @override
  ExerciseType get type => ExerciseType.lunge;
  @override
  String get displayName => '弓箭步';
  @override
  ExerciseCategory get category => ExerciseCategory.lowerBody;
  @override
  String get cameraGuidance => '請將手機正面對著你,確保全身(頭到腳)都在畫面裡。';
  @override
  double get restThreshold => 160;
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
    return ExerciseAnalyzer.minAngleAcrossSides(pose, const [
      (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
      (
        PoseLandmarkType.rightHip,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.rightAnkle
      ),
    ]);
  }
}

/// Shoulder press range judged by the shoulder-elbow-wrist angle. Unlike
/// [SquatAnalyzer]/[PushUpAnalyzer]/[BicepCurlAnalyzer], the rest position
/// between reps (weight racked at shoulder height) is the BENT end of the
/// range and the working phase presses toward full extension overhead, so
/// [contractsToSmallAngle] is false — see that flag's doc for how this
/// flips every threshold comparison. Because the arm travels mostly in the
/// frontal plane (out to the sides of the body, not front-to-back like a
/// push-up), the elbow bend is readable from a front-on camera.
class ShoulderPressAnalyzer extends ExerciseAnalyzer {
  const ShoulderPressAnalyzer();

  @override
  ExerciseType get type => ExerciseType.shoulderPress;
  @override
  String get displayName => '肩推';
  @override
  ExerciseCategory get category => ExerciseCategory.upperBody;
  @override
  String get cameraGuidance => '請將手機正面對著你,確保上半身跟手臂都在畫面裡。';
  @override
  bool get contractsToSmallAngle => false;
  @override
  double get restThreshold => 100;
  @override
  double get downThreshold => 140;
  @override
  double get upThreshold => 110;
  @override
  double get goodRangeMin => 160;
  @override
  double get goodRangeMax => 180;

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
  ExerciseType.lunge: LungeAnalyzer(),
  ExerciseType.shoulderPress: ShoulderPressAnalyzer(),
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
    if (analyzer.contractsToSmallAngle) {
      if (angle >= analyzer.restThreshold) {
        status = LiveFeedbackStatus.resting;
      } else if (angle > analyzer.goodRangeMax) {
        status = LiveFeedbackStatus.tooShallow;
      } else if (angle >= analyzer.goodRangeMin) {
        status = LiveFeedbackStatus.good;
      } else {
        status = LiveFeedbackStatus.tooDeep;
      }
    } else {
      if (angle <= analyzer.restThreshold) {
        status = LiveFeedbackStatus.resting;
      } else if (angle < analyzer.goodRangeMin) {
        status = LiveFeedbackStatus.tooShallow;
      } else if (angle <= analyzer.goodRangeMax) {
        status = LiveFeedbackStatus.good;
      } else {
        status = LiveFeedbackStatus.tooDeep;
      }
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
  // The most extreme angle reached during the in-progress rep: the smallest
  // for a flexion-pattern exercise, the largest for an extension-pattern one
  // (see ExerciseAnalyzer.contractsToSmallAngle). RepRecord.minAngle keeps
  // its name regardless — it's the value that drives classify() either way.
  double? _extremeAngleThisRep;
  int _pendingFrames = 0;

  int get reps => completedReps.length;

  void update(double? angle) {
    if (angle == null) {
      _pendingFrames = 0;
      return;
    }

    final small = analyzer.contractsToSmallAngle;

    if (!_isDown) {
      final enteredWorkingPhase =
          small ? angle <= analyzer.downThreshold : angle >= analyzer.downThreshold;
      if (enteredWorkingPhase) {
        _pendingFrames++;
        if (_pendingFrames >= requiredConsecutiveFrames) {
          _isDown = true;
          _extremeAngleThisRep = angle;
          _pendingFrames = 0;
        }
      } else {
        _pendingFrames = 0;
      }
      return;
    }

    final extremeSoFar = _extremeAngleThisRep;
    final isMoreExtreme = extremeSoFar == null ||
        (small ? angle < extremeSoFar : angle > extremeSoFar);
    if (isMoreExtreme) {
      _extremeAngleThisRep = angle;
    }

    final backNearRest =
        small ? angle >= analyzer.upThreshold : angle <= analyzer.upThreshold;
    if (backNearRest) {
      _pendingFrames++;
      if (_pendingFrames >= requiredConsecutiveFrames) {
        final extreme = _extremeAngleThisRep!;
        completedReps
            .add(RepRecord(minAngle: extreme, status: analyzer.classify(extreme)));
        _isDown = false;
        _extremeAngleThisRep = null;
        _pendingFrames = 0;
      }
    } else {
      _pendingFrames = 0;
    }
  }

  void reset() {
    completedReps.clear();
    _isDown = false;
    _extremeAngleThisRep = null;
    _pendingFrames = 0;
  }
}
