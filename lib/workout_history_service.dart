import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'workout_summary.dart';

/// A completed [WorkoutSummary] paired with when it happened, for display in
/// the history list (the summary's own JSON is the LLM prompt payload and
/// intentionally has no timestamp of its own).
class WorkoutHistoryEntry {
  const WorkoutHistoryEntry({
    required this.summary,
    required this.completedAt,
    this.advice,
  });

  final WorkoutSummary summary;
  final DateTime completedAt;
  final String? advice;

  Map<String, dynamic> toJson() => {
        ...summary.toJson(),
        'completed_at': completedAt.toIso8601String(),
        if (advice != null) 'advice': advice,
      };

  factory WorkoutHistoryEntry.fromJson(Map<String, dynamic> json) =>
      WorkoutHistoryEntry(
        summary: WorkoutSummary.fromJson(json),
        completedAt: DateTime.parse(json['completed_at'] as String),
        advice: json['advice'] as String?,
      );
}

/// Persists completed workouts locally so they survive an app restart.
class WorkoutHistoryService {
  static const _key = 'workout_history';

  Future<List<WorkoutHistoryEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final entries = raw
        .map((s) => WorkoutHistoryEntry.fromJson(
              jsonDecode(s) as Map<String, dynamic>,
            ))
        .toList();
    entries.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return entries;
  }

  Future<void> save(WorkoutHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    await prefs.setStringList(_key, [...raw, jsonEncode(entry.toJson())]);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
