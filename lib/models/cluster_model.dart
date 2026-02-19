import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';

part 'cluster_model.g.dart';

/// Represents a cluster of faces that belong to the same person.
///
/// Created and updated by [ClusteringService] after DBSCAN runs.
/// Each cluster maps to one "person" shown in the People tab.
///
/// Key relationships:
/// - One [ClusterModel] → many [FaceModel]s (via [clusterId])
/// - One [ClusterModel] → many [ImageModel]s (via [imageIds])
@HiveType(typeId: 2)
class ClusterModel extends Equatable {
  /// Cluster ID — matches [FaceModel.clusterId].
  /// -1 is reserved for noise/unassigned. Valid clusters start at 0.
  @HiveField(0)
  final int clusterId;

  /// Optional user-assigned name (e.g. "Mom", "John").
  /// Null until the user labels it.
  @HiveField(1)
  final String? label;

  /// IDs of all [FaceModel]s belonging to this cluster
  @HiveField(2)
  final List<String> faceIds;

  /// IDs of all unique [ImageModel]s that contain faces from this cluster.
  /// Used to quickly show "all photos of this person".
  @HiveField(3)
  final List<String> imageIds;

  /// Face ID of the best representative face for this cluster.
  /// Used as the cluster thumbnail in the People tab.
  /// Chosen as the face with the highest detection confidence.
  @HiveField(4)
  final String? representativeFaceId;

  /// The mean (centroid) embedding vector of all faces in this cluster.
  /// Used for fast nearest-cluster lookup when adding new faces.
  @HiveField(5)
  final List<double>? centroidEmbedding;

  /// When this cluster was first created
  @HiveField(6)
  final DateTime createdAt;

  /// When this cluster was last updated (new face added, re-clustered, etc.)
  @HiveField(7)
  final DateTime updatedAt;

  const ClusterModel({
    required this.clusterId,
    required this.faceIds,
    required this.imageIds,
    required this.createdAt,
    required this.updatedAt,
    this.label,
    this.representativeFaceId,
    this.centroidEmbedding,
  });

  /// Total number of faces in this cluster
  int get faceCount => faceIds.length;

  /// Total number of unique images containing this person
  int get imageCount => imageIds.length;

  /// True if user has given this cluster a name
  bool get isLabelled => label != null && label!.isNotEmpty;

  /// True if this cluster has a centroid computed
  /// Fixed: supports both 192D and 512D embeddings
  bool get hasCentroid =>
      centroidEmbedding != null && centroidEmbedding!.isNotEmpty;

  /// Display name — user label if set, otherwise auto-generated
  String get displayName => isLabelled ? label! : 'Person ${clusterId + 1}';

  ClusterModel copyWith({
    int? clusterId,
    String? label,
    List<String>? faceIds,
    List<String>? imageIds,
    String? representativeFaceId,
    List<double>? centroidEmbedding,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ClusterModel(
      clusterId: clusterId ?? this.clusterId,
      label: label ?? this.label,
      faceIds: faceIds ?? this.faceIds,
      imageIds: imageIds ?? this.imageIds,
      representativeFaceId:
      representativeFaceId ?? this.representativeFaceId,
      centroidEmbedding: centroidEmbedding ?? this.centroidEmbedding,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns a copy with a new face added to this cluster
  ClusterModel withFaceAdded(String faceId, String imageId) {
    final updatedFaceIds = List<String>.from(faceIds)..add(faceId);
    final updatedImageIds = imageIds.contains(imageId)
        ? imageIds
        : (List<String>.from(imageIds)..add(imageId));
    return copyWith(
      faceIds: updatedFaceIds,
      imageIds: updatedImageIds,
      updatedAt: DateTime.now(),
    );
  }

  /// Returns a copy with a face removed from this cluster
  ClusterModel withFaceRemoved(String faceId) {
    final updatedFaceIds = List<String>.from(faceIds)..remove(faceId);
    return copyWith(
      faceIds: updatedFaceIds,
      updatedAt: DateTime.now(),
    );
  }

  /// Returns a copy with a user-assigned label
  ClusterModel withLabel(String newLabel) {
    return copyWith(
      label: newLabel,
      updatedAt: DateTime.now(),
    );
  }

  /// Returns a copy with a new centroid embedding
  ClusterModel withCentroid(List<double> newCentroid) {
    return copyWith(
      centroidEmbedding: newCentroid,
      updatedAt: DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    clusterId,
    label,
    faceIds,
    imageIds,
    representativeFaceId,
    centroidEmbedding,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() {
    return 'ClusterModel('
        'clusterId: $clusterId, '
        'displayName: $displayName, '
        'faceCount: $faceCount, '
        'imageCount: $imageCount, '
        'isLabelled: $isLabelled'
        ')';
  }
}
