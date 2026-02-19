import 'package:flutter_bloc/flutter_bloc.dart';
import '../../repository/face_repository.dart';
import '../../models/cluster_model.dart';
import 'face_events.dart';
import 'face_state.dart';

/// Orchestrates the full on-device face processing pipeline:
///   ProcessImage → detect faces → extract embeddings → assign/re-cluster
///
/// Connects to [FaceRepository] for all ML and storage operations.
/// UI listens to [FaceState] for progress, clusters, and errors.
class FaceBloc extends Bloc<FaceEvents, FaceState> {
  final FaceRepository _faceRepository;

  FaceBloc({required FaceRepository faceRepository})
      : _faceRepository = faceRepository,
        super(const FaceState()) {
    on<ProcessImageRequested>(_onProcessImageRequested);
    on<RunFullClusteringRequested>(_onRunFullClusteringRequested);
    on<LoadClustersRequested>(_onLoadClustersRequested);
    on<LoadClusterFacesRequested>(_onLoadClusterFacesRequested);
    on<RenameClusterRequested>(_onRenameClusterRequested);
    on<DeleteFacesForImageRequested>(_onDeleteFacesForImageRequested);
    on<ClearAllFaceDataRequested>(_onClearAllFaceDataRequested);
    on<ResetFaceErrorRequested>(_onResetFaceErrorRequested);
  }

  // ─────────────────────────────────────────
  // Process a single image
  // ─────────────────────────────────────────

  /// Runs the full pipeline (detect → embed → cluster assign) for one image.
  ///
  /// Emits processing state, runs the pipeline in the background,
  /// then reloads clusters and stats on completion.
  Future<void> _onProcessImageRequested(
    ProcessImageRequested event,
    Emitter<FaceState> emit,
  ) async {
    try {
      emit(state.toProcessing());

      final result = await _faceRepository.processImage(event.image);

      if (!result.isSuccess) {
        emit(state.toError(
          result.errorMessage ?? 'Failed to process image.',
        ));
        return;
      }

      // Refresh clusters and stats after processing
      await _reloadClustersAndStats(emit);

      emit(state.toSuccess().copyWith(
        processingDone: state.processingDone + 1,
      ));
    } on Exception catch (e) {
      emit(state.toError(_parseError(e)));
    }
  }

  // ─────────────────────────────────────────
  // Full DBSCAN re-clustering
  // ─────────────────────────────────────────

  /// Runs full DBSCAN across all stored embeddings.
  ///
  /// This can take 1–2 seconds for large collections — the UI should
  /// show a loading indicator while [FaceState.isClustering] is true.
  Future<void> _onRunFullClusteringRequested(
    RunFullClusteringRequested event,
    Emitter<FaceState> emit,
  ) async {
    try {
      emit(state.toClustering());

      final result = await _faceRepository.runFullClustering();

      if (!result.  isSuccess) {
        emit(state.toError(
          result.errorMessage ?? 'Clustering failed.',
        ));
        return;
      }

      final clusteringResult = result.data!;

      // Reload updated clusters from Hive
      final clustersResult = await _faceRepository.getAllClusters();
      final statsResult    = await _faceRepository.getStats();

      emit(state.toSuccess().copyWith(
        clusters: clustersResult.data ?? [],
        stats: statsResult.data,
      ));

      // Log summary (visible in debug console)
      print('[FaceBloc] Clustering complete: '
          '${clusteringResult.clusterCount} people, '
          '${clusteringResult.noiseCount} noise faces');
    } on Exception catch (e) {
      emit(state.toError(_parseError(e)));
    }
  }

  // ─────────────────────────────────────────
  // Load clusters (People tab)
  // ─────────────────────────────────────────

  Future<void> _onLoadClustersRequested(
    LoadClustersRequested event,
    Emitter<FaceState> emit,
  ) async {
    try {
      emit(state.copyWith(
        isLoadingClusters: true,
        hasError: false,
        errorMessage: '',
      ));

      await _reloadClustersAndStats(emit);

      emit(state.toSuccess());
    } on Exception catch (e) {
      emit(state.toError(_parseError(e)));
    }
  }

  // ─────────────────────────────────────────
  // Load faces for cluster detail screen
  // ─────────────────────────────────────────

  Future<void> _onLoadClusterFacesRequested(
    LoadClusterFacesRequested event,
    Emitter<FaceState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoadingClusters: true));

      final result = await _faceRepository.getFacesByCluster(event.clusterId);

      if (!result.isSuccess) {
        emit(state.toError(
          result.errorMessage ?? 'Failed to load faces.',
        ));
        return;
      }

      emit(state.toSuccess().copyWith(
        selectedClusterFaces: result.data ?? [],
        selectedClusterId: event.clusterId,
      ));
    } on Exception catch (e) {
      emit(state.toError(_parseError(e)));
    }
  }

  // ─────────────────────────────────────────
  // Rename cluster
  // ─────────────────────────────────────────

  Future<void> _onRenameClusterRequested(
    RenameClusterRequested event,
    Emitter<FaceState> emit,
  ) async {
    try {
      final result = await _faceRepository.renameCluster(
        clusterId: event.clusterId,
        newLabel: event.newLabel,
      );

      if (!result.isSuccess) {
        emit(state.toError(
          result.errorMessage ?? 'Failed to rename cluster.',
        ));
        return;
      }

      // Update the cluster in the current list without full reload
      final updatedClusters = state.clusters.map((c) {
        return c.clusterId == event.clusterId ? result.data! : c;
      }).toList();

      emit(state.toSuccess().copyWith(clusters: updatedClusters));
    } on Exception catch (e) {
      emit(state.toError(_parseError(e)));
    }
  }

  // ─────────────────────────────────────────
  // Delete faces for a deleted image
  // ─────────────────────────────────────────

  Future<void> _onDeleteFacesForImageRequested(
    DeleteFacesForImageRequested event,
    Emitter<FaceState> emit,
  ) async {
    try {
      final result = await _faceRepository.deleteFacesForImage(event.imageId);

      if (!result.isSuccess) {
        // Non-critical: log but don't show error to user
        print('[FaceBloc] Failed to delete faces for image ${event.imageId}: '
            '${result.errorMessage}');
        return;
      }

      // Refresh clusters since face counts may have changed
      await _reloadClustersAndStats(emit);
    } on Exception catch (e) {
      print('[FaceBloc] Error deleting faces: ${_parseError(e)}');
    }
  }

  // ─────────────────────────────────────────
  // Clear all face data
  // ─────────────────────────────────────────

  Future<void> _onClearAllFaceDataRequested(
    ClearAllFaceDataRequested event,
    Emitter<FaceState> emit,
  ) async {
    try {
      await _faceRepository.clearAll();

      emit(state.toSuccess().copyWith(
        clusters: [],
        selectedClusterFaces: [],
        stats: null,
        processingDone: 0,
        processingTotal: 0,
        clearSelectedCluster: true,
      ));
    } on Exception catch (e) {
      emit(state.toError(_parseError(e)));
    }
  }

  // ─────────────────────────────────────────
  // Reset error
  // ─────────────────────────────────────────

  void _onResetFaceErrorRequested(
    ResetFaceErrorRequested event,
    Emitter<FaceState> emit,
  ) {
    emit(state.copyWith(hasError: false, errorMessage: ''));
  }

  // ─────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────

  /// Reloads both clusters list and stats from Hive.
  /// Called after any mutation (process, cluster, delete).
  Future<void> _reloadClustersAndStats(Emitter<FaceState> emit) async {
    final clustersResult = await _faceRepository.getAllClusters();
    final statsResult    = await _faceRepository.getStats();

    final clusters = clustersResult.data ?? <ClusterModel>[];
    final stats    = statsResult.data;

    emit(state.copyWith(
      clusters: clusters,
      stats: stats,
      isLoadingClusters: false,
    ));
  }

  String _parseError(Exception e) {
    final message = e.toString();
    if (message.contains('StateError')) {
      return 'ML models not ready. Please restart the app.';
    }
    if (message.contains('HiveError')) {
      return 'Database error. Please restart the app.';
    }
    return 'Face processing error. Please try again.';
  }
}
