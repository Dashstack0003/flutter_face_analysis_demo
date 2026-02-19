import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';

part 'face_model.g.dart';

/// Represents a single detected face within an image.
///
/// Stores:
/// - Which image it came from ([imageId])
/// - Where in the image the face is ([bbox*] fields)
/// - How confident the detection was ([detectionConfidence])
/// - The 512D embedding vector ([embedding]) used for clustering
/// - Which cluster/person it belongs to ([clusterId])
/// - Optional path to the cropped face thumbnail ([croppedFacePath])
@HiveType(typeId: 1)
class FaceModel extends Equatable {
  /// Unique ID for this face (UUID v4)
  @HiveField(0)
  final String id;

  /// ID of the parent [ImageModel] this face was detected in
  @HiveField(1)
  final String imageId;

  /// Bounding box — left edge (0.0 to 1.0, relative to image width)
  @HiveField(2)
  final double bboxX;

  /// Bounding box — top edge (0.0 to 1.0, relative to image height)
  @HiveField(3)
  final double bboxY;

  /// Bounding box — width (0.0 to 1.0, relative to image width)
  @HiveField(4)
  final double bboxWidth;

  /// Bounding box — height (0.0 to 1.0, relative to image height)
  @HiveField(5)
  final double bboxHeight;

  /// Detection confidence score (0.0 to 1.0). Only faces >= 0.7 are kept.
  @HiveField(6)
  final double detectionConfidence;

  /// 512-dimensional face embedding from FaceNet.
  /// Stored as a flat List<double>. Null until embedding extraction runs.
  @HiveField(7)
  final List<double>? embedding;

  /// Cluster ID assigned by DBSCAN.
  /// -1 = noise/unassigned, >= 0 = valid cluster (person group)
  @HiveField(8)
  final int clusterId;

  /// Path to the cropped & aligned face image saved on disk.
  /// Used for thumbnails in the UI. Null until cropping runs.
  @HiveField(9)
  final String? croppedFacePath;

  /// Timestamp when this face was detected
  @HiveField(10)
  final DateTime detectedAt;

  const FaceModel({
    required this.id,
    required this.imageId,
    required this.bboxX,
    required this.bboxY,
    required this.bboxWidth,
    required this.bboxHeight,
    required this.detectionConfidence,
    required this.detectedAt,
    this.embedding,
    this.clusterId = -1,
    this.croppedFacePath,
  });

  /// Returns true if this face has a valid embedding extracted
  // Accepts any embedding size — supports 192D and 512D model variants
  bool get hasEmbedding => embedding != null && embedding!.isNotEmpty;

  /// Returns true if this face has been assigned to a cluster
  bool get isClustered => clusterId >= 0;

  /// Returns true if this face has a saved crop thumbnail
  bool get hasCrop => croppedFacePath != null;

  /// Returns the bounding box as a map (useful for drawing overlays)
  Map<String, double> get bboxMap => {
    'x': bboxX,
    'y': bboxY,
    'width': bboxWidth,
    'height': bboxHeight,
  };

  FaceModel copyWith({
    String? id,
    String? imageId,
    double? bboxX,
    double? bboxY,
    double? bboxWidth,
    double? bboxHeight,
    double? detectionConfidence,
    List<double>? embedding,
    int? clusterId,
    String? croppedFacePath,
    DateTime? detectedAt,
  }) {
    return FaceModel(
      id: id ?? this.id,
      imageId: imageId ?? this.imageId,
      bboxX: bboxX ?? this.bboxX,
      bboxY: bboxY ?? this.bboxY,
      bboxWidth: bboxWidth ?? this.bboxWidth,
      bboxHeight: bboxHeight ?? this.bboxHeight,
      detectionConfidence: detectionConfidence ?? this.detectionConfidence,
      embedding: embedding ?? this.embedding,
      clusterId: clusterId ?? this.clusterId,
      croppedFacePath: croppedFacePath ?? this.croppedFacePath,
      detectedAt: detectedAt ?? this.detectedAt,
    );
  }

  /// Returns a copy with the embedding set
  FaceModel withEmbedding(List<double> newEmbedding) {
    return copyWith(embedding: newEmbedding);
  }

  /// Returns a copy with the cluster ID assigned
  FaceModel withCluster(int newClusterId) {
    return copyWith(clusterId: newClusterId);
  }

  /// Returns a copy with the cropped face path set
  FaceModel withCrop(String path) {
    return copyWith(croppedFacePath: path);
  }

  @override
  List<Object?> get props => [
    id,
    imageId,
    bboxX,
    bboxY,
    bboxWidth,
    bboxHeight,
    detectionConfidence,
    embedding,
    clusterId,
    croppedFacePath,
    detectedAt,
  ];

  @override
  String toString() {
    return 'FaceModel('
        'id: $id, '
        'imageId: $imageId, '
        'confidence: ${detectionConfidence.toStringAsFixed(2)}, '
        'clusterId: $clusterId, '
        'hasEmbedding: $hasEmbedding, '
        'hasCrop: $hasCrop'
        ')';
  }
}
