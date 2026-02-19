import '../helper/hive_helper.dart';
import '../helper/image_picker_helper.dart';
import '../models/image_model.dart';

/// Result wrapper for repository operations
class RepositoryResult<T> {
  final T? data;
  final String? errorMessage;
  final bool isSuccess;

  const RepositoryResult._({
    this.data,
    this.errorMessage,
    required this.isSuccess,
  });

  factory RepositoryResult.success(T data) {
    return RepositoryResult._(data: data, isSuccess: true);
  }

  factory RepositoryResult.failure(String message) {
    return RepositoryResult._(errorMessage: message, isSuccess: false);
  }

  @override
  String toString() {
    return 'RepositoryResult(isSuccess: $isSuccess, error: $errorMessage)';
  }
}

/// Repository class to manage all image-related operations
/// Acts as the single source of truth between BLoC and data layer
class ImageRepository {
  const ImageRepository();

  /// Pick an image from the given source and save to local database
  Future<RepositoryResult<ImageModel>> pickAndSaveImage(
    ImageSourceType source,
  ) async {
    try {
      /// Step 1: Pick image from source
      final ImagePickResult pickResult = await ImagePickerHelper.pickImage(
        source,
      );

      /// Handle cancellation
      if (pickResult.isCancelled) {
        return RepositoryResult.failure('cancelled');
      }

      /// Handle pick error
      if (!pickResult.isSuccess || pickResult.image == null) {
        return RepositoryResult.failure(
          pickResult.errorMessage ?? 'Failed to pick image.',
        );
      }

      final ImageModel image = pickResult.image!;

      /// Step 2: Check for duplicate
      final bool exists = await HiveHelper.imageExists(image.id);
      if (exists) {
        return RepositoryResult.failure('This image has already been saved.');
      }

      /// Step 3: Save to local database
      await HiveHelper.addImage(image);

      return RepositoryResult.success(image);
    } on Exception catch (e) {
      return RepositoryResult.failure(_parseException(e));
    }
  }

  /// Load all images sorted by date (newest first by default)
  Future<RepositoryResult<List<ImageModel>>> loadAllImages({
    bool ascending = false,
  }) async {
    try {
      final List<ImageModel> images = await HiveHelper.getImagesSortedByDate(
        ascending: ascending,
      );

      return RepositoryResult.success(images);
    } on Exception catch (e) {
      return RepositoryResult.failure(_parseException(e));
    }
  }

  /// Delete a single image by ID
  Future<RepositoryResult<bool>> deleteImage(String id) async {
    try {
      /// Check if image exists before deleting
      final bool exists = await HiveHelper.imageExists(id);
      if (!exists) {
        return RepositoryResult.failure('Image not found in the database.');
      }

      await HiveHelper.deleteImage(id);

      return RepositoryResult.success(true);
    } on Exception catch (e) {
      return RepositoryResult.failure(_parseException(e));
    }
  }

  /// Delete multiple images by IDs
  Future<RepositoryResult<bool>> deleteMultipleImages(List<String> ids) async {
    try {
      if (ids.isEmpty) {
        return RepositoryResult.failure('No images selected for deletion.');
      }

      await HiveHelper.deleteImages(ids);

      return RepositoryResult.success(true);
    } on Exception catch (e) {
      return RepositoryResult.failure(_parseException(e));
    }
  }

  /// Clear all images from local database
  Future<RepositoryResult<bool>> clearAllImages() async {
    try {
      await HiveHelper.clearAllImages();

      return RepositoryResult.success(true);
    } on Exception catch (e) {
      return RepositoryResult.failure(_parseException(e));
    }
  }

  /// Get total image count
  Future<RepositoryResult<int>> getImageCount() async {
    try {
      final int count = await HiveHelper.getImageCount();

      return RepositoryResult.success(count);
    } on Exception catch (e) {
      return RepositoryResult.failure(_parseException(e));
    }
  }

  /// Get total storage used by all images
  Future<RepositoryResult<String>> getTotalStorageUsed() async {
    try {
      final int totalBytes = await HiveHelper.getTotalStorageSize();
      final String formatted = ImagePickerHelper.formatFileSize(totalBytes);

      return RepositoryResult.success(formatted);
    } on Exception catch (e) {
      return RepositoryResult.failure(_parseException(e));
    }
  }

  /// Get a single image by ID
  Future<RepositoryResult<ImageModel>> getImageById(String id) async {
    try {
      final ImageModel? image = await HiveHelper.getImageById(id);

      if (image == null) {
        return RepositoryResult.failure('Image not found.');
      }

      return RepositoryResult.success(image);
    } on Exception catch (e) {
      return RepositoryResult.failure(_parseException(e));
    }
  }

  /// Validates if image file still exists on disk
  Future<RepositoryResult<bool>> validateImageFile(String path) async {
    try {
      final bool exists = await ImagePickerHelper.fileExists(path);

      return RepositoryResult.success(exists);
    } on Exception catch (e) {
      return RepositoryResult.failure(_parseException(e));
    }
  }

  /// Parses exception to a user-friendly message
  String _parseException(Exception e) {
    final String message = e.toString();

    if (message.contains('MissingPluginException')) {
      return 'Feature not supported on this device.';
    }
    if (message.contains('PlatformException')) {
      return 'Device error occurred. Please try again.';
    }
    if (message.contains('FileSystemException')) {
      return 'File system error. Please check storage permissions.';
    }

    return 'An unexpected error occurred. Please try again.';
  }
}
