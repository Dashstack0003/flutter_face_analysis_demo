import 'dart:math' as math;
import '../models/face_model.dart';
import '../models/cluster_model.dart';
import 'embedding_service.dart';

/// Result of a full clustering run.
class ClusteringResult {
  final List<FaceModel> updatedFaces;
  final List<ClusterModel> clusters;
  final int noiseCount;

  const ClusteringResult({
    required this.updatedFaces,
    required this.clusters,
    required this.noiseCount,
  });

  int get clusterCount => clusters.length;

  bool get hasClusters => clusters.isNotEmpty;
}

/// Groups faces into clusters of the same person using DBSCAN + post-merge.
class ClusteringService {
  /// Distance threshold for DBSCAN neighbor detection.
  final double eps;

  /// Minimum faces to form a core point.
  /// Set to 1 so even a single face gets its own cluster.
  final int minSamples;

  /// Post-DBSCAN merge threshold (conservative).
  /// Only merges clusters whose centroids are VERY close.
  /// Kept low to avoid false merges of different people.
  final double mergeThreshold;

  /// Threshold used by [assignToNearestCluster] for incremental photo assignment.
  /// Higher than [mergeThreshold] so new photos of existing people get correctly
  /// assigned even when the embedding drifts across sessions.
  final double assignmentThreshold;

  static const int _noiseLabel = -1;

  ClusteringService({
    this.eps = 0.95, // tuned for 512D FaceNet embeddings
    this.minSamples = 1,
    this.mergeThreshold = 0.88, // merge clusters whose centroids are close
    this.assignmentThreshold =
        1.0, // lenient: link new photos of existing people
  });

  // ─────────────────────────────────────────────────────────────
  // Main entry point
  // ─────────────────────────────────────────────────────────────

  ClusteringResult clusterFaces(List<FaceModel> faces) {
    final validFaces = faces.where((f) => f.hasEmbedding).toList();

    if (validFaces.isEmpty) {
      return const ClusteringResult(
        updatedFaces: [],
        clusters: [],
        noiseCount: 0,
      );
    }

    // Step 1: Build distance matrix
    final distances = _buildDistanceMatrix(validFaces);

    // Step 2: Run DBSCAN
    final labels = _dbscan(validFaces.length, distances);

    // Step 3: Apply labels to faces
    final updatedFaces = <FaceModel>[];
    for (int i = 0; i < validFaces.length; i++) {
      updatedFaces.add(validFaces[i].withCluster(labels[i]));
    }

    // Step 4: Build initial clusters
    var clusters = _buildClusters(updatedFaces);

    // Step 5: ✨ NEW — Merge clusters with very similar centroids
    final mergeResult = _mergeSimilarClusters(clusters, updatedFaces);
    clusters = mergeResult['clusters'] as List<ClusterModel>;
    final finalFaces = mergeResult['faces'] as List<FaceModel>;

    final noiseCount = finalFaces.where((f) => !f.isClustered).length;

    return ClusteringResult(
      updatedFaces: finalFaces,
      clusters: clusters,
      noiseCount: noiseCount,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Distance matrix (unchanged)
  // ─────────────────────────────────────────────────────────────

  List<List<double>> _buildDistanceMatrix(List<FaceModel> faces) {
    final n = faces.length;
    // Use infinity as the "impossible" sentinel so same-image pairs are never
    // considered neighbours, regardless of how close their embeddings are.
    final distances = List.generate(
      n,
      (_) => List<double>.filled(n, double.infinity),
    );

    for (int i = 0; i < n; i++) {
      distances[i][i] = 0.0; // self-distance is always 0

      for (int j = i + 1; j < n; j++) {
        // Same-image constraint: two faces from the same photo are ALWAYS
        // different people. Never let DBSCAN link them as neighbours.
        if (faces[i].imageId == faces[j].imageId) {
          // Leave both distances[i][j] and distances[j][i] as infinity.
          continue;
        }

        final dist = EmbeddingService.euclideanDistance(
          faces[i].embedding!,
          faces[j].embedding!,
        );
        distances[i][j] = dist;
        distances[j][i] = dist;
      }
    }

    return distances;
  }

  // ─────────────────────────────────────────────────────────────
  // DBSCAN (unchanged)
  // ─────────────────────────────────────────────────────────────

  List<int> _dbscan(int n, List<List<double>> distances) {
    final labels = List<int>.filled(n, _noiseLabel);
    int currentCluster = 0;

    for (int i = 0; i < n; i++) {
      if (labels[i] != _noiseLabel) continue;

      final neighbors = _regionQuery(i, n, distances);

      if (neighbors.length < minSamples) continue;

      labels[i] = currentCluster;
      _expandCluster(i, neighbors, currentCluster, labels, n, distances);

      currentCluster++;
    }

    return labels;
  }

  void _expandCluster(
    int pointIdx,
    List<int> neighbors,
    int clusterId,
    List<int> labels,
    int n,
    List<List<double>> distances,
  ) {
    final queue = List<int>.from(neighbors);

    int qi = 0;
    while (qi < queue.length) {
      final neighbor = queue[qi++];

      if (labels[neighbor] == _noiseLabel) {
        labels[neighbor] = clusterId;

        final neighborNeighbors = _regionQuery(neighbor, n, distances);

        if (neighborNeighbors.length >= minSamples) {
          for (final nn in neighborNeighbors) {
            if (labels[nn] == _noiseLabel) {
              queue.add(nn);
            }
          }
        }
      }
    }
  }

  List<int> _regionQuery(int pointIdx, int n, List<List<double>> distances) {
    final neighbors = <int>[];
    for (int j = 0; j < n; j++) {
      // REMOVE "j != pointIdx" so the point counts as its own neighbor
      if (distances[pointIdx][j] <= eps) {
        neighbors.add(j);
      }
    }
    return neighbors;
  }

  // ─────────────────────────────────────────────────────────────
  // Build clusters (unchanged)
  // ─────────────────────────────────────────────────────────────

  List<ClusterModel> _buildClusters(List<FaceModel> labelledFaces) {
    final groups = <int, List<FaceModel>>{};
    for (final face in labelledFaces) {
      if (face.isClustered) {
        groups.putIfAbsent(face.clusterId, () => []).add(face);
      }
    }

    final now = DateTime.now();
    final clusters = <ClusterModel>[];

    for (final entry in groups.entries) {
      final clusterId = entry.key;
      final clusterFaces = entry.value;

      final imageIds = clusterFaces.map((f) => f.imageId).toSet().toList();

      final representative = clusterFaces.reduce(
        (best, face) =>
            face.detectionConfidence > best.detectionConfidence ? face : best,
      );

      final centroid = _computeCentroid(
        clusterFaces.map((f) => f.embedding!).toList(),
      );

      clusters.add(
        ClusterModel(
          clusterId: clusterId,
          faceIds: clusterFaces.map((f) => f.id).toList(),
          imageIds: imageIds,
          representativeFaceId: representative.id,
          centroidEmbedding: centroid,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    clusters.sort((a, b) => b.faceCount.compareTo(a.faceCount));

    return clusters;
  }

  // ─────────────────────────────────────────────────────────────
  // ✨ NEW — Merge similar clusters
  // ─────────────────────────────────────────────────────────────

  /// Merges clusters whose centroids are within [mergeThreshold] distance.
  ///
  /// Uses ITERATIVE greedy merging (NOT union-find):
  ///   1. Find the closest pair of clusters.
  ///   2. If their distance ≤ mergeThreshold, merge them and RECOMPUTE centroid.
  ///   3. Repeat until no pair is below threshold.
  ///
  /// This prevents the transitivity / bridge problem: with union-find, if
  /// A↔B < threshold and B↔C < threshold, all three merge even when A↔C is
  /// large (A and C are different people).  After merging A+B the centroid
  /// shifts, so the new AB↔C distance is checked fresh — no more false chains.
  Map<String, dynamic> _mergeSimilarClusters(
    List<ClusterModel> clusters,
    List<FaceModel> faces,
  ) {
    if (clusters.length <= 1) {
      return {'clusters': clusters, 'faces': faces};
    }

    // Working copy — cluster IDs stay as original DBSCAN IDs throughout.
    var working = List<ClusterModel>.from(clusters);

    // Maps each surviving cluster ID → all original cluster IDs absorbed into it.
    final originalsFor = <int, List<int>>{
      for (final c in clusters) c.clusterId: [c.clusterId],
    };

    // Greedy loop: always merge the single closest pair below threshold.
    while (true) {
      double bestDist = double.infinity;
      int bestI = -1, bestJ = -1;

      for (int i = 0; i < working.length; i++) {
        for (int j = i + 1; j < working.length; j++) {
          if (!working[i].hasCentroid || !working[j].hasCentroid) continue;
          final dist = EmbeddingService.euclideanDistance(
            working[i].centroidEmbedding!,
            working[j].centroidEmbedding!,
          );
          print(
            '[mergeSimilarClusters] dist ${working[i].displayName}(${working[i].clusterId})'
            ' ↔ ${working[j].displayName}(${working[j].clusterId}): $dist',
          );
          if (dist < bestDist) {
            bestDist = dist;
            bestI = i;
            bestJ = j;
          }
        }
      }

      if (bestI == -1 || bestDist > mergeThreshold) break;

      // Merge working[bestJ] INTO working[bestI].
      final a = working[bestI];
      final b = working[bestJ];

      final allFaceIds = [...a.faceIds, ...b.faceIds];
      final allImageIds = {...a.imageIds, ...b.imageIds}.toList();
      final mergedFaces = faces
          .where((f) => allFaceIds.contains(f.id))
          .toList();

      final representative = mergedFaces.reduce(
        (best, f) =>
            f.detectionConfidence > best.detectionConfidence ? f : best,
      );
      final centroid = _computeCentroid(
        mergedFaces.map((f) => f.embedding!).toList(),
      );

      working[bestI] = ClusterModel(
        clusterId: a.clusterId,
        // keep survivor's original ID
        faceIds: allFaceIds,
        imageIds: allImageIds,
        representativeFaceId: representative.id,
        centroidEmbedding: centroid,
        // ← fresh centroid prevents bridging
        createdAt: a.createdAt,
        updatedAt: DateTime.now(),
      );

      // Track all originals that now belong to the survivor.
      originalsFor[a.clusterId]!.addAll(originalsFor[b.clusterId]!);
      originalsFor.remove(b.clusterId);
      working.removeAt(bestJ);
    }

    // Renumber final clusters 0, 1, 2, … and build oldToNew map.
    final mergedClusters = <ClusterModel>[];
    final oldToNew = <int, int>{}; // original DBSCAN ID → new sequential ID
    int newId = 0;

    for (final c in working) {
      for (final origId in originalsFor[c.clusterId]!) {
        oldToNew[origId] = newId;
      }
      mergedClusters.add(c.copyWith(clusterId: newId));
      newId++;
    }

    // Reassign faces.
    final updatedFaces = faces.map((f) {
      if (f.isClustered && oldToNew.containsKey(f.clusterId)) {
        return f.withCluster(oldToNew[f.clusterId]!);
      }
      return f;
    }).toList();

    mergedClusters.sort((a, b) => b.faceCount.compareTo(a.faceCount));

    print(
      '[mergeSimilarClusters] Result: ${mergedClusters.length} clusters after merge',
    );
    return {'clusters': mergedClusters, 'faces': updatedFaces};
  }

  // ─────────────────────────────────────────────────────────────
  // Centroid (dynamic size)
  // ─────────────────────────────────────────────────────────────

  List<double> _computeCentroid(List<List<double>> embeddings) {
    final size = embeddings.first.length;
    final sum = List<double>.filled(size, 0.0);

    for (final emb in embeddings) {
      for (int i = 0; i < size; i++) {
        sum[i] += emb[i];
      }
    }

    final count = embeddings.length.toDouble();
    final mean = sum.map((v) => v / count).toList();

    double norm = 0.0;
    for (final v in mean) {
      norm += v * v;
    }
    norm = math.sqrt(norm);

    if (norm == 0.0) return mean;
    return mean.map((v) => v / norm).toList();
  }

  // ─────────────────────────────────────────────────────────────
  // Incremental assignment (unused now — always full DBSCAN)
  // ─────────────────────────────────────────────────────────────

  int assignToNearestCluster({
    required List<double> faceEmbedding,
    required List<ClusterModel> existingClusters,
  }) {
    int bestClusterId = _noiseLabel;
    double bestDistance = double.infinity;

    for (final cluster in existingClusters) {
      if (!cluster.hasCentroid) continue;

      final dist = EmbeddingService.euclideanDistance(
        faceEmbedding,
        cluster.centroidEmbedding!,
      );

      if (dist < bestDistance) {
        bestDistance = dist;
        bestClusterId = cluster.clusterId;
      }
    }

    return bestDistance <= assignmentThreshold ? bestClusterId : _noiseLabel;
  }
}
