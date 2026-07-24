import 'package:flutter_test/flutter_test.dart';
import 'package:posture_check/exercise_analyzer.dart';
import 'package:posture_check/workout_history_service.dart';
import 'package:posture_check/workout_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  WorkoutSummary buildSummary(String exercise) => WorkoutSummary.fromReps(
        exercise,
        [const RepRecord(minAngle: 80, status: RepQualityStatus.good)],
      );

  group('WorkoutHistoryService', () {
    test('loadAll returns an empty list when nothing has been saved', () async {
      final service = WorkoutHistoryService();

      expect(await service.loadAll(), isEmpty);
    });

    test('save then loadAll round-trips a saved entry', () async {
      final service = WorkoutHistoryService();
      final entry = WorkoutHistoryEntry(
        summary: buildSummary('深蹲'),
        completedAt: DateTime(2026, 1, 1, 9, 30),
      );

      await service.save(entry);
      final loaded = await service.loadAll();

      expect(loaded, hasLength(1));
      expect(loaded.single.summary.exercise, '深蹲');
      expect(loaded.single.completedAt, entry.completedAt);
    });

    test('save persists the advice text and loadAll returns it', () async {
      final service = WorkoutHistoryService();
      await service.save(WorkoutHistoryEntry(
        summary: buildSummary('深蹲'),
        completedAt: DateTime(2026, 1, 1),
        advice: '幅度掌握得很穩定,可以增加負重。',
      ));

      final loaded = await service.loadAll();

      expect(loaded.single.advice, '幅度掌握得很穩定,可以增加負重。');
    });

    test('an entry saved without advice loads back with a null advice',
        () async {
      final service = WorkoutHistoryService();
      await service.save(WorkoutHistoryEntry(
        summary: buildSummary('深蹲'),
        completedAt: DateTime(2026, 1, 1),
      ));

      final loaded = await service.loadAll();

      expect(loaded.single.advice, isNull);
    });

    test('loadAll returns entries most-recent-first regardless of save order',
        () async {
      final service = WorkoutHistoryService();
      final older = WorkoutHistoryEntry(
        summary: buildSummary('深蹲'),
        completedAt: DateTime(2026, 1, 1),
      );
      final newer = WorkoutHistoryEntry(
        summary: buildSummary('伏地挺身'),
        completedAt: DateTime(2026, 1, 2),
      );

      await service.save(older);
      await service.save(newer);
      final loaded = await service.loadAll();

      expect(loaded.map((e) => e.summary.exercise), ['伏地挺身', '深蹲']);
    });

    test('clear removes all saved entries', () async {
      final service = WorkoutHistoryService();
      await service.save(WorkoutHistoryEntry(
        summary: buildSummary('深蹲'),
        completedAt: DateTime.now(),
      ));

      await service.clear();

      expect(await service.loadAll(), isEmpty);
    });
  });
}
