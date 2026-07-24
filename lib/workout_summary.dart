import 'exercise_analyzer.dart';

/// Aggregated stats for one workout session, in the shape that would be
/// sent to an LLM as the prompt payload (structured features, not raw
/// per-frame landmarks). Exercise-agnostic: works the same whether [reps]
/// came from a squat, push-up, or any other single-angle exercise.
class WorkoutSummary {
  const WorkoutSummary({
    required this.exercise,
    required this.totalReps,
    required this.goodReps,
    required this.tooShallowReps,
    required this.tooDeepReps,
    required this.averageMinAngle,
  });

  factory WorkoutSummary.fromReps(String exercise, List<RepRecord> reps) {
    if (reps.isEmpty) {
      return WorkoutSummary(
        exercise: exercise,
        totalReps: 0,
        goodReps: 0,
        tooShallowReps: 0,
        tooDeepReps: 0,
        averageMinAngle: 0,
      );
    }

    final good = reps.where((r) => r.status == RepQualityStatus.good).length;
    final shallow =
        reps.where((r) => r.status == RepQualityStatus.tooShallow).length;
    final deep = reps.where((r) => r.status == RepQualityStatus.tooDeep).length;
    final avgAngle =
        reps.map((r) => r.minAngle).reduce((a, b) => a + b) / reps.length;

    return WorkoutSummary(
      exercise: exercise,
      totalReps: reps.length,
      goodReps: good,
      tooShallowReps: shallow,
      tooDeepReps: deep,
      averageMinAngle: avgAngle,
    );
  }

  final String exercise;
  final int totalReps;
  final int goodReps;
  final int tooShallowReps;
  final int tooDeepReps;
  final double averageMinAngle;

  Map<String, dynamic> toJson() => {
        'exercise': exercise,
        'total_reps': totalReps,
        'good_reps': goodReps,
        'too_shallow_reps': tooShallowReps,
        'too_deep_reps': tooDeepReps,
        'average_min_angle_degrees': double.parse(
          averageMinAngle.toStringAsFixed(1),
        ),
      };
}
