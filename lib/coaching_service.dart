import 'workout_summary.dart';

/// Turns a [WorkoutSummary] into personalized coaching text.
///
/// This is the seam where a real LLM call goes later: build a prompt from
/// `summary.toJson()`, call the provider's API, return the response text.
/// [MockCoachingService] fakes that round trip (including network delay) so
/// the rest of the app can be built and demoed before an API key/provider is
/// chosen.
abstract class CoachingService {
  Future<String> getAdvice(WorkoutSummary summary);
}

class MockCoachingService implements CoachingService {
  @override
  Future<String> getAdvice(WorkoutSummary summary) async {
    await Future.delayed(const Duration(milliseconds: 600));

    if (summary.totalReps == 0) {
      return '這次還沒有偵測到完整的${summary.exercise}次數,再試一次看看。';
    }

    final goodRatio = summary.goodReps / summary.totalReps;
    final buffer = StringBuffer()
      ..writeln('本次共完成 ${summary.totalReps} 下${summary.exercise},'
          '幅度達標 ${summary.goodReps} 下、'
          '太淺 ${summary.tooShallowReps} 下、'
          '太深 ${summary.tooDeepReps} 下。');

    if (goodRatio >= 0.8) {
      buffer.write('動作幅度掌握得很穩定,可以考慮增加負重或次數來提升強度。');
    } else if (summary.tooShallowReps >= summary.tooDeepReps) {
      buffer.write('大部分次數的活動範圍不夠大,建議放慢速度,'
          '確實蹲低/壓低到位再回到起始位置,感受目標肌群發力。');
    } else {
      buffer.write('有不少次數動作幅度偏大,注意關節角度是否超出安全範圍,'
          '必要時縮小動作幅度以保護關節。');
    }

    return buffer.toString();
  }
}
