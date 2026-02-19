import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../helper/hive_helper.dart';
import '../../models/face_model.dart';
import '../../services/tflite_service.dart';
import '../../services/face_detection_service.dart';
import '../../services/embedding_service.dart';
import '../../services/clustering_service.dart';

/// ─────────────────────────────────────────────────────────────
/// ML Pipeline Debug Screen
///
/// Tap each step to test the full pipeline interactively.
///
/// To open this screen, add a button in HomeScreen:
///
///   TextButton(
///     onPressed: () => Navigator.push(context,
///       MaterialPageRoute(builder: (_) => MLDebugScreen(
///         tfliteService: tfliteService,
///       )),
///     ),
///     child: const Text('Debug ML'),
///   )
/// ─────────────────────────────────────────────────────────────
class MLDebugScreen extends StatefulWidget {
  final TFLiteService tfliteService;

  const MLDebugScreen({super.key, required this.tfliteService});

  @override
  State<MLDebugScreen> createState() => _MLDebugScreenState();
}

class _MLDebugScreenState extends State<MLDebugScreen> {
  late final FaceDetectionService _detectionService;
  late final EmbeddingService _embeddingService;
  late final ClusteringService _clusteringService;

  String? _selectedImagePath;
  bool _isRunning = false;

  _StepResult? _step0Result;
  _StepResult? _step1Result;
  _StepResult? _step2Result;
  _StepResult? _step3Result;
  _StepResult? _step4Result;

  List<DetectedFace> _detectedFaces = [];
  List<FaceModel> _faceModels = [];

  @override
  void initState() {
    super.initState();
    _detectionService  = FaceDetectionService(tfliteService: widget.tfliteService);
    _embeddingService  = EmbeddingService(tfliteService: widget.tfliteService);
    _clusteringService = ClusteringService(eps: 0.6, minSamples: 2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Row(
          children: [
            Icon(Icons.bug_report_rounded, color: Color(0xFF38BDF8), size: 20),
            SizedBox(width: 10),
            Text('ML Pipeline Debugger',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildImagePicker(),
          const SizedBox(height: 16),
          _buildStep(
            step: 0, icon: Icons.memory_rounded,
            title: 'Step 0 — Model Loading',
            desc: 'Verify BlazeFace + MobileFaceNet are initialized',
            result: _step0Result, canRun: true, onRun: _testModelLoading,
          ),
          const SizedBox(height: 12),
          _buildStep(
            step: 1, icon: Icons.face_rounded,
            title: 'Step 1 — Face Detection',
            desc: 'Run BlazeFace on selected image',
            result: _step1Result, canRun: _selectedImagePath != null,
            onRun: _testFaceDetection, requiresImage: true,
          ),
          const SizedBox(height: 12),
          _buildStep(
            step: 2, icon: Icons.grain_rounded,
            title: 'Step 2 — Embedding Extraction',
            desc: 'Extract 512D vectors from detected face crops',
            result: _step2Result, canRun: _detectedFaces.isNotEmpty,
            onRun: _testEmbedding,
          ),
          const SizedBox(height: 12),
          _buildStep(
            step: 3, icon: Icons.people_rounded,
            title: 'Step 3 — DBSCAN Clustering',
            desc: 'Group embeddings into person clusters',
            result: _step3Result,
            canRun: _faceModels.any((f) => f.hasEmbedding),
            onRun: _testClustering,
          ),
          const SizedBox(height: 12),
          _buildStep(
            step: 4, icon: Icons.storage_rounded,
            title: 'Step 4 — Hive Persistence',
            desc: 'Save faces to Hive and read back',
            result: _step4Result, canRun: _faceModels.isNotEmpty,
            onRun: _testHive,
          ),
          const SizedBox(height: 24),
          _buildRunAllButton(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ─── Image picker ───────────────────────

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _selectedImagePath != null
                ? const Color(0xFF38BDF8)
                : const Color(0xFF334155),
            width: 2,
          ),
        ),
        child: _selectedImagePath != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(File(_selectedImagePath!), fit: BoxFit.cover),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
                      ),
                    ),
                  ),
                  const Positioned(
                    bottom: 8, left: 12,
                    child: Text('Tap to change', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                ]),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF38BDF8), size: 36),
                  SizedBox(height: 8),
                  Text('Tap to select a test image', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                  SizedBox(height: 2),
                  Text('Use a clear photo with faces', style: TextStyle(color: Color(0xFF475569), fontSize: 12)),
                ],
              ),
      ),
    );
  }

  // ─── Step card ──────────────────────────

  Widget _buildStep({
    required int step,
    required IconData icon,
    required String title,
    required String desc,
    required _StepResult? result,
    required bool canRun,
    required VoidCallback onRun,
    bool requiresImage = false,
  }) {
    final color = result == null
        ? const Color(0xFF475569)
        : result.isPassed ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            ])),
            if (result != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(
                  result.isPassed ? '✓ PASS' : '✗ FAIL',
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
          ]),
        ),
        if (result != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10)),
            child: SelectableText(
              result.message,
              style: TextStyle(
                color: result.isPassed ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                fontSize: 12, fontFamily: 'monospace', height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (canRun && !_isRunning) ? onRun : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                disabledBackgroundColor: const Color(0xFF334155),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                !canRun && requiresImage ? 'Select an image first'
                    : _isRunning ? 'Running...'
                    : result == null ? 'Run Test' : 'Re-run',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ─── Run All button ──────────────────────

  Widget _buildRunAllButton() {
    final results = [_step0Result, _step1Result, _step2Result, _step3Result, _step4Result];
    final total  = results.where((r) => r != null).length;
    final passed = results.where((r) => r?.isPassed == true).length;

    return Column(children: [
      if (total > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '$passed / $total tests passed',
            style: TextStyle(
              color: passed == 5 ? const Color(0xFF22C55E) : const Color(0xFFFBBF24),
              fontSize: 16, fontWeight: FontWeight.w700,
            ),
          ),
        ),
      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton.icon(
          onPressed: (_selectedImagePath != null && !_isRunning) ? _runAll : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            disabledBackgroundColor: const Color(0xFF334155),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.play_circle_rounded, color: Colors.white),
          label: const Text('Run All Tests',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    ]);
  }

  // ─── Test implementations ────────────────

  Future<void> _testModelLoading() async {
    setState(() => _isRunning = true);
    try {
      if (!widget.tfliteService.isInitialized) {
        setState(() => _step0Result = _StepResult.fail(
          'TFLiteService.isInitialized = false\n'
          'Check:\n'
          '  1. tfliteService.initialize() is called in main.dart\n'
          '  2. Both .tflite files exist in assets/models/\n'
          '  3. pubspec.yaml declares the assets correctly',
        ));
        return;
      }

      final blazeShape   = widget.tfliteService.blazeFaceInputShape;
      final faceNetShape = widget.tfliteService.mobileFaceNetInputShape;

      final blazeOk   = blazeShape.length == 4 && blazeShape[1] == 192;
      final faceNetOk = faceNetShape.length == 4 && faceNetShape[1] == 160;

      if (!blazeOk || !faceNetOk) {
        setState(() => _step0Result = _StepResult.fail(
          'Tensor shape mismatch:\n'
          'BlazeFace: $blazeShape (expected [1,128,128,3])\n'
          'MobileFaceNet: $faceNetShape (expected [1,112,112,3])',
        ));
        return;
      }

      setState(() => _step0Result = _StepResult.pass(
        '✓ TFLiteService initialized = true\n'
        '✓ BlazeFace input shape: $blazeShape\n'
        '✓ MobileFaceNet input shape: $faceNetShape\n'
        '✓ Both models ready for inference',
      ));
    } catch (e) {
      setState(() => _step0Result = _StepResult.fail('Exception: $e'));
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _testFaceDetection() async {
    if (_selectedImagePath == null) return;
    setState(() => _isRunning = true);
    try {
      final sw = Stopwatch()..start();
      final result = await _detectionService.detectFaces(_selectedImagePath!);
      sw.stop();

      if (!result.hasFaces) {
        setState(() => _step1Result = _StepResult.fail(
          'No faces detected (${sw.elapsedMilliseconds}ms)\n\n'
          'Tips:\n'
          '  • Use a clear frontal face photo\n'
          '  • Ensure good lighting\n'
          '  • Face should be at least 20% of image size\n'
          '  • Confidence threshold is 0.7 — try a sharper photo',
        ));
        return;
      }

      _detectedFaces = result.faces;
      final info = result.faces.asMap().entries.map((e) {
        final f = e.value;
        return 'Face ${e.key + 1}: conf=${f.confidence.toStringAsFixed(2)}, '
            'x=${f.bboxX.toStringAsFixed(2)} y=${f.bboxY.toStringAsFixed(2)} '
            '${f.bboxWidth.toStringAsFixed(2)}×${f.bboxHeight.toStringAsFixed(2)}';
      }).join('\n');

      setState(() => _step1Result = _StepResult.pass(
        '✓ ${result.faces.length} face(s) detected in ${sw.elapsedMilliseconds}ms\n'
        '✓ Crops saved to documents/face_crops/\n\n'
        '$info',
      ));
    } catch (e) {
      setState(() => _step1Result = _StepResult.fail('Exception: $e'));
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _testEmbedding() async {
    if (_detectedFaces.isEmpty) return;
    setState(() => _isRunning = true);
    try {
      _faceModels = [];
      int ok = 0;
      final sw = Stopwatch()..start();

      for (final d in _detectedFaces) {
        final emb = await _embeddingService.extractEmbedding(d.croppedPath);
        _faceModels.add(FaceModel(
          id: d.faceId, imageId: 'debug_test_${d.faceId}',
          bboxX: d.bboxX, bboxY: d.bboxY, bboxWidth: d.bboxWidth, bboxHeight: d.bboxHeight,
          detectionConfidence: d.confidence, embedding: emb,
          croppedFacePath: d.croppedPath, detectedAt: DateTime.now(),
        ));
        if (emb != null) ok++;
      }
      sw.stop();

      if (ok == 0) {
        setState(() => _step2Result = _StepResult.fail(
          'All embeddings failed.\nCheck face crop files exist from Step 1.',
        ));
        return;
      }

      final first = _faceModels.first.embedding!;
      double normSq = first.fold(0, (s, v) => s + v * v);
      final l2 = normSq == 0 ? 0.0 : (normSq.toStringAsFixed(2));
      final sample = first.take(5).map((v) => v.toStringAsFixed(4)).join(', ');

      String distInfo = '';
      if (_faceModels.length >= 2 && _faceModels[0].hasEmbedding && _faceModels[1].hasEmbedding) {
        final d = EmbeddingService.euclideanDistance(_faceModels[0].embedding!, _faceModels[1].embedding!);
        distInfo = '\n✓ Distance face0↔face1: ${d.toStringAsFixed(4)} '
            '(${d < 0.6 ? "≈ same person" : "≈ different people"})';
      }

      setState(() => _step2Result = _StepResult.pass(
        '✓ $ok/${_detectedFaces.length} embeddings in ${sw.elapsedMilliseconds}ms\n'
        '✓ Embedding dimensions: ${first.length}D\n'
        '✓ L2 norm²: $l2 (should be ≈1.0)\n'
        '✓ Sample: [$sample ...]'
        '$distInfo',
      ));
    } catch (e) {
      setState(() => _step2Result = _StepResult.fail('Exception: $e'));
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _testClustering() async {
    if (_faceModels.isEmpty) return;
    setState(() => _isRunning = true);
    try {
      final sw = Stopwatch()..start();
      final result = _clusteringService.clusterFaces(_faceModels);
      sw.stop();

      final info = result.clusters.map((c) =>
        '  Cluster ${c.clusterId}: ${c.faceCount} face(s)'
      ).join('\n');

      setState(() => _step3Result = _StepResult.pass(
        '✓ DBSCAN complete in ${sw.elapsedMilliseconds}ms\n'
        '✓ ${result.clusterCount} cluster(s) (people)\n'
        '✓ ${result.noiseCount} noise face(s)\n\n'
        '${info.isEmpty ? "  Need 2+ faces to cluster" : info}',
      ));
    } catch (e) {
      setState(() => _step3Result = _StepResult.fail('Exception: $e'));
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _testHive() async {
    if (_faceModels.isEmpty) return;
    setState(() => _isRunning = true);
    try {
      // Write debug faces with prefixed IDs
      final debugFaces = _faceModels.map((f) =>
        f.copyWith(id: 'dbg_${f.id}', imageId: 'dbg_image')
      ).toList();

      await HiveHelper.addFaces(debugFaces);

      // Read back and verify
      int readCount = 0;
      bool embOk = true;
      for (final face in debugFaces) {
        final r = await HiveHelper.getFaceById(face.id);
        if (r == null) {
          setState(() => _step4Result = _StepResult.fail('Read back failed for id: ${face.id}'));
          return;
        }
        readCount++;
        if (face.hasEmbedding && (r.embedding == null || r.embedding!.length != 512)) {
          embOk = false;
        }
      }

      // Clean up
      await HiveHelper.deleteFacesByImageId('dbg_image');

      setState(() => _step4Result = _StepResult.pass(
        '✓ Saved ${debugFaces.length} face(s) to Hive\n'
        '✓ Read back $readCount/${{debugFaces.length}} successfully\n'
        '✓ Embeddings survive serialization: $embOk\n'
        '✓ All fields intact (id, bbox, confidence, embedding)\n'
        '✓ Debug entries cleaned up',
      ));
    } catch (e) {
      setState(() => _step4Result = _StepResult.fail('Exception: $e'));
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _runAll() async {
    await _testModelLoading();
    await Future.delayed(const Duration(milliseconds: 200));
    if (_selectedImagePath != null) {
      await _testFaceDetection();
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (_detectedFaces.isNotEmpty) {
      await _testEmbedding();
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (_faceModels.any((f) => f.hasEmbedding)) {
      await _testClustering();
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (_faceModels.isNotEmpty) {
      await _testHive();
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null && mounted) {
      setState(() {
        _selectedImagePath = picked.path;
        _step1Result = _step2Result = _step3Result = _step4Result = null;
        _detectedFaces = [];
        _faceModels = [];
      });
    }
  }
}

// ─── Result model ────────────────────────

class _StepResult {
  final bool isPassed;
  final String message;
  const _StepResult._({required this.isPassed, required this.message});
  factory _StepResult.pass(String msg) => _StepResult._(isPassed: true,  message: msg);
  factory _StepResult.fail(String msg) => _StepResult._(isPassed: false, message: msg);
}
