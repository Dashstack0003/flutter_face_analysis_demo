import 'dart:math' as math;

import '../helper/hive_helper.dart';
import '../models/face_model.dart';
import '../models/cluster_model.dart';
import '../models/image_model.dart';
import '../services/face_detection_service.dart';
import '../services/embedding_service.dart';
import '../services/clustering_service.dart';

/// Result wrapper for face repository operations (mirrors ImageRepository pattern).
class FaceRepositoryResult<T> {
  final T? data;
  final String? errorMessage;
  final bool isSuccess;

  const FaceRepositoryResult._({
    this.data,
    this.errorMessage,
    required this.isSuccess,
  });

  factory FaceRepositoryResult.success(T data) =>
      FaceRepositoryResult._(data: data, isSuccess: true);

  factory FaceRepositoryResult.failure(String message) =>
      FaceRepositoryResult._(errorMessage: message, isSuccess: false);
}

/// Single source of truth for all face-related data operations.
///
/// Orchestrates the full ML pipeline per image:
///   detect → embed → save → (re)cluster
///
/// All results are persisted to Hive via [HiveHelper].
class FaceRepository {
  final FaceDetectionService _detectionService;
  final EmbeddingService _embeddingService;
  final ClusteringService _clusteringService;

  const FaceRepository({
    required FaceDetectionService detectionService,
    required EmbeddingService embeddingService,
    required ClusteringService clusteringService,
  }) : _detectionService = detectionService,
       _embeddingService = embeddingService,
       _clusteringService = clusteringService;

  // ─────────────────────────────────────────
  // Core Pipeline: Process a single image
  // ─────────────────────────────────────────

  /// Runs the complete face pipeline on a single [ImageModel]:
  ///   1. Run BlazeFace detection → get cropped face files
  ///   2. Run MobileFaceNet → get 512D embeddings
  ///   3. Save all [FaceModel]s to Hive
  ///   4. Run incremental cluster assignment (fast path)
  ///      OR flag for full re-cluster if no existing clusters
  ///
  /// Returns the list of [FaceModel]s saved for this image.
  Future<FaceRepositoryResult<List<FaceModel>>> processImage(
      ImageModel image,
      ) async {
    try {
      // ── Phase 1: Detection ──────────────────────────
      final detectionResult = await _detectionService.detectFaces(image.path);
      if (!detectionResult.hasFaces) {
        return FaceRepositoryResult.success([]);
      }

      // ── Phase 2: Embedding extraction ──────────────
      final now = DateTime.now();
      final facesToSave = <FaceModel>[];

      for (final detected in detectionResult.faces) {
        final embedding = await _embeddingService.extractEmbedding(detected.croppedPath);
        facesToSave.add(FaceModel(
          id: detected.faceId,
          imageId: image.id,
          bboxX: detected.bboxX,
          bboxY: detected.bboxY,
          bboxWidth: detected.bboxWidth,
          bboxHeight: detected.bboxHeight,
          detectionConfidence: detected.confidence,
          embedding: embedding,
          croppedFacePath: detected.croppedPath,
          detectedAt: now,
          clusterId: -1,
        ));
      }

      // ── Phase 3: Save faces to Hive ─────────────────
      await HiveHelper.addFaces(facesToSave);

      // ── Phase 4: Incremental cluster assignment ──────────────────────────
      // Compare each new face against existing cluster centroids.
      // This avoids a full DBSCAN re-run (which causes ID-reassignment issues)
      // and handles gradual embedding variation better via centroid matching.
      //
      // Same-image constraint: each existing cluster may only absorb ONE face
      // per processImage call. Two faces from the same photo are always
      // different people, so they can never go into the same cluster.
      final existingClusters = await HiveHelper.getAllClusters();
      final assignedFaces = <FaceModel>[];
      final unmatchedFaces = <FaceModel>[];
      final clustersToUpdate = <int, ClusterModel>{};
      final usedClusterIds = <int>{}; // clusters already claimed in this image

      for (final face in facesToSave) {
        // Only offer clusters not yet claimed by another face from this image
        final availableClusters = existingClusters
            .where((c) => !usedClusterIds.contains(c.clusterId))
            .toList();

        final clusterId = _clusteringService.assignToNearestCluster(
          faceEmbedding: face.embedding!,
          existingClusters: availableClusters,
        );
        if (clusterId != -1) {
          // Matched an existing person — add face to their cluster
          usedClusterIds.add(clusterId);
          final assigned = face.withCluster(clusterId);
          assignedFaces.add(assigned);
          clustersToUpdate[clusterId] ??= existingClusters.firstWhere(
            (c) => c.clusterId == clusterId,
          );
          clustersToUpdate[clusterId] =
              clustersToUpdate[clusterId]!.withFaceAdded(assigned.id, image.id);
        } else {
          unmatchedFaces.add(face);
        }
      }

      // ── Phase 5: Group unmatched faces into new clusters ─────────────────
      if (unmatchedFaces.isNotEmpty) {
        final nextId = existingClusters.isEmpty
            ? 0
            : existingClusters.map((c) => c.clusterId).reduce(math.max) + 1;

        // Run DBSCAN only on the new unmatched faces
        final result = _clusteringService.clusterFaces(unmatchedFaces);

        // Shift cluster IDs so they don't collide with existing ones
        for (final face in result.updatedFaces) {
          assignedFaces.add(
            face.isClustered ? face.withCluster(face.clusterId + nextId) : face,
          );
        }
        final newClusters = result.clusters
            .map((c) => c.copyWith(clusterId: c.clusterId + nextId))
            .toList();
        await HiveHelper.saveClusters(newClusters);
      }

      // ── Phase 6: Refresh centroids for matched clusters ───────────────────
      for (final updated in clustersToUpdate.values) {
        final alreadySaved =
            await HiveHelper.getFacesByClusterId(updated.clusterId);
        final addedNow = assignedFaces
            .where((f) => f.clusterId == updated.clusterId)
            .toList();
        final allEmbeddings = [
          ...alreadySaved.map((f) => f.embedding!),
          ...addedNow.map((f) => f.embedding!),
        ];
        if (allEmbeddings.isNotEmpty) {
          await HiveHelper.saveCluster(
              updated.withCentroid(_computeCentroid(allEmbeddings)));
        } else {
          await HiveHelper.saveCluster(updated);
        }
      }

      // ── Phase 7: Persist face cluster assignments ─────────────────────────
      await HiveHelper.updateFaces(assignedFaces);

      return FaceRepositoryResult.success(facesToSave);
    } on Exception catch (e) {
      return FaceRepositoryResult.failure(_parseException(e));
    }
  }

  // ─────────────────────────────────────────
  // Full Re-Clustering
  // ─────────────────────────────────────────

  /// Runs full DBSCAN clustering on ALL faces that have embeddings.
  ///
  /// This is the "batch" path — called:
  ///   - After initial bulk photo import
  ///   - Periodically after N new faces are added
  ///   - When user manually triggers re-cluster
  ///
  /// Clears existing clusters and replaces with fresh results.
  Future<FaceRepositoryResult<ClusteringResult>> runFullClustering() async {
    try {
      final allFaces = await HiveHelper.getFacesWithEmbeddings();
      if (allFaces.isEmpty) {
        return FaceRepositoryResult.failure('No faces with embeddings found.');
      }

      // 1. Snapshot OLD clusters before clearing
      final oldClusters = await HiveHelper.getAllClusters();

      // 2. Run DBSCAN
      final result = _clusteringService.clusterFaces(allFaces);

      // 3. Remap new IDs → old IDs by face overlap
      final remappedFaces = _remapToExistingClusterIds(
        result.updatedFaces,
        result.clusters,
        oldClusters,
      );

      // 4. Clear stale clusters
      await HiveHelper.clearAllClusters();

      // 5. Persist remapped faces
      await HiveHelper.updateFaces(remappedFaces);

      // 6. Rebuild clusters preserving labels
      final remappedClusters = _rebuildClusters(remappedFaces, oldClusters);
      await HiveHelper.saveClusters(remappedClusters);

      return FaceRepositoryResult.success(result);
    } on Exception catch (e) {
      return FaceRepositoryResult.failure(_parseException(e));
    }
  }

  // ─────────────────────────────────────────────────────
  // Label preservation after re-cluster
  // ─────────────────────────────────────────────────────

  /// After clustering, re-maps new clusters to old ones so that user-assigned
  /// labels survive re-clustering and new faces of existing people are merged
  /// back into their original group.
  ///
  /// Key invariant: EACH OLD CLUSTER IS CLAIMED BY AT MOST ONE NEW CLUSTER.
  /// Without this, two new clusters that both overlap the same old (wrongly
  /// merged) cluster get the same ID, and _rebuildClusters merges them again.
  ///
  /// Three passes:
  ///   1. Face-ID overlap (greedy, one-to-one) — highest overlap wins first.
  ///   2. Centroid fallback (one-to-one) — unclaimed old clusters only.
  ///   3. Collision-safe IDs — genuinely new people get fresh IDs.
  List<FaceModel> _remapToExistingClusterIds(
      List<FaceModel> newFaces,
      List<ClusterModel> newClusters,
      List<ClusterModel> oldClusters,
      ) {
    if (oldClusters.isEmpty) return newFaces;

    final newToOld = <int, int>{};
    final claimedOldIds = <int>{};

    // ── Pass 1: face-ID overlap (ONE-TO-ONE, greedy by best overlap) ─────────
    // Build all (overlap, newClusterId, oldClusterId) triples.
    final triples = <List<int>>[];
    for (final newCluster in newClusters) {
      final newFaceIds = newCluster.faceIds.toSet();
      for (final oldCluster in oldClusters) {
        final overlap =
            oldCluster.faceIds.toSet().intersection(newFaceIds).length;
        if (overlap > 0) {
          triples.add([overlap, newCluster.clusterId, oldCluster.clusterId]);
        }
      }
    }
    // Highest overlap wins first — prevents two new clusters from claiming
    // the same old cluster when the old data was incorrectly merged.
    triples.sort((a, b) => b[0].compareTo(a[0]));

    final claimedNewIds = <int>{};
    for (final t in triples) {
      final newId = t[1];
      final oldId = t[2];
      if (!claimedNewIds.contains(newId) && !claimedOldIds.contains(oldId)) {
        newToOld[newId] = oldId;
        claimedNewIds.add(newId);
        claimedOldIds.add(oldId);
      }
    }

    // ── Pass 2: centroid fallback (ONE-TO-ONE, unclaimed old clusters only) ──
    // Handles new faces of a known person that were just outside eps and
    // formed a separate cluster with no shared face IDs.
    for (final newCluster in newClusters) {
      if (newToOld.containsKey(newCluster.clusterId)) continue;
      if (!newCluster.hasCentroid) continue;

      int bestOldId = -1;
      double bestDist = double.infinity;

      for (final oldCluster in oldClusters) {
        if (claimedOldIds.contains(oldCluster.clusterId)) continue; // already taken
        if (!oldCluster.hasCentroid) continue;
        final dist = EmbeddingService.euclideanDistance(
          newCluster.centroidEmbedding!,
          oldCluster.centroidEmbedding!,
        );
        if (dist < bestDist) {
          bestDist = dist;
          bestOldId = oldCluster.clusterId;
        }
      }

      if (bestOldId != -1 && bestDist <= _clusteringService.mergeThreshold) {
        newToOld[newCluster.clusterId] = bestOldId;
        claimedOldIds.add(bestOldId);
      }
    }

    // ── Pass 3: collision-safe IDs for genuinely new people ───────────────
    // Unmapped clusters may have raw DBSCAN IDs (0, 1, 2 …) that coincide
    // with old cluster IDs assigned to a different person.
    final reservedIds = <int>{
      ...oldClusters.map((c) => c.clusterId),
      ...newToOld.values,
    };
    int nextFresh =
        (reservedIds.isEmpty ? -1 : reservedIds.reduce(math.max)) + 1;

    for (final newCluster in newClusters) {
      if (newToOld.containsKey(newCluster.clusterId)) continue;
      if (reservedIds.contains(newCluster.clusterId)) {
        while (reservedIds.contains(nextFresh)) { nextFresh++; }
        newToOld[newCluster.clusterId] = nextFresh;
        reservedIds.add(nextFresh);
        nextFresh++;
      }
    }

    // Apply remapping to faces
    return newFaces.map((f) {
      if (f.isClustered && newToOld.containsKey(f.clusterId)) {
        return f.withCluster(newToOld[f.clusterId]!);
      }
      return f;
    }).toList();
  }

  /// Rebuilds ClusterModel list from remapped faces, preserving old labels.
  List<ClusterModel> _rebuildClusters(
      List<FaceModel> remappedFaces,
      List<ClusterModel> oldClusters,
      ) {
    final oldById = {for (final c in oldClusters) c.clusterId: c};
    final groups = <int, List<FaceModel>>{};

    for (final face in remappedFaces) {
      if (face.isClustered) {
        groups.putIfAbsent(face.clusterId, () => []).add(face);
      }
    }

    final now = DateTime.now();
    final clusters = <ClusterModel>[];

    for (final entry in groups.entries) {
      final clusterId = entry.key;
      final faces = entry.value;
      final old = oldById[clusterId];

      final imageIds = faces.map((f) => f.imageId).toSet().toList();
      final representative = faces.reduce(
            (best, f) =>
        f.detectionConfidence > best.detectionConfidence ? f : best,
      );
      final centroid = _computeCentroid(faces.map((f) => f.embedding!).toList());

      clusters.add(ClusterModel(
        clusterId: clusterId,
        faceIds: faces.map((f) => f.id).toList(),
        imageIds: imageIds,
        representativeFaceId: representative.id,
        centroidEmbedding: centroid,
        label: old?.label,           // ← preserve existing label
        createdAt: old?.createdAt ?? now,
        updatedAt: now,
      ));
    }

    clusters.sort((a, b) => b.faceCount.compareTo(a.faceCount));
    return clusters;
  }

  /// Reuse centroid computation from ClusteringService (copy here to avoid coupling)
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

  // ─────────────────────────────────────────
  // Read operations
  // ─────────────────────────────────────────

  /// Returns all clusters sorted by face count (most faces first).
  Future<FaceRepositoryResult<List<ClusterModel>>> getAllClusters() async {
    try {
      final clusters = await HiveHelper.getAllClusters();
      return FaceRepositoryResult.success(clusters);
    } on Exception catch (e) {
      return FaceRepositoryResult.failure(_parseException(e));
    }
  }

  /// Returns all faces belonging to a given cluster ID.
  Future<FaceRepositoryResult<List<FaceModel>>> getFacesByCluster(
    int clusterId,
  ) async {
    try {
      final faces = await HiveHelper.getFacesByClusterId(clusterId);
      return FaceRepositoryResult.success(faces);
    } on Exception catch (e) {
      return FaceRepositoryResult.failure(_parseException(e));
    }
  }

  /// Returns all faces detected in a given image.
  Future<FaceRepositoryResult<List<FaceModel>>> getFacesByImage(
    String imageId,
  ) async {
    try {
      final faces = await HiveHelper.getFacesByImageId(imageId);
      return FaceRepositoryResult.success(faces);
    } on Exception catch (e) {
      return FaceRepositoryResult.failure(_parseException(e));
    }
  }

  /// Returns processing stats for the home screen dashboard.
  Future<FaceRepositoryResult<FaceStats>> getStats() async {
    try {
      final totalFaces = await HiveHelper.getFaceCount();
      final totalClusters = await HiveHelper.getClusterCount();
      final allFaces = await HiveHelper.getAllFaces();
      final unassigned = allFaces.where((f) => !f.isClustered).length;

      return FaceRepositoryResult.success(
        FaceStats(
          totalFaces: totalFaces,
          totalPeople: totalClusters,
          unassignedFaces: unassigned,
        ),
      );
    } on Exception catch (e) {
      return FaceRepositoryResult.failure(_parseException(e));
    }
  }

  // ─────────────────────────────────────────
  // Cluster management
  // ─────────────────────────────────────────

  /// Renames a cluster with a user-provided label.
  Future<FaceRepositoryResult<ClusterModel>> renameCluster({
    required int clusterId,
    required String newLabel,
  }) async {
    try {
      final cluster = await HiveHelper.getClusterById(clusterId);
      if (cluster == null) {
        return FaceRepositoryResult.failure('Cluster $clusterId not found.');
      }

      final updated = cluster.withLabel(newLabel);
      await HiveHelper.saveCluster(updated);

      return FaceRepositoryResult.success(updated);
    } on Exception catch (e) {
      return FaceRepositoryResult.failure(_parseException(e));
    }
  }

  /// Deletes all faces and data for a given image
  /// (called when user deletes an image from gallery).
  Future<FaceRepositoryResult<bool>> deleteFacesForImage(String imageId) async {
    try {
      await HiveHelper.deleteFacesByImageId(imageId);
      return FaceRepositoryResult.success(true);
    } on Exception catch (e) {
      return FaceRepositoryResult.failure(_parseException(e));
    }
  }

  /// Clears all face and cluster data (used in reset/clear all).
  Future<FaceRepositoryResult<bool>> clearAll() async {
    try {
      await HiveHelper.clearAllFaces();
      await HiveHelper.clearAllClusters();
      return FaceRepositoryResult.success(true);
    } on Exception catch (e) {
      return FaceRepositoryResult.failure(_parseException(e));
    }
  }

  // ─────────────────────────────────────────
  // Error parsing
  // ─────────────────────────────────────────

  String _parseException(Exception e) {
    final message = e.toString();
    if (message.contains('HiveError')) {
      return 'Database error. Please restart the app.';
    }
    if (message.contains('FileSystemException')) {
      return 'File error. Please check storage permissions.';
    }
    if (message.contains('StateError')) {
      return 'ML models not initialized. Please restart the app.';
    }
    return 'An unexpected error occurred during face processing.';
  }
}

/// Summary stats for the dashboard.
class FaceStats {
  final int totalFaces;
  final int totalPeople;
  final int unassignedFaces;

  const FaceStats({
    required this.totalFaces,
    required this.totalPeople,
    required this.unassignedFaces,
  });
}
