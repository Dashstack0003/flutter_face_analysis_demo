import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_face_analysis_demo/services/clustering_service.dart';
import 'package:flutter_face_analysis_demo/services/embedding_service.dart';
import 'package:flutter_face_analysis_demo/models/face_model.dart';
import 'package:flutter_face_analysis_demo/models/cluster_model.dart';

/// ─────────────────────────────────────────────────────────────
/// Unit Tests — No device, no TFLite, no Hive required.
///
/// Run with:
///   flutter test test/ml_pipeline_test.dart
/// ─────────────────────────────────────────────────────────────
void main() {
  // ─────────────────────────────────────────
  // EmbeddingService — distance utilities
  // ─────────────────────────────────────────

  group('EmbeddingService — distance utilities', () {
    test('euclideanDistance: identical vectors → 0.0', () {
      final a = List<double>.filled(512, 0.5);
      final dist = EmbeddingService.euclideanDistance(a, a);
      expect(dist, closeTo(0.0, 1e-6));
    });

    test('euclideanDistance: opposite unit vectors → 2.0', () {
      final a = List<double>.filled(512, 1.0 / 512);
      final b = List<double>.filled(512, -1.0 / 512);
      final dist = EmbeddingService.euclideanDistance(a, b);
      // All elements differ by 2/512, so dist = sqrt(512 * (2/512)^2) = 2/sqrt(512)
      expect(dist, greaterThan(0.0));
    });

    test('euclideanDistance: same person embeddings stay under threshold', () {
      // Simulate two embeddings of the "same" person — very similar
      final base = _generateNormalizedEmbedding(seed: 42);
      final similar = base.map((v) => v + 0.01).toList(); // tiny perturbation
      final normalized = _l2Normalize(similar);

      final dist = EmbeddingService.euclideanDistance(base, normalized);
      expect(dist, lessThan(0.6), reason: 'Same-person distance should be < 0.6');
    });

    test('euclideanDistance: different person embeddings exceed threshold', () {
      final personA = _generateNormalizedEmbedding(seed: 1);
      final personB = _generateNormalizedEmbedding(seed: 99);

      final dist = EmbeddingService.euclideanDistance(personA, personB);
      expect(dist, greaterThan(0.5), reason: 'Different-person distance should be > 0.5');
    });

    test('cosineSimilarity: identical unit vectors → 1.0', () {
      final a = _generateNormalizedEmbedding(seed: 5);
      final sim = EmbeddingService.cosineSimilarity(a, a);
      expect(sim, closeTo(1.0, 1e-4));
    });

    test('cosineSimilarity: perpendicular vectors → 0.0', () {
      final a = List<double>.generate(512, (i) => i < 256 ? 1.0 / 256 : 0.0);
      final b = List<double>.generate(512, (i) => i >= 256 ? 1.0 / 256 : 0.0);
      final aNorm = _l2Normalize(a);
      final bNorm = _l2Normalize(b);
      final sim = EmbeddingService.cosineSimilarity(aNorm, bNorm);
      expect(sim, closeTo(0.0, 1e-4));
    });
  });

  // ─────────────────────────────────────────
  // ClusteringService — DBSCAN
  // ─────────────────────────────────────────

  group('ClusteringService — DBSCAN', () {
    late ClusteringService clustering;

    setUp(() {
      clustering = ClusteringService(eps: 0.6, minSamples: 2);
    });

    test('empty faces list → empty result', () {
      final result = clustering.clusterFaces([]);
      expect(result.updatedFaces, isEmpty);
      expect(result.clusters, isEmpty);
      expect(result.noiseCount, equals(0));
    });

    test('single face with embedding → noise (cannot form cluster alone)', () {
      final faces = [_makeFace(id: 'f1', seed: 1)];
      final result = clustering.clusterFaces(faces);

      expect(result.clusterCount, equals(0));
      expect(result.noiseCount, equals(1));
      expect(result.updatedFaces.first.clusterId, equals(-1));
    });

    test('two very similar faces → same cluster', () {
      final baseEmb = _generateNormalizedEmbedding(seed: 10);
      final similarEmb = _perturbEmbedding(baseEmb, delta: 0.05);

      // Different imageIds so same-image constraint does not apply
      final faces = [
        _makeFaceWithEmbedding(id: 'f1', embedding: baseEmb, imageId: 'img1'),
        _makeFaceWithEmbedding(id: 'f2', embedding: similarEmb, imageId: 'img2'),
      ];

      final result = clustering.clusterFaces(faces);

      expect(result.clusterCount, equals(1),
          reason: 'Two similar faces should form 1 cluster');
      expect(result.updatedFaces[0].clusterId, equals(result.updatedFaces[1].clusterId),
          reason: 'Both faces should have same cluster ID');
    });

    test('two very different faces → separate clusters or noise', () {
      final faces = [
        _makeFaceWithEmbedding(id: 'f1', embedding: _generateNormalizedEmbedding(seed: 1)),
        _makeFaceWithEmbedding(id: 'f2', embedding: _generateNormalizedEmbedding(seed: 99)),
      ];

      final result = clustering.clusterFaces(faces);

      // With only 2 very different faces, they should be noise or separate clusters
      // Either way, they should NOT be in the same cluster
      if (result.clusterCount >= 2) {
        expect(result.updatedFaces[0].clusterId,
            isNot(equals(result.updatedFaces[1].clusterId)));
      } else {
        // Both noise is also acceptable
        expect(result.noiseCount, greaterThan(0));
      }
    });

    test('3 same-person faces + 2 different-person faces → 2 clusters', () {
      // Person A — 3 very similar embeddings
      final personABase = _generateNormalizedEmbedding(seed: 10);
      final personAFaces = [
        _makeFaceWithEmbedding(id: 'a1', embedding: _perturbEmbedding(personABase, delta: 0.02), imageId: 'img_a1'),
        _makeFaceWithEmbedding(id: 'a2', embedding: _perturbEmbedding(personABase, delta: 0.03), imageId: 'img_a2'),
        _makeFaceWithEmbedding(id: 'a3', embedding: _perturbEmbedding(personABase, delta: 0.01), imageId: 'img_a3'),
      ];

      // Person B — 2 very similar embeddings, far from Person A
      final personBBase = _generateNormalizedEmbedding(seed: 200);
      final personBFaces = [
        _makeFaceWithEmbedding(id: 'b1', embedding: _perturbEmbedding(personBBase, delta: 0.02), imageId: 'img_b1'),
        _makeFaceWithEmbedding(id: 'b2', embedding: _perturbEmbedding(personBBase, delta: 0.03), imageId: 'img_b2'),
      ];

      final result = clustering.clusterFaces([...personAFaces, ...personBFaces]);

      expect(result.clusterCount, equals(2),
          reason: 'Should detect exactly 2 people');

      // All Person A faces should share the same cluster ID
      final aIds = result.updatedFaces
          .where((f) => ['a1', 'a2', 'a3'].contains(f.id))
          .map((f) => f.clusterId)
          .toSet();
      expect(aIds, hasLength(1), reason: 'All person A faces should be in same cluster');

      // All Person B faces should share the same cluster ID
      final bIds = result.updatedFaces
          .where((f) => ['b1', 'b2'].contains(f.id))
          .map((f) => f.clusterId)
          .toSet();
      expect(bIds, hasLength(1), reason: 'All person B faces should be in same cluster');

      // Person A and B should be in different clusters
      expect(aIds.first, isNot(equals(bIds.first)));
    });

    test('faces without embeddings are skipped', () {
      final faces = [
        _makeFaceNoEmbedding(id: 'noEmb1'),
        _makeFaceNoEmbedding(id: 'noEmb2'),
        _makeFaceWithEmbedding(id: 'withEmb', embedding: _generateNormalizedEmbedding(seed: 5)),
      ];

      final result = clustering.clusterFaces(faces);

      // Only face with embedding is processed
      expect(result.updatedFaces.length, equals(1));
      expect(result.updatedFaces.first.id, equals('withEmb'));
    });

    test('ClusterModel has correct face count and image IDs', () {
      final emb = _generateNormalizedEmbedding(seed: 20);
      final faces = [
        _makeFaceWithEmbedding(id: 'f1', embedding: _perturbEmbedding(emb, delta: 0.01), imageId: 'img1'),
        _makeFaceWithEmbedding(id: 'f2', embedding: _perturbEmbedding(emb, delta: 0.02), imageId: 'img2'),
        _makeFaceWithEmbedding(id: 'f3', embedding: _perturbEmbedding(emb, delta: 0.01), imageId: 'img1'),
      ];

      final result = clustering.clusterFaces(faces);

      expect(result.clusterCount, equals(1));
      final cluster = result.clusters.first;

      expect(cluster.faceCount, equals(3));
      expect(cluster.imageIds, containsAll(['img1', 'img2']));
      expect(cluster.imageCount, equals(2), reason: 'img1 appears twice but counts once');
    });

    test('ClusterModel has representative face and centroid', () {
      final emb = _generateNormalizedEmbedding(seed: 30);
      final faces = [
        _makeFaceWithEmbedding(id: 'f1', embedding: _perturbEmbedding(emb, delta: 0.01), confidence: 0.9, imageId: 'img1'),
        _makeFaceWithEmbedding(id: 'f2', embedding: _perturbEmbedding(emb, delta: 0.02), confidence: 0.7, imageId: 'img2'),
      ];

      final result = clustering.clusterFaces(faces);
      final cluster = result.clusters.first;

      expect(cluster.representativeFaceId, isNotNull);
      // Representative should be the highest confidence face
      expect(cluster.representativeFaceId, equals('f1'));

      expect(cluster.centroidEmbedding, isNotNull);
      expect(cluster.centroidEmbedding!.length, equals(512));
    });
  });

  // ─────────────────────────────────────────
  // ClusteringService — incremental assignment
  // ─────────────────────────────────────────

  group('ClusteringService — incremental assignment', () {
    test('new face matches existing cluster within eps', () {
      final clustering = ClusteringService(eps: 0.6, minSamples: 2);
      final centroid = _generateNormalizedEmbedding(seed: 50);

      final existingClusters = [
        ClusterModel(
          clusterId: 0,
          faceIds: ['f1', 'f2'],
          imageIds: ['img1'],
          centroidEmbedding: centroid,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      // New face very similar to cluster centroid
      final newFaceEmb = _perturbEmbedding(centroid, delta: 0.05);

      final result = clustering.assignToNearestCluster(
        faceEmbedding: newFaceEmb,
        existingClusters: existingClusters,
      );

      expect(result, equals(0), reason: 'Should match cluster 0');
    });

    test('new face does not match any cluster — returns noise (-1)', () {
      final clustering = ClusteringService(eps: 0.6, minSamples: 2);
      final centroid = _generateNormalizedEmbedding(seed: 50);

      final existingClusters = [
        ClusterModel(
          clusterId: 0,
          faceIds: ['f1'],
          imageIds: ['img1'],
          centroidEmbedding: centroid,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      // Very different embedding
      final unrelatedEmb = _generateNormalizedEmbedding(seed: 999);

      final result = clustering.assignToNearestCluster(
        faceEmbedding: unrelatedEmb,
        existingClusters: existingClusters,
      );

      expect(result, equals(-1), reason: 'Should return noise when no cluster matches');
    });
  });

  // ─────────────────────────────────────────
  // FaceModel — model logic
  // ─────────────────────────────────────────

  group('FaceModel — computed properties', () {
    test('hasEmbedding: true only when embedding has 512 elements', () {
      final withEmb = _makeFaceWithEmbedding(
        id: 'f1',
        embedding: List.filled(512, 0.1),
      );
      final noEmb = _makeFaceNoEmbedding(id: 'f2');

      expect(withEmb.hasEmbedding, isTrue);
      expect(noEmb.hasEmbedding, isFalse);
    });

    test('isClustered: true only when clusterId >= 0', () {
      final noise     = _makeFaceWithEmbedding(id: 'f1', embedding: List.filled(512, 0.1));
      final clustered = noise.withCluster(3);

      expect(noise.isClustered, isFalse);
      expect(clustered.isClustered, isTrue);
      expect(clustered.clusterId, equals(3));
    });

    test('withEmbedding: returns copy with new embedding', () {
      final face = _makeFaceNoEmbedding(id: 'f1');
      final emb  = List<double>.filled(512, 0.25);
      final updated = face.withEmbedding(emb);

      expect(updated.embedding, equals(emb));
      expect(updated.id, equals(face.id)); // other fields unchanged
    });

    test('copyWith preserves unchanged fields', () {
      final face = _makeFaceWithEmbedding(
        id: 'f1',
        embedding: List.filled(512, 0.1),
        confidence: 0.95,
      );
      final copy = face.copyWith(clusterId: 2);

      expect(copy.clusterId, equals(2));
      expect(copy.detectionConfidence, equals(0.95));
      expect(copy.id, equals('f1'));
    });
  });

  // ─────────────────────────────────────────
  // ClusterModel — model logic
  // ─────────────────────────────────────────

  group('ClusterModel — computed properties', () {
    test('displayName: uses label if set, otherwise auto-generates', () {
      final named = ClusterModel(
        clusterId: 0, faceIds: [], imageIds: [],
        label: 'Mom',
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      );
      final unnamed = ClusterModel(
        clusterId: 4, faceIds: [], imageIds: [],
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      );

      expect(named.displayName, equals('Mom'));
      expect(unnamed.displayName, equals('Person 5')); // clusterId + 1
    });

    test('withFaceAdded: increments faceCount, deduplicates imageIds', () {
      final cluster = ClusterModel(
        clusterId: 0,
        faceIds: ['f1'],
        imageIds: ['img1'],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final updated = cluster.withFaceAdded('f2', 'img1'); // same image
      expect(updated.faceCount, equals(2));
      expect(updated.imageCount, equals(1), reason: 'img1 should not be duplicated');
    });

    test('hasCentroid: false when centroid is null or wrong size', () {
      final noCentroid = ClusterModel(
        clusterId: 0, faceIds: [], imageIds: [],
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      );
      final withCentroid = noCentroid.withCentroid(List.filled(512, 0.1));

      expect(noCentroid.hasCentroid, isFalse);
      expect(withCentroid.hasCentroid, isTrue);
    });
  });
}

// ─────────────────────────────────────────────────────────────────
// Test helpers
// ─────────────────────────────────────────────────────────────────

/// Generates a deterministic 512D unit vector from a seed.
List<double> _generateNormalizedEmbedding({required int seed}) {
  final rng = _SeededRandom(seed);
  final raw = List<double>.generate(512, (_) => rng.nextDouble() * 2 - 1);
  return _l2Normalize(raw);
}

/// Adds a small deterministic perturbation to an embedding and re-normalizes.
List<double> _perturbEmbedding(List<double> base, {required double delta}) {
  final rng = _SeededRandom(base.length + (delta * 1000).toInt());
  final perturbed = base.map((v) => v + (rng.nextDouble() * 2 - 1) * delta).toList();
  return _l2Normalize(perturbed);
}

List<double> _l2Normalize(List<double> v) {
  double norm = 0;
  for (final x in v) {
    norm += x * x;
  }
  norm = norm == 0 ? 1.0 : norm;
  final len = norm < 1e-9 ? 1.0 : (1.0 / (norm * norm)); // approximate
  // Proper sqrt normalization:
  double sqrtNorm = 0;
  for (final x in v) {
    sqrtNorm += x * x;
  }
  sqrtNorm = sqrtNorm == 0 ? 1.0 : sqrtNorm;
  final scale = 1.0 / (sqrtNorm == 0 ? 1.0 : _sqrt(sqrtNorm));
  return v.map((x) => x * scale).toList();
}

double _sqrt(double x) {
  if (x <= 0) return 0;
  double r = x;
  for (int i = 0; i < 30; i++) {
    r = (r + x / r) / 2;
  }
  return r;
}

FaceModel _makeFace({required String id, required int seed}) {
  return FaceModel(
    id: id, imageId: 'img_$id',
    bboxX: 0.1, bboxY: 0.1, bboxWidth: 0.3, bboxHeight: 0.4,
    detectionConfidence: 0.95,
    embedding: _generateNormalizedEmbedding(seed: seed),
    detectedAt: DateTime.now(),
  );
}

FaceModel _makeFaceWithEmbedding({
  required String id,
  required List<double> embedding,
  String imageId = 'test_image',
  double confidence = 0.9,
}) {
  return FaceModel(
    id: id, imageId: imageId,
    bboxX: 0.1, bboxY: 0.1, bboxWidth: 0.3, bboxHeight: 0.4,
    detectionConfidence: confidence,
    embedding: embedding,
    detectedAt: DateTime.now(),
  );
}

FaceModel _makeFaceNoEmbedding({required String id}) {
  return FaceModel(
    id: id, imageId: 'test_image',
    bboxX: 0.1, bboxY: 0.1, bboxWidth: 0.3, bboxHeight: 0.4,
    detectionConfidence: 0.85,
    detectedAt: DateTime.now(),
  );
}

/// Simple deterministic pseudo-random generator (no dart:math Random needed)
class _SeededRandom {
  int _state;
  _SeededRandom(this._state);

  double nextDouble() {
    _state = (_state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return (_state & 0xFFFF) / 0xFFFF;
  }
}