import 'package:equatable/equatable.dart';
import '../../models/image_model.dart';

/// Base class for all face processing events.
abstract class FaceEvents extends Equatable {
  const FaceEvents();

  @override
  List<Object?> get props => [];
}

/// Triggered when a single image needs face processing (detect + embed + assign cluster).
/// Called automatically after ImageBloc saves a new image.
class ProcessImageRequested extends FaceEvents {
  final ImageModel image;

  const ProcessImageRequested({required this.image});

  @override
  List<Object?> get props => [image];
}

/// Triggers a full DBSCAN re-cluster across all stored face embeddings.
/// Used after bulk import or when the user manually requests re-clustering.
class RunFullClusteringRequested extends FaceEvents {}

/// Loads all clusters from Hive (for the People tab).
class LoadClustersRequested extends FaceEvents {}

/// Loads all faces belonging to a specific cluster (for cluster detail screen).
class LoadClusterFacesRequested extends FaceEvents {
  final int clusterId;

  const LoadClusterFacesRequested({required this.clusterId});

  @override
  List<Object?> get props => [clusterId];
}

/// Renames a cluster with a user-provided label.
class RenameClusterRequested extends FaceEvents {
  final int clusterId;
  final String newLabel;

  const RenameClusterRequested({
    required this.clusterId,
    required this.newLabel,
  });

  @override
  List<Object?> get props => [clusterId, newLabel];
}

/// Called when an image is deleted — removes all its associated faces.
class DeleteFacesForImageRequested extends FaceEvents {
  final String imageId;

  const DeleteFacesForImageRequested({required this.imageId});

  @override
  List<Object?> get props => [imageId];
}

/// Clears all face and cluster data (used when user clears all images).
class ClearAllFaceDataRequested extends FaceEvents {}

/// Resets any error state.
class ResetFaceErrorRequested extends FaceEvents {}
