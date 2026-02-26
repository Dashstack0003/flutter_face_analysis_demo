import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Manages loading, caching, and disposing of TFLite model interpreters.
///
/// Two models are used:
/// - **BlazeFace Full-Range Sparse** (`face_detection_full_range_sparse.tflite`): detects face bounding boxes (192×192, 2304 anchors)
/// - **MobileFaceNet 512D** (`mobilefacenet_512d.tflite`): extracts 512D face embeddings (ArcFace-trained)
///
/// Call [initialize] once at app startup (in main.dart or FaceBloc init).
/// Call [dispose] when the app is terminated or models are no longer needed.
class TFLiteService {
  // ─────────────────────────────────────────
  // Asset paths — must match pubspec.yaml
  // ─────────────────────────────────────────
  static const String _blazeFacePath     = 'assets/models/face_detection_full_range_sparse.tflite';
  static const String _mobileFaceNetPath = 'assets/models/facenet_512_new.tflite';

  // ─────────────────────────────────────────
  // Model input sizes
  // ─────────────────────────────────────────

  /// BlazeFace Full-Range expects a 192×192 RGB input
  static const int blazeFaceInputSize = 192;

  /// MobileFaceNet expects a 160×160 RGB input
  static const int mobileFaceNetInputSize = 160;

  /// MobileFaceNet 512D outputs a 512-dimensional embedding vector
  static const int embeddingSize = 512;

  /// BlazeFace Full-Range Sparse produces 2304 anchors (48×48 grid, 1 anchor/cell, stride=4)
  static const int numAnchors = 2304;

  // ─────────────────────────────────────────
  // Interpreter instances
  // ─────────────────────────────────────────
  Interpreter? _blazeFaceInterpreter;
  Interpreter? _mobileFaceNetInterpreter;

  bool _isInitialized = false;

  /// Returns true if both models are loaded and ready
  bool get isInitialized => _isInitialized;

  // ─────────────────────────────────────────
  // Initialization
  // ─────────────────────────────────────────

  /// Loads both TFLite models into memory.
  ///
  /// Uses [InterpreterOptions] with 2 threads for optimal mobile performance.
  /// Safe to call multiple times — will skip if already initialized.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final options = InterpreterOptions()..threads = 2;

      // Load BlazeFace
      _blazeFaceInterpreter = await _loadModel(
        _blazeFacePath,
        options,
        'BlazeFace',
      );

      // Load MobileFaceNet
      _mobileFaceNetInterpreter = await _loadModel(
        _mobileFaceNetPath,
        options,
        'MobileFaceNet',
      );

      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }

  /// Internal helper to load a single model from assets.
  Future<Interpreter> _loadModel(
    String assetPath,
    InterpreterOptions options,
    String modelName,
  ) async {
    try {
      // Load raw bytes from assets
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();

      final interpreter = Interpreter.fromBuffer(bytes, options: options);
      return interpreter;
    } catch (e) {
      throw Exception('Failed to load $modelName from $assetPath: $e');
    }
  }

  // ─────────────────────────────────────────
  // Accessor: BlazeFace
  // ─────────────────────────────────────────

  /// Returns the BlazeFace interpreter.
  /// Throws if [initialize] has not been called.
  Interpreter get blazeFaceInterpreter {
    _assertInitialized('blazeFaceInterpreter');
    return _blazeFaceInterpreter!;
  }

  // ─────────────────────────────────────────
  // Accessor: MobileFaceNet
  // ─────────────────────────────────────────

  /// Returns the MobileFaceNet interpreter.
  /// Throws if [initialize] has not been called.
  Interpreter get mobileFaceNetInterpreter {
    _assertInitialized('mobileFaceNetInterpreter');
    return _mobileFaceNetInterpreter!;
  }

  // ─────────────────────────────────────────
  // Input/output shape helpers
  // ─────────────────────────────────────────

  /// Returns the input tensor shape for BlazeFace Full-Range: [1, 192, 192, 3]
  List<int> get blazeFaceInputShape =>
      blazeFaceInterpreter.getInputTensor(0).shape;

  /// Returns the input tensor shape for MobileFaceNet: [1, 112, 112, 3]
  List<int> get mobileFaceNetInputShape =>
      mobileFaceNetInterpreter.getInputTensor(0).shape;

  /// Prints all tensor shapes for both models — useful for debugging
  void debugPrintShapes() {
    if (!_isInitialized) {
      return;
    }

    final blazeInputs = blazeFaceInterpreter.getInputTensors();
    final blazeOutputs = blazeFaceInterpreter.getOutputTensors();

    for (int i = 0; i < blazeInputs.length; i++) {
      final t = blazeInputs[i];
      print('[TFLiteService] BlazeFace input[$i]: shape=${t.shape}, type=${t.type}');
    }
    for (int i = 0; i < blazeOutputs.length; i++) {
      final t = blazeOutputs[i];
      print('[TFLiteService] BlazeFace output[$i]: shape=${t.shape}, type=${t.type}');
    }

    final faceNetInputs = mobileFaceNetInterpreter.getInputTensors();
    final faceNetOutputs = mobileFaceNetInterpreter.getOutputTensors();

    for (int i = 0; i < faceNetInputs.length; i++) {
      final t = faceNetInputs[i];
      print('[TFLiteService] MobileFaceNet input[$i]: shape=${t.shape}, type=${t.type}');
    }
    for (int i = 0; i < faceNetOutputs.length; i++) {
      final t = faceNetOutputs[i];
      print('[TFLiteService] MobileFaceNet output[$i]: shape=${t.shape}, type=${t.type}');
    }

    final inputShape = blazeFaceInterpreter.getInputTensor(0).shape;
    final outputShape = blazeFaceInterpreter.getOutputTensor(0).shape;

    print("Input Shape: $inputShape");
    print("Output Shape: $outputShape");
  }

  // ─────────────────────────────────────────
  // Dispose
  // ─────────────────────────────────────────

  /// Releases both interpreters from memory.
  /// Should be called when the app is terminating or models are no longer needed.
  void dispose() {
    _blazeFaceInterpreter?.close();
    _mobileFaceNetInterpreter?.close();
    _blazeFaceInterpreter = null;
    _mobileFaceNetInterpreter = null;
    _isInitialized = false;
  }

  // ─────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────

  void _assertInitialized(String caller) {
    if (!_isInitialized) {
      throw StateError(
        'TFLiteService not initialized. '
        'Call TFLiteService.initialize() before accessing $caller.',
      );
    }
  }
}
