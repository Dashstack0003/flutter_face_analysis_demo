import 'package:equatable/equatable.dart';
import '../../models/face_model.dart';
import '../../models/cluster_model.dart';
import '../../repository/face_repository.dart';

/// Status of any face processing operation.
enum FaceOperationStatus {
  initial,
  processing,   // detection + embedding running
  clustering,   // DBSCAN running
  loading,      // reading from Hive
  success,
  failure,
}

/// Complete state for the face processing pipeline.
class FaceState extends Equatable {

  // ── Processing flags ─────────────────────

  /// True while an image is being run through detection + embedding
  final bool isProcessingImage;

  /// True while DBSCAN clustering is running
  final bool isClustering;

  /// True while clusters are being loaded from Hive
  final bool isLoadingClusters;

  /// Current operation status
  final FaceOperationStatus status;

  // ── Data ─────────────────────────────────

  /// All clusters (one per person), sorted by face count descending
  final List<ClusterModel> clusters;

  /// Faces loaded for the currently-viewed cluster detail screen
  final List<FaceModel> selectedClusterFaces;

  /// ID of the cluster currently being viewed (null = none)
  final int? selectedClusterId;

  /// Quick-access stats for dashboard display
  final FaceStats? stats;

  // ── Progress tracking ─────────────────────

  /// Total images queued for processing (for progress bar)
  final int processingTotal;

  /// Images processed so far
  final int processingDone;

  // ── Error handling ────────────────────────

  final bool hasError;
  final String errorMessage;

  const FaceState({
    this.isProcessingImage = false,
    this.isClustering = false,
    this.isLoadingClusters = false,
    this.status = FaceOperationStatus.initial,
    this.clusters = const [],
    this.selectedClusterFaces = const [],
    this.selectedClusterId,
    this.stats,
    this.processingTotal = 0,
    this.processingDone = 0,
    this.hasError = false,
    this.errorMessage = '',
  });

  // ── Computed properties ───────────────────

  /// True if any async operation is running
  bool get isLoading =>
      isProcessingImage || isClustering || isLoadingClusters;

  /// Processing progress as 0.0–1.0 (for ProgressIndicator)
  double get processingProgress =>
      processingTotal == 0 ? 0.0 : processingDone / processingTotal;

  /// Total number of unique people identified
  int get peopleCount => clusters.length;

  /// True if at least one person cluster exists
  bool get hasClusters => clusters.isNotEmpty;

  // ── copyWith ─────────────────────────────

  FaceState copyWith({
    bool? isProcessingImage,
    bool? isClustering,
    bool? isLoadingClusters,
    FaceOperationStatus? status,
    List<ClusterModel>? clusters,
    List<FaceModel>? selectedClusterFaces,
    int? selectedClusterId,
    FaceStats? stats,
    int? processingTotal,
    int? processingDone,
    bool? hasError,
    String? errorMessage,
    bool clearSelectedCluster = false,
  }) {
    return FaceState(
      isProcessingImage: isProcessingImage ?? this.isProcessingImage,
      isClustering: isClustering ?? this.isClustering,
      isLoadingClusters: isLoadingClusters ?? this.isLoadingClusters,
      status: status ?? this.status,
      clusters: clusters ?? this.clusters,
      selectedClusterFaces: selectedClusterFaces ?? this.selectedClusterFaces,
      selectedClusterId: clearSelectedCluster
          ? null
          : selectedClusterId ?? this.selectedClusterId,
      stats: stats ?? this.stats,
      processingTotal: processingTotal ?? this.processingTotal,
      processingDone: processingDone ?? this.processingDone,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  // ── Convenience transition methods ───────

  FaceState toProcessing() => copyWith(
        isProcessingImage: true,
        hasError: false,
        errorMessage: '',
        status: FaceOperationStatus.processing,
      );

  FaceState toClustering() => copyWith(
        isClustering: true,
        hasError: false,
        errorMessage: '',
        status: FaceOperationStatus.clustering,
      );

  FaceState toSuccess() => copyWith(
        isProcessingImage: false,
        isClustering: false,
        isLoadingClusters: false,
        hasError: false,
        errorMessage: '',
        status: FaceOperationStatus.success,
      );

  FaceState toError(String message) => copyWith(
        isProcessingImage: false,
        isClustering: false,
        isLoadingClusters: false,
        hasError: true,
        errorMessage: message,
        status: FaceOperationStatus.failure,
      );

  @override
  List<Object?> get props => [
        isProcessingImage,
        isClustering,
        isLoadingClusters,
        status,
        clusters,
        selectedClusterFaces,
        selectedClusterId,
        stats,
        processingTotal,
        processingDone,
        hasError,
        errorMessage,
      ];

  @override
  String toString() {
    return 'FaceState('
        'status: $status, '
        'clusters: ${clusters.length}, '
        'isProcessing: $isProcessingImage, '
        'isClustering: $isClustering, '
        'hasError: $hasError'
        ')';
  }
}
