import 'dart:io';
import 'dart:math' as math;
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'tflite_service.dart';

/// Extracts a 512-dimensional embedding vector from a cropped face image
/// using the MobileFaceNet TFLite model.
///
/// The embedding uniquely represents facial features and is used downstream
/// by [ClusteringService] to group similar faces together.
///
/// Key details:
/// - Input: 160×160 RGB face crop (normalized to [-1, 1])
/// - Output: 512D float32 vector, L2-normalized to unit length
/// - Distance metric: Euclidean distance on L2-normalized vectors
///   (equivalent to cosine similarity)
class EmbeddingService {
  final TFLiteService _tfliteService;

  EmbeddingService({required TFLiteService tfliteService})
    : _tfliteService = tfliteService;

  // ─────────────────────────────────────────
  // Main entry point
  // ─────────────────────────────────────────

  /// Extracts a 512D embedding from the face image at [croppedFacePath].
  ///
  /// Returns a L2-normalized [List<double>] of length 512.
  /// Returns null if the file does not exist or inference fails.
  Future<List<double>?> extractEmbedding(String croppedFacePath) async {
    try {
      // Step 1: Load cropped face image from disk
      final file = File(croppedFacePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final faceImage = img.decodeImage(bytes);
      if (faceImage == null) return null;

      // Step 2: Preprocess for MobileFaceNet
      final inputTensor = _preprocessFace(faceImage);

      // Step 3: Run inference
      final rawEmbedding = _runMobileFaceNet(inputTensor);

      // Step 4: L2-normalize the output
      return _l2Normalize(rawEmbedding);
    } catch (e) {
      print("[extractEmbedding] Error : ${e.toString()}");
      return null;
    }
  }

  /// Batch version — processes multiple face paths and returns
  /// a map of [croppedFacePath] → embedding (or null if failed).
  Future<Map<String, List<double>?>> extractEmbeddingsBatch(
    List<String> croppedFacePaths,
  ) async {
    final results = <String, List<double>?>{};

    for (final path in croppedFacePaths) {
      results[path] = await extractEmbedding(path);
    }

    return results;
  }

  // ─────────────────────────────────────────
  // Step 2: Preprocessing
  // ─────────────────────────────────────────

  /// Resizes the face to 160×160 and normalizes to [-1.0, 1.0].
  ///
  /// MobileFaceNet expects:
  ///   - Input shape: [1, 160, 160, 3]
  ///   - Pixel values: (value - 127.5) / 128.0
  Float32List _preprocessFace(img.Image faceImage) {
    const inputSize = TFLiteService.mobileFaceNetInputSize;

    // Ensure exact 112×112 size
    final resized = img.copyResize(
      faceImage,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    final input = Float32List(1 * inputSize * inputSize * 3);
    int idx = 0;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        // MobileFaceNet normalization: (x - 127.5) / 128
        input[idx++] = (pixel.r - 127.5) / 128.0;
        input[idx++] = (pixel.g - 127.5) / 128.0;
        input[idx++] = (pixel.b - 127.5) / 128.0;
      }
    }

    return input;
  }

  // ─────────────────────────────────────────
  // Step 3: Run MobileFaceNet inference
  // ─────────────────────────────────────────

  /// Runs the MobileFaceNet interpreter on the preprocessed input.
  ///
  /// MobileFaceNet output: [1, 512] — a single 512D embedding vector.
  List<double> _runMobileFaceNet(Float32List inputData) {
    final interpreter = _tfliteService.mobileFaceNetInterpreter;

    const inputSize = TFLiteService.mobileFaceNetInputSize;

    // Read the actual output size from the model tensor at runtime.
    // This handles both 192D and 512D MobileFaceNet variants without
    // hardcoding a size that breaks hasEmbedding checks elsewhere.
    final outputShape = interpreter.getOutputTensor(0).shape;
    final actualEmbeddingSize = outputShape.last; // e.g. 192 or 512

    // Reshape input to [1, 160, 160, 3]
    final input = inputData.reshape([1, inputSize, inputSize, 3]);

    // Build output buffer matching the model's actual output shape
    final output = List.filled(
      actualEmbeddingSize,
      0.0,
    ).reshape([1, actualEmbeddingSize]);

    interpreter.run(input, output);

    // Cast inner elements to double safely
    final List<dynamic> firstBatch = output[0];
    return _normalize(firstBatch.cast());
    // return firstBatch.map((e) => (e as num).toDouble()).toList();
  }

  // ─────────────────────────────────────────
  // Step 4: L2 Normalization
  // ─────────────────────────────────────────

  /// Normalizes the embedding vector to unit length (L2 norm = 1.0).
  ///
  /// After normalization, Euclidean distance between two embeddings is
  /// equivalent to cosine distance, which is more stable for face comparison.
  ///
  /// Formula: normalized[i] = raw[i] / sqrt(sum(raw[j]^2))
  List<double> _l2Normalize(List<double> embedding) {
    double sumSquares = 0.0;
    for (final v in embedding) {
      sumSquares += v * v;
    }

    final norm = math.sqrt(sumSquares);

    if (norm == 0.0) {
      // Degenerate case — return zero vector rather than divide by zero
      return List<double>.filled(embedding.length, 0.0);
    }

    return embedding.map((v) => v / norm).toList();
  }

  // ─────────────────────────────────────────
  // Utility: Compute distance between two embeddings
  // ─────────────────────────────────────────

  /// Computes the Euclidean distance between two L2-normalized embeddings.
  ///
  /// Interpretation guide:
  ///   - distance < 0.6  → likely same person
  ///   - distance < 1.0  → possibly same person
  ///   - distance >= 1.0 → likely different people
  ///
  /// Both embeddings must have the same length (512).
  static double euclideanDistance(List<double> a, List<double> b) {
    if (a.length != b.length) return double.infinity;

    double sumSquares = 0.0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sumSquares += diff * diff;
    }
    return math.sqrt(sumSquares);
  }

  /// Computes cosine similarity between two embeddings.
  ///
  /// Returns a value between -1 and 1 (1 = identical, -1 = opposite).
  /// For L2-normalized vectors this equals the dot product.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
    }
    return dotProduct;
  }

  List<double> _normalize(List<double> embedding) {
    double sum = 0.0;

    for (var v in embedding) {
      sum += v * v;
    }

    double norm = sqrt(sum);

    return embedding.map((e) => e / norm).toList();
  }
}
