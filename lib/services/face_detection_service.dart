import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:uuid/uuid.dart';
import 'tflite_service.dart';

/// Represents a single raw detection from BlazeFace before filtering.
class RawDetection {
  final double x; // left edge, normalized 0–1
  final double y; // top edge, normalized 0–1
  final double width; // normalized 0–1
  final double height; // normalized 0–1
  final double score; // confidence 0–1

  const RawDetection({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.score,
  });
}

/// Result of processing one image through the detection pipeline.
class DetectionResult {
  /// Each entry: cropped face saved to disk + its bbox + confidence
  final List<DetectedFace> faces;

  /// Whether any faces were found
  bool get hasFaces => faces.isNotEmpty;

  const DetectionResult({required this.faces});
}

/// A single detected face with its metadata.
class DetectedFace {
  final String faceId; // fresh UUID for this face
  final String croppedPath; // absolute path to saved face crop
  final double bboxX;
  final double bboxY;
  final double bboxWidth;
  final double bboxHeight;
  final double confidence;

  const DetectedFace({
    required this.faceId,
    required this.croppedPath,
    required this.bboxX,
    required this.bboxY,
    required this.bboxWidth,
    required this.bboxHeight,
    required this.confidence,
  });
}

/// Runs BlazeFace Full-Range Sparse detection on a given image file, then:
/// 1. Filters detections by confidence threshold
/// 2. Applies Non-Maximum Suppression (NMS) to remove overlapping boxes
/// 3. Crops each detected face from the original image
/// 4. Saves each crop to app documents directory
/// 5. Returns [DetectionResult] with all found faces
class FaceDetectionService {
  final TFLiteService _tfliteService;
  final _uuid = const Uuid();

  /// Minimum confidence to keep a detection (0.0–1.0)
  static const double confidenceThreshold = 0.7;

  /// IoU threshold for Non-Maximum Suppression
  static const double nmsIouThreshold = 0.3;

  /// Padding added around the bounding box when cropping (fraction of bbox size)
  static const double cropPadding = 0.4;

  FaceDetectionService({required TFLiteService tfliteService})
    : _tfliteService = tfliteService;

  // ─────────────────────────────────────────
  // Main entry point
  // ─────────────────────────────────────────

  /// Detects all faces in [imagePath] and saves crops to disk.
  ///
  /// Returns [DetectionResult] with one [DetectedFace] per detected face.
  /// Returns empty result if no faces found or on error.
  Future<DetectionResult> detectFaces(String imagePath) async {
    try {
      // Step 1: Load and decode the original image
      final file = File(imagePath);
      if (!await file.exists()) {
        return const DetectionResult(faces: []);
      }

      final bytes = await file.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        return const DetectionResult(faces: []);
      }

      // Step 2: Prepare model input (resize to 192×192, normalize)
      final inputTensor = _preprocessImage(originalImage);

      // Step 3: Run BlazeFace inference
      final rawDetections = _runBlazeFace(inputTensor);

      // Step 4: Filter by confidence + apply NMS
      final filtered = _filterDetections(rawDetections);

      if (filtered.isEmpty) {
        return const DetectionResult(faces: []);
      }

      // Step 5: Crop each face from original image and save to disk
      final cropsDir = await _getCropsDirectory();
      final detectedFaces = <DetectedFace>[];

      for (final detection in filtered) {
        final faceId = _uuid.v4();
        final cropPath = await _cropAndSaveFace(
          originalImage: originalImage,
          detection: detection,
          faceId: faceId,
          cropsDir: cropsDir,
        );

        if (cropPath != null) {
          detectedFaces.add(
            DetectedFace(
              faceId: faceId,
              croppedPath: cropPath,
              bboxX: detection.x,
              bboxY: detection.y,
              bboxWidth: detection.width,
              bboxHeight: detection.height,
              confidence: detection.score,
            ),
          );
        }
      }

      return DetectionResult(faces: detectedFaces);
    } catch (e) {
      // Return empty result rather than crashing — image may be corrupt
      return const DetectionResult(faces: []);
    }
  }

  // ─────────────────────────────────────────
  // Step 2: Preprocess image for BlazeFace
  // ─────────────────────────────────────────

  /// Resizes the image to 192×192 and normalizes pixel values to [-1, 1].
  /// Output shape: [1, 192, 192, 3] as Float32List.
  Float32List _preprocessImage(img.Image originalImage) {
    final inputSize = TFLiteService.blazeFaceInputSize;

    // Resize to model input size
    final resized = img.copyResize(
      originalImage,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    // Flatten to [1, 192, 192, 3] normalized Float32
    final input = Float32List(1 * inputSize * inputSize * 3);
    int pixelIndex = 0;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        // Normalize from [0, 255] to [-1.0, 1.0]
        input[pixelIndex++] = pixel.r / 255.0;
        input[pixelIndex++] = pixel.g / 255.0;
        input[pixelIndex++] = pixel.b / 255.0;
      }
    }

    return input;
  }

  // ─────────────────────────────────────────
  // Step 3: Run BlazeFace inference
  // ─────────────────────────────────────────

  /// Runs the BlazeFace Full-Range interpreter and parses raw output tensors.
  ///
  /// BlazeFace Full-Range Sparse outputs (reverse_output_order=true):
  ///   - output[0]: [1, 2304, 1]  — classification scores (logits)  ← index 0 is SCORES
  ///   - output[1]: [1, 2304, 16] — box regressors (cx, cy, w, h + 6 keypoints×2)
  ///
  /// Anchor-based decoding is applied to get absolute bbox coordinates.
  List<RawDetection> _runBlazeFace(Float32List inputData) {
    final interpreter = _tfliteService.blazeFaceInterpreter;
    final inputShape = [
      1,
      TFLiteService.blazeFaceInputSize,
      TFLiteService.blazeFaceInputSize,
      3,
    ];
    final input = inputData.reshape(inputShape);

    final n = TFLiteService.numAnchors; // 2304

    // Full-range model: reverse_output_order=true
    // output[0] = boxes  [1, 2304, 16]
    // output[1] = scores [1, 2304, 1]
    final outputBoxes = List.filled(1 * n * 16, 0.0).reshape([1, n, 16]);
    final outputScores = List.filled(1 * n * 1, 0.0).reshape([1, n, 1]);

    // Swapping the indices to match the model's output signature
    final outputs = {0: outputBoxes, 1: outputScores};

    interpreter.runForMultipleInputs([input], outputs);

    return _decodeDetections(outputBoxes.cast(), outputScores.cast());
  }

  /// Decodes BlazeFace anchor-based output into normalized bounding boxes.
  ///
  /// BlazeFace uses pre-defined anchors. Each regressor encodes offsets
  /// relative to its anchor center. We apply sigmoid to scores.
  List<RawDetection> _decodeDetections(
    List<dynamic> boxes,
    List<dynamic> scores,
  ) {
    final detections = <RawDetection>[];
    final anchors = _generateAnchors();

    for (int i = 0; i < TFLiteService.numAnchors; i++) {
      // 1. Get Score (Apply sigmoid only if raw logits are returned)
      double rawScore = scores[0][i][0];
      double score = _sigmoid(rawScore);

      // Lower threshold for debugging to see if ANY detections exist
      if (score < 0.5) continue;

      // 2. Decode Box
      // BlazeFace output: [dx, dy, dw, dh, ...] relative to anchor
      final anchor = anchors[i];
      final cxRaw = boxes[0][i][0];
      final cyRaw = boxes[0][i][1];
      final wRaw = boxes[0][i][2];
      final hRaw = boxes[0][i][3];

      // Map to normalized 0-1 coordinates
      final cx = cxRaw / TFLiteService.blazeFaceInputSize + anchor[0];
      final cy = cyRaw / TFLiteService.blazeFaceInputSize + anchor[1];
      final w = wRaw / TFLiteService.blazeFaceInputSize;
      final h = hRaw / TFLiteService.blazeFaceInputSize;

      final x = (cx - w / 2).clamp(0.0, 1.0);
      final y = (cy - h / 2).clamp(0.0, 1.0);

      detections.add(
        RawDetection(
          x: x,
          y: y,
          width: w.clamp(0.0, 1.0 - x),
          height: h.clamp(0.0, 1.0 - y),
          score: score,
        ),
      );
    }
    return detections;
  }

  /// Generates BlazeFace Full-Range Sparse anchors.
  ///
  /// Full-Range Sparse uses a single stride of 4 on a 192×192 input:
  /// - stride 4 → feature map 48×48 → 1 anchor/cell (interpolated_scale_aspect_ratio=0.0)
  /// - Total = 48 × 48 × 1 = 2304 anchors
  List<List<double>> _generateAnchors() {
    const int inputSize = TFLiteService.blazeFaceInputSize; // 192
    const int stride = 4;
    const int gridSize = inputSize ~/ stride; // 48

    final anchors = <List<double>>[];

    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        // 1 anchor per cell — center in normalized [0, 1] space
        final cx = (col + 0.5) / gridSize;
        final cy = (row + 0.5) / gridSize;
        anchors.add([cx, cy]);
      }
    }

    return anchors; // length == 2304
  }

  // ─────────────────────────────────────────
  // Step 4: Filter + NMS
  // ─────────────────────────────────────────

  /// Filters detections by confidence and applies Non-Maximum Suppression.
  List<RawDetection> _filterDetections(List<RawDetection> detections) {
    if (detections.isEmpty) return [];

    // Sort by score descending
    final sorted = List<RawDetection>.from(detections)
      ..sort((a, b) => b.score.compareTo(a.score));

    return _applyNMS(sorted);
  }

  /// Greedy NMS: keep the highest scoring detection, remove overlapping ones.
  List<RawDetection> _applyNMS(List<RawDetection> sorted) {
    final kept = <RawDetection>[];

    for (final candidate in sorted) {
      bool suppress = false;

      for (final kept_ in kept) {
        final iou = _computeIoU(candidate, kept_);
        if (iou > nmsIouThreshold) {
          suppress = true;
          break;
        }
      }

      if (!suppress) {
        kept.add(candidate);
      }
    }

    return kept;
  }

  /// Computes Intersection over Union for two detections.
  double _computeIoU(RawDetection a, RawDetection b) {
    final ax1 = a.x;
    final ay1 = a.y;
    final ax2 = a.x + a.width;
    final ay2 = a.y + a.height;

    final bx1 = b.x;
    final by1 = b.y;
    final bx2 = b.x + b.width;
    final by2 = b.y + b.height;

    final interX1 = math.max(ax1, bx1);
    final interY1 = math.max(ay1, by1);
    final interX2 = math.min(ax2, bx2);
    final interY2 = math.min(ay2, by2);

    final interW = math.max(0.0, interX2 - interX1);
    final interH = math.max(0.0, interY2 - interY1);
    final interArea = interW * interH;

    final aArea = a.width * a.height;
    final bArea = b.width * b.height;
    final unionArea = aArea + bArea - interArea;

    return unionArea == 0 ? 0.0 : interArea / unionArea;
  }

  // ─────────────────────────────────────────
  // Step 5: Crop + save faces
  // ─────────────────────────────────────────

  /// Crops the detected face region from the original image with padding,
  /// resizes to 112×112 (MobileFaceNet input size), and saves as JPEG.
  Future<String?> _cropAndSaveFace({
    required img.Image originalImage,
    required RawDetection detection,
    required String faceId,
    required Directory cropsDir,
  }) async {
    try {
      final imgW = originalImage.width.toDouble();
      final imgH = originalImage.height.toDouble();

      // Apply padding around bounding box
      final padW = detection.width * cropPadding;
      final padH = detection.height * cropPadding;

      final cropX = ((detection.x - padW) * imgW).clamp(0.0, imgW - 1).toInt();
      final cropY = ((detection.y - padH) * imgH).clamp(0.0, imgH - 1).toInt();
      final cropW = ((detection.width + 2 * padW) * imgW)
          .clamp(1.0, imgW - cropX)
          .toInt();
      final cropH = ((detection.height + 2 * padH) * imgH)
          .clamp(1.0, imgH - cropY)
          .toInt();

      // Crop from original image
      final cropped = img.copyCrop(
        originalImage,
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
      );

      // Resize to MobileFaceNet input size (112×112)
      final resized = img.copyResize(
        cropped,
        width: TFLiteService.mobileFaceNetInputSize,
        height: TFLiteService.mobileFaceNetInputSize,
        interpolation: img.Interpolation.linear,
      );

      // Save to disk as JPEG
      final filePath = '${cropsDir.path}/$faceId.jpg';
      final jpegBytes = img.encodeJpg(resized, quality: 90);
      await File(filePath).writeAsBytes(jpegBytes);

      return filePath;
    } catch (e) {
      return null;
    }
  }

  // ─────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────

  /// Returns (or creates) the directory where face crops are saved.
  Future<Directory> _getCropsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cropsDir = Directory('${appDir.path}/face_crops');
    if (!await cropsDir.exists()) {
      await cropsDir.create(recursive: true);
    }
    return cropsDir;
  }

  double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));
}
