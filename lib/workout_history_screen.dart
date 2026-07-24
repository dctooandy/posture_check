import 'package:flutter/material.dart';

import 'workout_history_service.dart';

/// Lists past completed workouts, most recent first.
class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key, required this.historyService});

  final WorkoutHistoryService historyService;

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  late Future<List<WorkoutHistoryEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = widget.historyService.loadAll();
  }

  Future<void> _clearHistory() async {
    await widget.historyService.clear();
    setState(() {
      _entriesFuture = widget.historyService.loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('訓練歷史', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            tooltip: '清除歷史紀錄',
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearHistory,
          ),
        ],
      ),
      body: FutureBuilder<List<WorkoutHistoryEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            );
          }

          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(
              child: Text('尚無訓練紀錄', style: TextStyle(color: Colors.white54)),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _HistoryTile(entry: entries[index]),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final WorkoutHistoryEntry entry;

  static String _formatDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}/${two(date.month)}/${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final summary = entry.summary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                summary.exercise,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _formatDate(entry.completedAt),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '共 ${summary.totalReps} 下 · 達標 ${summary.goodReps} · '
            '太淺 ${summary.tooShallowReps} · 太深 ${summary.tooDeepReps}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (entry.advice != null) ...[
            const SizedBox(height: 12),
            Text(
              entry.advice!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
