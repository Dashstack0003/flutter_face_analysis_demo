import 'package:equatable/equatable.dart';
import '../../helper/image_picker_helper.dart';

/// Base class for all image-related events
abstract class ImageEvents extends Equatable {
  const ImageEvents();

  @override
  List<Object?> get props => [];
}

/// Event to load all images from local database
class LoadImagesRequested extends ImageEvents {
  final bool ascending;

  const LoadImagesRequested({this.ascending = false});

  @override
  List<Object?> get props => [ascending];
}

/// Event to pick and save a new image from given source
class PickImageRequested extends ImageEvents {
  final ImageSourceType source;

  const PickImageRequested({required this.source});

  @override
  List<Object?> get props => [source];
}

/// Event to delete a single image by ID
class DeleteImageRequested extends ImageEvents {
  final String imageId;

  const DeleteImageRequested({required this.imageId});

  @override
  List<Object?> get props => [imageId];
}

/// Event to delete multiple selected images
class DeleteMultipleImagesRequested extends ImageEvents {
  final List<String> imageIds;

  const DeleteMultipleImagesRequested({required this.imageIds});

  @override
  List<Object?> get props => [imageIds];
}

/// Event to clear all images from local database
class ClearAllImagesRequested extends ImageEvents {}

/// Event to toggle selection mode in grid view
class ToggleSelectionModeRequested extends ImageEvents {
  final bool isSelectionMode;

  const ToggleSelectionModeRequested({required this.isSelectionMode});

  @override
  List<Object?> get props => [isSelectionMode];
}

/// Event to toggle selection of a specific image
class ToggleImageSelectionRequested extends ImageEvents {
  final String imageId;

  const ToggleImageSelectionRequested({required this.imageId});

  @override
  List<Object?> get props => [imageId];
}

/// Event to select all images in grid view
class SelectAllImagesRequested extends ImageEvents {}

/// Event to deselect all images in grid view
class DeselectAllImagesRequested extends ImageEvents {}

/// Event to update bottom navigation index
class UpdateBottomNavIndexRequested extends ImageEvents {
  final int index;

  const UpdateBottomNavIndexRequested({required this.index});

  @override
  List<Object?> get props => [index];
}

/// Event to reset error message in state
class ResetErrorRequested extends ImageEvents {}

/// Event to reset the entire image state
class ResetImageStateRequested extends ImageEvents {}

/// Event to handle errors from any operation
class HandleImageError extends ImageEvents {
  final Object error;
  final String? customMessage;

  const HandleImageError({required this.error, this.customMessage});

  @override
  List<Object?> get props => [error, customMessage];
}
