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
        return const DetectionResult(faces: []);
      }

      final bytes = await file.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        return const DetectionResult(faces: []);
      }

      final input = _preprocessImage(originalImage);

      final n = 2304;
      final outputBoxes =
      List.filled(1 * n * 16, 0.0).reshape([1, n, 16]);
      final outputScores =
      List.filled(1 * n * 1, 0.0).reshape([1, n, 1]);

      final interpreter = _tfliteService.blazeFaceInterpreter;

      interpreter.runForMultipleInputs(
        [input.reshape([1, 192, 192, 3])],
        {0: outputBoxes, 1: outputScores},
      );

      final anchors = _generateAnchors();
      final detectedFaces = <DetectedFace>[];
      final cropsDir = await _getCropsDirectory();

      final imageWidth = originalImage.width.toDouble();
      final imageHeight = originalImage.height.toDouble();

      for (int i = 0; i < n; i++) {
        final score = _sigmoid(outputScores[0][i][0]);
        if (score < confidenceThreshold) continue;

        final anchor = anchors[i];

        final dx = outputBoxes[0][i][0];
        final dy = outputBoxes[0][i][1];
        final dw = outputBoxes[0][i][2];
        final dh = outputBoxes[0][i][3];

        // Proper anchor decoding
        final cx = dx / 192 + anchor[0];
        final cy = dy / 192 + anchor[1];
        final w = dw / 192;
        final h = dh / 192;

        final xmin = ((cx - w / 2) * imageWidth);
        final ymin = ((cy - h / 2) * imageHeight);
        final width = (w * imageWidth);
        final height = (h * imageHeight);

        if (width <= 0 || height <= 0) continue;

        final cropX = xmin.clamp(0.0, imageWidth - 1).toInt();
        final cropY = ymin.clamp(0.0, imageHeight - 1).toInt();
        final cropW = width.clamp(1.0, imageWidth - cropX).toInt();
        final cropH = height.clamp(1.0, imageHeight - cropY).toInt();

        final cropped = img.copyCrop(
          originalImage,
          x: cropX,
          y: cropY,
          width: cropW,
          height: cropH,
        );

        final resized = img.copyResize(
          cropped,
          width: 160,
          height: 160,
        );

        final faceId = _uuid.v4();
        final filePath = '${cropsDir.path}/$faceId.jpg';

        await File(filePath)
            .writeAsBytes(img.encodeJpg(resized));

        detectedFaces.add(
          DetectedFace(
            faceId: faceId,
            croppedPath: filePath,
            bboxX: xmin,
            bboxY: ymin,
            bboxWidth: width,
            bboxHeight: height,
            confidence: score,
            boundingBox: Rect.fromLTWH(xmin, ymin, width, height),
            leftEye: Offset.zero,
            rightEye: Offset.zero,
            croppedFace: resized,
          ),
        );
      }

      return DetectionResult(faces: detectedFaces);
    } catch (e) {
      return const DetectionResult(faces: []);
    }
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
        input[index++] = (pixel.r - 127.5) / 128.0;
        input[index++] = (pixel.g - 127.5) / 128.0;
        input[index++] = (pixel.b - 127.5) / 128.0;
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
}
