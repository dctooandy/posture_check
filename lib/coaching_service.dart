import 'dart:convert';

import 'package:http/http.dart' as http;

import 'workout_summary.dart';

/// Turns a [WorkoutSummary] into personalized coaching text.
abstract class CoachingService {
  Future<String> getAdvice(WorkoutSummary summary);
}

/// Fakes the LLM round trip (including network delay) so the rest of the app
/// can be built and demoed without a network call or API key.
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

/// Calls the Claude API directly from the app. There's no official Dart/
/// Flutter Anthropic SDK, so this goes over raw HTTP per the Messages API.
///
/// The API key ends up embedded in the built app binary either way — fine
/// for a POC, but a shipped app should route this through a backend that
/// holds the key instead of calling Anthropic directly from the client.
class ClaudeCoachingService implements CoachingService {
  ClaudeCoachingService({required this.apiKey, this.model = 'claude-haiku-4-5'});

  final String apiKey;
  final String model;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  @override
  Future<String> getAdvice(WorkoutSummary summary) async {
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 300,
        'messages': [
          {'role': 'user', 'content': _buildPrompt(summary)},
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Claude API 呼叫失敗 (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final content = decoded['content'] as List<dynamic>;
    final textBlock = content.firstWhere(
      (block) => block['type'] == 'text',
      orElse: () => null,
    );

    if (textBlock == null) {
      throw Exception('Claude API 回應中沒有文字內容');
    }

    return (textBlock['text'] as String).trim();
  }

  String _buildPrompt(WorkoutSummary summary) {
    final data = jsonEncode(summary.toJson());
    return '你是一位健身教練。根據以下訓練數據,用繁體中文寫一段簡短、具體的訓練建議(3 到 5 句):\n\n'
        '$data\n\n'
        '內容需要:提到完成次數與品質分佈、指出主要問題(幅度不夠或過深)、給一個具體可執行的改善建議。'
        '直接輸出建議文字本身,不要開場白、不要標題、不要條列符號。';
  }
}
