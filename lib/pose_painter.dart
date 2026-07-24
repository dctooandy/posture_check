import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Draws detected pose landmarks and skeleton connections over the camera preview.
class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.cameraLensDirection,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;

  static const _connections = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  static const _lineColor = Color(0xFF00E5FF);
  static const _pointRingColor = Color(0xFF7C4DFF);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = _lineColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final pointFillPaint = Paint()..color = Colors.white;
    final pointRingPaint = Paint()
      ..color = _pointRingColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final pose in poses) {
      for (final connection in _connections) {
        final a = pose.landmarks[connection[0]];
        final b = pose.landmarks[connection[1]];
        if (a != null && b != null) {
          canvas.drawLine(
            _translatePoint(Offset(a.x, a.y), size),
            _translatePoint(Offset(b.x, b.y), size),
            linePaint,
          );
        }
      }
      for (final landmark in pose.landmarks.values) {
        final center = _translatePoint(Offset(landmark.x, landmark.y), size);
        canvas.drawCircle(center, 3, pointFillPaint);
        canvas.drawCircle(center, 5, pointRingPaint);
      }
    }
  }

  Offset _translatePoint(Offset point, Size canvasSize) {
    final rotatedImageSize =
        (rotation == InputImageRotation.rotation90deg ||
                rotation == InputImageRotation.rotation270deg)
            ? Size(imageSize.height, imageSize.width)
            : imageSize;

    final scaleX = canvasSize.width / rotatedImageSize.width;
    final scaleY = canvasSize.height / rotatedImageSize.height;

    double x = point.dx * scaleX;
    final y = point.dy * scaleY;

    if (cameraLensDirection == CameraLensDirection.front) {
      x = canvasSize.width - x;
    }

    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.poses != poses ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation;
  }
}
