import 'package:equatable/equatable.dart';
import '../../models/image_model.dart';

/// Enum representing the status of image operations
enum ImageOperationStatus {
  initial,
  loading,
  success,
  failure,
  picking,
  deleting,
}

/// Represents the complete image state of the application
class ImageState extends Equatable {
  /// Core image list
  final List<ImageModel> images;

  /// Operation status
  final ImageOperationStatus status;

  /// Loading flags
  final bool isLoading;
  final bool isPickingImage;
  final bool isDeletingImage;
  final bool isLoadingImages;

  /// Newly picked image (used for success feedback)
  final ImageModel? lastPickedImage;

  /// Error handling
  final String errorMessage;
  final bool hasError;

  /// Selection mode for grid view
  final bool isSelectionMode;
  final List<String> selectedImageIds;

  /// Bottom navigation
  final int currentBottomNavIndex;

  /// Metadata
  final int totalImageCount;
  final String totalStorageUsed;

  const ImageState({
    this.images = const [],
    this.status = ImageOperationStatus.initial,
    this.isLoading = false,
    this.isPickingImage = false,
    this.isDeletingImage = false,
    this.isLoadingImages = false,
    this.lastPickedImage,
    this.errorMessage = '',
    this.hasError = false,
    this.isSelectionMode = false,
    this.selectedImageIds = const [],
    this.currentBottomNavIndex = 0,
    this.totalImageCount = 0,
    this.totalStorageUsed = '0 B',
  });

  /// Returns true if any images are selected
  bool get hasSelectedImages => selectedImageIds.isNotEmpty;

  /// Returns the count of selected images
  int get selectedCount => selectedImageIds.length;

  /// Returns true if all images are selected
  bool get isAllSelected =>
      images.isNotEmpty && selectedImageIds.length == images.length;

  /// Returns true if images list is empty
  bool get isEmpty => images.isEmpty;

  /// Creates a copy of this state with the given fields replaced
  ImageState copyWith({
    List<ImageModel>? images,
    ImageOperationStatus? status,
    bool? isLoading,
    bool? isPickingImage,
    bool? isDeletingImage,
    bool? isLoadingImages,
    ImageModel? lastPickedImage,
    String? errorMessage,
    bool? hasError,
    bool? isSelectionMode,
    List<String>? selectedImageIds,
    int? currentBottomNavIndex,
    int? totalImageCount,
    String? totalStorageUsed,
    bool isReset = false,
  }) {
    return ImageState(
      images: images ?? this.images,
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      isPickingImage: isPickingImage ?? this.isPickingImage,
      isDeletingImage: isDeletingImage ?? this.isDeletingImage,
      isLoadingImages: isLoadingImages ?? this.isLoadingImages,
      lastPickedImage: isReset ? null : lastPickedImage ?? this.lastPickedImage,
      errorMessage: isReset ? '' : errorMessage ?? this.errorMessage,
      hasError: isReset ? false : hasError ?? this.hasError,
      isSelectionMode: isReset
          ? false
          : isSelectionMode ?? this.isSelectionMode,
      selectedImageIds: isReset
          ? []
          : selectedImageIds ?? this.selectedImageIds,
      currentBottomNavIndex:
          currentBottomNavIndex ?? this.currentBottomNavIndex,
      totalImageCount: totalImageCount ?? this.totalImageCount,
      totalStorageUsed: totalStorageUsed ?? this.totalStorageUsed,
    );
  }

  /// Convenience method - returns loading state
  ImageState toLoading() => copyWith(
    isLoading: true,
    hasError: false,
    errorMessage: '',
    status: ImageOperationStatus.loading,
  );

  /// Convenience method - returns picking state
  ImageState toPicking() => copyWith(
    isPickingImage: true,
    hasError: false,
    errorMessage: '',
    status: ImageOperationStatus.picking,
  );

  /// Convenience method - returns deleting state
  ImageState toDeleting() => copyWith(
    isDeletingImage: true,
    hasError: false,
    errorMessage: '',
    status: ImageOperationStatus.deleting,
  );

  /// Convenience method - returns error state
  ImageState toError(String message) => copyWith(
    isLoading: false,
    isPickingImage: false,
    isDeletingImage: false,
    isLoadingImages: false,
    hasError: true,
    errorMessage: message,
    status: ImageOperationStatus.failure,
  );

  /// Convenience method - returns success state
  ImageState toSuccess() => copyWith(
    isLoading: false,
    isPickingImage: false,
    isDeletingImage: false,
    isLoadingImages: false,
    hasError: false,
    errorMessage: '',
    status: ImageOperationStatus.success,
  );

  @override
  List<Object?> get props => [
    images,
    status,
    isLoading,
    isPickingImage,
    isDeletingImage,
    isLoadingImages,
    lastPickedImage,
    errorMessage,
    hasError,
    isSelectionMode,
    selectedImageIds,
    currentBottomNavIndex,
    totalImageCount,
    totalStorageUsed,
  ];

  @override
  String toString() {
    return 'ImageState('
        'status: $status, '
        'images: ${images.length}, '
        'isLoading: $isLoading, '
        'isPickingImage: $isPickingImage, '
        'isDeletingImage: $isDeletingImage, '
        'hasError: $hasError, '
        'errorMessage: $errorMessage, '
        'isSelectionMode: $isSelectionMode, '
        'selectedCount: $selectedCount, '
        'currentBottomNavIndex: $currentBottomNavIndex'
        ')';
  }
}
