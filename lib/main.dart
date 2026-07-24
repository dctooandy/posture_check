import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'coaching_service.dart';
import 'exercise_analyzer.dart';
import 'pose_painter.dart';
import 'workout_summary.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const PostureCheckApp());
}

class PostureCheckApp extends StatelessWidget {
  const PostureCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Posture Check',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const PoseCameraScreen(),
    );
  }
}

class PoseCameraScreen extends StatefulWidget {
  const PoseCameraScreen({super.key});

  @override
  State<PoseCameraScreen> createState() => _PoseCameraScreenState();
}

class _PoseCameraScreenState extends State<PoseCameraScreen>
    with WidgetsBindingObserver {
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  final CoachingService _coachingService = MockCoachingService();

  CameraController? _controller;
  int _cameraIndex = 0;
  bool _isBusy = false;
  List<Pose> _poses = [];
  Size? _imageSize;
  InputImageRotation _imageRotation = InputImageRotation.rotation0deg;
  String? _error;

  ExerciseType _exerciseType = ExerciseType.squat;
  ExerciseAnalyzer get _analyzer => kExerciseAnalyzers[_exerciseType]!;
  late RepCounter _repCounter = RepCounter(_analyzer);
  final AngleSmoother _angleSmoother = AngleSmoother();
  ExerciseFeedback _feedback = const ExerciseFeedback(status: LiveFeedbackStatus.noPoseDetected);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraIndex =
        _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    if (_cameraIndex == -1) _cameraIndex = 0;
    _startCamera();
  }

  Future<void> _startCamera() async {
    final camera = _cameras[_cameraIndex];
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.startImageStream(_processImage);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = '相機初始化失敗: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      controller.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isBusy) return;
    _isBusy = true;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage?.metadata != null) {
      try {
        final poses = await _poseDetector.processImage(inputImage!);
        if (mounted) {
          setState(() {
            _poses = poses;
            _imageSize = inputImage.metadata!.size;
            _imageRotation = inputImage.metadata!.rotation;
            final raw = ExerciseFeedbackEngine.rawAngle(poses, _analyzer);
            final smoothed = _angleSmoother.smooth(raw);
            _feedback = ExerciseFeedbackEngine.classify(smoothed, _analyzer);
            _repCounter.update(smoothed);
          });
        }
      } catch (_) {
        // Skip frames that fail to process; not fatal for a POC feedback loop.
      }
    }
    _isBusy = false;
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      final controller = _controller;
      if (controller == null) return null;
      var rotationCompensation = _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final expectedFormat =
        Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || format != expectedFormat || image.planes.length != 1) {
      return null;
    }

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  void _selectExercise(ExerciseType type) {
    if (type == _exerciseType) return;
    setState(() {
      _exerciseType = type;
      _repCounter = RepCounter(_analyzer);
      _angleSmoother.reset();
      _feedback = const ExerciseFeedback(status: LiveFeedbackStatus.noPoseDetected);
    });
  }

  void _showWorkoutSummary() {
    final summary =
        WorkoutSummary.fromReps(_analyzer.displayName, _repCounter.completedReps);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SummarySheet(
        summary: summary,
        coachingService: _coachingService,
      ),
    );
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _imageSize = null;
    _poses = [];
    await _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    Widget body;
    if (_error != null) {
      body = Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white)),
      );
    } else if (controller == null || !controller.value.isInitialized) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(controller),
          if (_imageSize != null)
            CustomPaint(
              painter: PosePainter(
                poses: _poses,
                imageSize: _imageSize!,
                rotation: _imageRotation,
                cameraLensDirection: _cameras[_cameraIndex].lensDirection,
              ),
            ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RepCounterBadge(reps: _repCounter.reps),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: _ExercisePicker(
                      selected: _exerciseType,
                      onSelected: _selectExercise,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 72,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: 'switch_camera',
                  tooltip: '切換鏡頭',
                  onPressed: _cameras.length > 1 ? _switchCamera : null,
                  child: const Icon(Icons.cameraswitch),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'reset_reps',
                  tooltip: '重設次數',
                  backgroundColor: Colors.black54,
                  onPressed: () => setState(_repCounter.reset),
                  child: const Icon(Icons.refresh),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'workout_summary',
                  tooltip: '產生訓練建議',
                  backgroundColor: Colors.deepPurple,
                  onPressed: _repCounter.reps > 0 ? _showWorkoutSummary : null,
                  child: const Icon(Icons.assessment),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: _FeedbackBanner(feedback: _feedback),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: body),
    );
  }
}

class _ExercisePicker extends StatelessWidget {
  const _ExercisePicker({required this.selected, required this.onSelected});

  final ExerciseType selected;
  final ValueChanged<ExerciseType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in ExerciseType.values)
              GestureDetector(
                onTap: () => onSelected(type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: type == selected ? Colors.deepPurple : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    kExerciseAnalyzers[type]!.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RepCounterBadge extends StatelessWidget {
  const _RepCounterBadge({required this.reps});

  final int reps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '次數: $reps',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.feedback});

  final ExerciseFeedback feedback;

  static const _messages = {
    LiveFeedbackStatus.noPoseDetected: '偵測不到身體,請完整站入鏡頭',
    LiveFeedbackStatus.resting: '請開始動作',
    LiveFeedbackStatus.tooShallow: '幅度不夠,再深一點',
    LiveFeedbackStatus.good: '幅度足夠 👍',
    LiveFeedbackStatus.tooDeep: '幅度過大,請留意關節安全',
  };

  static const _colors = {
    LiveFeedbackStatus.noPoseDetected: Colors.grey,
    LiveFeedbackStatus.resting: Colors.blueGrey,
    LiveFeedbackStatus.tooShallow: Colors.orange,
    LiveFeedbackStatus.good: Colors.green,
    LiveFeedbackStatus.tooDeep: Colors.redAccent,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[feedback.status]!;
    final angle = feedback.angle;

    // A fixed max height so this banner can never grow into a screen-filling
    // card, regardless of how AnimatedSwitcher's transition entries stack up
    // if the underlying status flickers faster than its transition duration
    // (e.g. a person repeatedly leaving/re-entering frame). 140 leaves
    // headroom above the ~65px two CJK text lines + padding actually need,
    // since CJK line-height metrics run taller than Latin text at the same
    // font size, and system font-scale settings add further slack.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 140),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              // Outgoing text disappears instantly instead of fading out.
              // Without this, a burst of rapid status changes (e.g. angle
              // sweeping through multiple thresholds as someone raises their
              // arms) can leave several outgoing entries alive at once,
              // which is what was overflowing the banner's height cap.
              reverseDuration: Duration.zero,
              child: Text(
                _messages[feedback.status]!,
                key: ValueKey(feedback.status),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (angle != null)
              Text(
                '關節角度: ${angle.toStringAsFixed(0)}°',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummarySheet extends StatefulWidget {
  const _SummarySheet({required this.summary, required this.coachingService});

  final WorkoutSummary summary;
  final CoachingService coachingService;

  @override
  State<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<_SummarySheet> {
  late final Future<String> _adviceFuture =
      widget.coachingService.getAdvice(widget.summary);

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${summary.exercise} 訓練建議',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '共 ${summary.totalReps} 下 · 達標 ${summary.goodReps} · '
              '太淺 ${summary.tooShallowReps} · 太深 ${summary.tooDeepReps}',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FutureBuilder<String>(
              future: _adviceFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    ),
                  );
                }
                return Text(
                  snapshot.data!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.5,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
