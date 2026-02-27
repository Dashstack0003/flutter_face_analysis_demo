import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:uuid/uuid.dart';

import 'tflite_service.dart';

class DetectionResult {
  final List<DetectedFace> faces;

  bool get hasFaces => faces.isNotEmpty;

  const DetectionResult({required this.faces});
}

class DetectedFace {
  final String faceId;
  final String croppedPath;
  final Rect boundingBox;
  final double confidence;
  final double bboxX;
  final double bboxY;
  final double bboxWidth;
  final double bboxHeight;
  final OffsetBase leftEye;
  final OffsetBase rightEye;
  final img.Image croppedFace;

  const DetectedFace({
    required this.faceId,
    required this.croppedPath,
    required this.boundingBox,
    required this.confidence,
    required this.bboxX,
    required this.bboxY,
    required this.bboxWidth,
    required this.bboxHeight,
    required this.leftEye,
    required this.rightEye,
    required this.croppedFace,
  });
}

class FaceDetectionService {
  final TFLiteService _tfliteService;
  final _uuid = const Uuid();

  static const double confidenceThreshold = 0.7;

  FaceDetectionService({required TFLiteService tfliteService})
    : _tfliteService = tfliteService;

  // ─────────────────────────────────────────
  // MAIN METHOD
  // ─────────────────────────────────────────

  Future<DetectionResult> detectFaces(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        print("[FaceDetection] Image file not found");
        return const DetectionResult(faces: []);
      }

      final bytes = await file.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        print("[FaceDetection] Failed to decode image");
        return const DetectionResult(faces: []);
      }

      print(
        "[FaceDetection] Image loaded: ${originalImage.width}x${originalImage.height}",
      );

      final input = _preprocessImage(originalImage);

      const int n = 2304;
      final outputBoxes = List.filled(1 * n * 16, 0.0).reshape([1, n, 16]);
      final outputScores = List.filled(1 * n * 1, 0.0).reshape([1, n, 1]);

      final interpreter = _tfliteService.blazeFaceInterpreter;

      interpreter.runForMultipleInputs(
        [
          input.reshape([1, 192, 192, 3]),
        ],
        {0: outputBoxes, 1: outputScores},
      );

      print("[FaceDetection] BlazeFace inference completed");

      final anchors = _generateAnchors();
      final detectedFaces = <DetectedFace>[];
      final cropsDir = await _getCropsDirectory();

      final imageWidth = originalImage.width.toDouble();
      final imageHeight = originalImage.height.toDouble();

      for (int i = 0; i < n; i++) {
        final score = _sigmoid(outputScores[0][i][0]);
        if (score < confidenceThreshold) continue;

        print("[FaceDetection] Face detected with confidence: $score");

        final anchor = anchors[i];

        final dx = outputBoxes[0][i][0];
        final dy = outputBoxes[0][i][1];
        final dw = outputBoxes[0][i][2];
        final dh = outputBoxes[0][i][3];

        // Decode bounding box
        final cx = dx / 192 + anchor[0];
        final cy = dy / 192 + anchor[1];
        final w = dw / 192;
        final h = dh / 192;

        final xmin = (cx - w / 2) * imageWidth;
        final ymin = (cy - h / 2) * imageHeight;
        final width = w * imageWidth;
        final height = h * imageHeight;

        if (width <= 0 || height <= 0) continue;

        // Decode eye landmarks
        final leftEyeX = (outputBoxes[0][i][4] / 192 + anchor[0]) * imageWidth;
        final leftEyeY = (outputBoxes[0][i][5] / 192 + anchor[1]) * imageHeight;

        final rightEyeX = (outputBoxes[0][i][6] / 192 + anchor[0]) * imageWidth;
        final rightEyeY =
            (outputBoxes[0][i][7] / 192 + anchor[1]) * imageHeight;

        // Compute alignment angle
        final dxEye = rightEyeX - leftEyeX;
        final dyEye = rightEyeY - leftEyeY;

        final angleRad = math.atan2(dyEye, dxEye);
        final angleDeg = angleRad * 180 / math.pi;

        print("[FaceDetection] Rotation angle: $angleDeg");

        final workingImage = originalImage;
        // Rotate entire image
        final rotatedImage = img.copyRotate(
          workingImage,
          angle: -safeAngle(angleDeg),
        );

        // Rotate bounding box center
        final imageCenter = Offset(imageWidth / 2, imageHeight / 2);
        final boxCenter = Offset(xmin + width / 2, ymin + height / 2);

        final rotatedCenter = rotatePoint(boxCenter, imageCenter, -angleRad);

        // Add margin
        const margin = 0.2;

        final expandedW = width * (1 + margin);
        final expandedH = height * (1 + margin);

        // Recalculate crop center after margin
        final cropCenterX = rotatedCenter.dx;
        final cropCenterY = rotatedCenter.dy;

        final cropX = (cropCenterX - expandedW / 2)
            .clamp(0.0, rotatedImage.width - 1)
            .toInt();

        final cropY = (cropCenterY - expandedH / 2)
            .clamp(0.0, rotatedImage.height - 1)
            .toInt();

        final cropW = expandedW.clamp(1.0, rotatedImage.width - cropX).toInt();

        final cropH = expandedH.clamp(1.0, rotatedImage.height - cropY).toInt();

        final cropped = img.copyCrop(
          rotatedImage,
          x: cropX,
          y: cropY,
          width: cropW,
          height: cropH,
        );

        // Resize aligned face to FaceNet size
        final alignedFace = img.copyResize(cropped, width: 160, height: 160);

        final faceId = _uuid.v4();
        final filePath = '${cropsDir.path}/$faceId.jpg';

        await File(filePath).writeAsBytes(img.encodeJpg(alignedFace));

        print("[FaceDetection] Face saved: $filePath");

        detectedFaces.add(
          DetectedFace(
            faceId: faceId,
            croppedPath: filePath,
            confidence: score,
            bboxX: xmin,
            bboxY: ymin,
            bboxWidth: width,
            bboxHeight: height,
            boundingBox: Rect.fromLTWH(xmin, ymin, width, height),
            leftEye: Offset(leftEyeX, leftEyeY),
            rightEye: Offset(rightEyeX, rightEyeY),
            croppedFace: alignedFace,
          ),
        );
      }

      print("[FaceDetection] Total faces detected: ${detectedFaces.length}");

      return DetectionResult(faces: detectedFaces);
    } catch (e) {
      print("[FaceDetection] Error: $e");
      return const DetectionResult(faces: []);
    }
  }

  double safeAngle(double angle) {
    if (angle.isNaN || angle.isInfinite) return 0.0;
    return angle;
  }

  // ─────────────────────────────────────────
  // IMAGE PREPROCESSING
  // ─────────────────────────────────────────

  Float32List _preprocessImage(img.Image image) {
    final resized = img.copyResize(
      image,
      width: 192,
      height: 192,
      interpolation: img.Interpolation.linear,
    );

    final input = Float32List(1 * 192 * 192 * 3);
    int index = 0;

    for (int y = 0; y < 192; y++) {
      for (int x = 0; x < 192; x++) {
        final pixel = resized.getPixel(x, y);

        // BlazeFace expects [-1, 1]
        input[index++] = (pixel.r - 127.5) / 127.5;
        input[index++] = (pixel.g - 127.5) / 127.5;
        input[index++] = (pixel.b - 127.5) / 127.5;
      }
    }

    return input;
  }

  Future<Directory> _getCropsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cropsDir = Directory('${appDir.path}/face_crops');

    if (!await cropsDir.exists()) {
      await cropsDir.create(recursive: true);
    }

    return cropsDir;
  }

  double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

  List<List<double>> _generateAnchors() {
    const int inputSize = 192;
    const int stride = 4;

    final int gridSize = inputSize ~/ stride; // 48
    final anchors = <List<double>>[];

    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        final cx = (col + 0.5) / gridSize;
        final cy = (row + 0.5) / gridSize;
        anchors.add([cx, cy]);
      }
    }

    return anchors; // 48 x 48 = 2304 anchors
  }

  Offset rotatePoint(Offset point, Offset center, double angleRad) {
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);

    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;

    final newX = dx * cosA - dy * sinA + center.dx;
    final newY = dx * sinA + dy * cosA + center.dy;

    return Offset(newX, newY);
  }
}
