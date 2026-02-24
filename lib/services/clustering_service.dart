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
  /// LOWERED from 0.6 → 0.8 for more lenient grouping (same person across
  /// different lighting/angles/expressions should cluster together).
  final double eps;

  /// Minimum faces to form a core point.
  /// Set to 1 so even a single face gets its own cluster.
  final int minSamples;

  /// Merge clusters whose centroids are within this distance.
  /// Prevents duplicate people from being split across multiple clusters.
  final double mergeThreshold;

  static const int _noiseLabel = -1;

  ClusteringService({
    this.eps = 0.8,              // ← INCREASED for looser matching
    this.minSamples = 1,
    this.mergeThreshold = 0.7,   // ← NEW: merge similar clusters
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
    final distances = List.generate(n, (_) => List<double>.filled(n, 0.0));

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
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
      if (j != pointIdx && distances[pointIdx][j] <= eps) {
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

      clusters.add(ClusterModel(
        clusterId: clusterId,
        faceIds: clusterFaces.map((f) => f.id).toList(),
        imageIds: imageIds,
        representativeFaceId: representative.id,
        centroidEmbedding: centroid,
        createdAt: now,
        updatedAt: now,
      ));
    }

    clusters.sort((a, b) => b.faceCount.compareTo(a.faceCount));

    return clusters;
  }

  // ─────────────────────────────────────────────────────────────
  // ✨ NEW — Merge similar clusters
  // ─────────────────────────────────────────────────────────────

  /// Merges clusters whose centroids are within [mergeThreshold] distance.
  /// This fixes duplicate people being split across multiple clusters due
  /// to DBSCAN's strict eps requirements.
  Map<String, dynamic> _mergeSimilarClusters(
      List<ClusterModel> clusters,
      List<FaceModel> faces,
      ) {
    if (clusters.length <= 1) {
      return {'clusters': clusters, 'faces': faces};
    }

    // Build centroid distance matrix
    final n = clusters.length;
    final centroidDistances = List.generate(n, (_) => List<double>.filled(n, 0.0));

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (!clusters[i].hasCentroid || !clusters[j].hasCentroid) continue;

        final dist = EmbeddingService.euclideanDistance(
          clusters[i].centroidEmbedding!,
          clusters[j].centroidEmbedding!,
        );
        centroidDistances[i][j] = dist;
        centroidDistances[j][i] = dist;
      }
    }

    // Find clusters to merge using union-find
    final parent = List<int>.generate(n, (i) => i);

    int find(int x) {
      if (parent[x] != x) parent[x] = find(parent[x]);
      return parent[x];
    }

    void union(int x, int y) {
      final px = find(x);
      final py = find(y);
      if (px != py) parent[px] = py;
    }

    // Merge clusters within threshold
    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (centroidDistances[i][j] <= mergeThreshold) {
          union(i, j);
        }
      }
    }

    // Group clusters by merge group
    final mergeGroups = <int, List<int>>{};
    for (int i = 0; i < n; i++) {
      mergeGroups.putIfAbsent(find(i), () => []).add(i);
    }

    // Build merged clusters
    final mergedClusters = <ClusterModel>[];
    final oldToNew = <int, int>{};
    int newClusterId = 0;

    for (final group in mergeGroups.values) {
      if (group.length == 1) {
        // No merge needed
        final old = clusters[group.first];
        oldToNew[old.clusterId] = newClusterId;
        mergedClusters.add(old.copyWith(clusterId: newClusterId));
      } else {
        // Merge multiple clusters
        final toMerge = group.map((i) => clusters[i]).toList();
        final allFaceIds = toMerge.expand((c) => c.faceIds).toList();
        final allImageIds = toMerge.expand((c) => c.imageIds).toSet().toList();

        // Pick representative with highest confidence
        final allFaces = faces.where((f) => allFaceIds.contains(f.id)).toList();
        final representative = allFaces.reduce(
              (best, face) =>
          face.detectionConfidence > best.detectionConfidence ? face : best,
        );

        // Recompute merged centroid
        final centroid = _computeCentroid(
          allFaces.map((f) => f.embedding!).toList(),
        );

        for (final old in toMerge) {
          oldToNew[old.clusterId] = newClusterId;
        }

        mergedClusters.add(ClusterModel(
          clusterId: newClusterId,
          faceIds: allFaceIds,
          imageIds: allImageIds,
          representativeFaceId: representative.id,
          centroidEmbedding: centroid,
          createdAt: toMerge.first.createdAt,
          updatedAt: DateTime.now(),
        ));
      }
      newClusterId++;
    }

    // Reassign faces to merged cluster IDs
    final updatedFaces = faces.map((f) {
      if (f.isClustered && oldToNew.containsKey(f.clusterId)) {
        return f.withCluster(oldToNew[f.clusterId]!);
      }
      return f;
    }).toList();

    mergedClusters.sort((a, b) => b.faceCount.compareTo(a.faceCount));

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

    return bestDistance <= eps ? bestClusterId : _noiseLabel;
  }
}
