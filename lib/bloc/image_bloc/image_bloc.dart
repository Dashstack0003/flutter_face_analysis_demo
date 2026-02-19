import 'package:flutter_bloc/flutter_bloc.dart';

import '../../repository/image_repository.dart';
import '../../models/image_model.dart';
import 'image_events.dart';
import 'image_state.dart';

class ImageBloc extends Bloc<ImageEvents, ImageState> {
  final ImageRepository _imageRepository;

  ImageBloc({
    required ImageRepository imageRepository,
  })  : _imageRepository = imageRepository,
        super(const ImageState()) {
    /// Register event handlers
    on<LoadImagesRequested>(_onLoadImagesRequested);
    on<PickImageRequested>(_onPickImageRequested);
    on<DeleteImageRequested>(_onDeleteImageRequested);
    on<DeleteMultipleImagesRequested>(_onDeleteMultipleImagesRequested);
    on<ClearAllImagesRequested>(_onClearAllImagesRequested);
    on<ToggleSelectionModeRequested>(_onToggleSelectionModeRequested);
    on<ToggleImageSelectionRequested>(_onToggleImageSelectionRequested);
    on<SelectAllImagesRequested>(_onSelectAllImagesRequested);
    on<DeselectAllImagesRequested>(_onDeselectAllImagesRequested);
    on<UpdateBottomNavIndexRequested>(_onUpdateBottomNavIndexRequested);
    on<ResetErrorRequested>(_onResetErrorRequested);
    on<ResetImageStateRequested>(_onResetImageStateRequested);
    on<HandleImageError>(_onHandleImageError);
  }

  /// ─────────────────────────────────────────
  /// Load Images
  /// ─────────────────────────────────────────
  Future<void> _onLoadImagesRequested(
      LoadImagesRequested event,
      Emitter<ImageState> emit,
      ) async {
    try {
      emit(state.copyWith(
        isLoadingImages: true,
        hasError: false,
        errorMessage: '',
      ));

      final result = await _imageRepository.loadAllImages(
        ascending: event.ascending,
      );

      if (!result.isSuccess) {
        emit(state.toError(
          result.errorMessage ?? 'Failed to load images.',
        ));
        return;
      }

      final List<ImageModel> images = result.data ?? [];

      /// Fetch metadata
      final countResult = await _imageRepository.getImageCount();
      final storageResult = await _imageRepository.getTotalStorageUsed();

      emit(state.toSuccess().copyWith(
        images: images,
        isLoadingImages: false,
        totalImageCount: countResult.data ?? images.length,
        totalStorageUsed: storageResult.data ?? '0 B',
      ));
    } on Exception catch (e) {
      add(HandleImageError(error: e));
    }
  }

  /// ─────────────────────────────────────────
  /// Pick Image
  /// ─────────────────────────────────────────
  Future<void> _onPickImageRequested(
      PickImageRequested event,
      Emitter<ImageState> emit,
      ) async {
    try {
      emit(state.toPicking());

      final result = await _imageRepository.pickAndSaveImage(event.source);

      /// Handle cancellation silently
      if (!result.isSuccess && result.errorMessage == 'cancelled') {
        emit(state.toSuccess());
        return;
      }

      if (!result.isSuccess) {
        emit(state.toError(
          result.errorMessage ?? 'Failed to pick image.',
        ));
        return;
      }

      final ImageModel pickedImage = result.data!;

      /// Update images list with newly picked image
      final List<ImageModel> updatedImages = [
        pickedImage,
        ...state.images,
      ];

      emit(state.toSuccess().copyWith(
        images: updatedImages,
        lastPickedImage: pickedImage,
        totalImageCount: updatedImages.length,
      ));
    } on Exception catch (e) {
      add(HandleImageError(error: e));
    }
  }

  /// ─────────────────────────────────────────
  /// Delete Single Image
  /// ─────────────────────────────────────────
  Future<void> _onDeleteImageRequested(
      DeleteImageRequested event,
      Emitter<ImageState> emit,
      ) async {
    try {
      emit(state.toDeleting());

      final result = await _imageRepository.deleteImage(event.imageId);

      if (!result.isSuccess) {
        emit(state.toError(
          result.errorMessage ?? 'Failed to delete image.',
        ));
        return;
      }

      /// Remove deleted image from list
      final List<ImageModel> updatedImages = state.images
          .where((image) => image.id != event.imageId)
          .toList();

      /// Remove from selected IDs if in selection mode
      final List<String> updatedSelectedIds = state.selectedImageIds
          .where((id) => id != event.imageId)
          .toList();

      /// Fetch updated storage info
      final storageResult = await _imageRepository.getTotalStorageUsed();

      emit(state.toSuccess().copyWith(
        images: updatedImages,
        selectedImageIds: updatedSelectedIds,
        totalImageCount: updatedImages.length,
        totalStorageUsed: storageResult.data ?? '0 B',
      ));
    } on Exception catch (e) {
      add(HandleImageError(error: e));
    }
  }

  /// ─────────────────────────────────────────
  /// Delete Multiple Images
  /// ─────────────────────────────────────────
  Future<void> _onDeleteMultipleImagesRequested(
      DeleteMultipleImagesRequested event,
      Emitter<ImageState> emit,
      ) async {
    try {
      emit(state.toDeleting());

      final result =
      await _imageRepository.deleteMultipleImages(event.imageIds);

      if (!result.isSuccess) {
        emit(state.toError(
          result.errorMessage ?? 'Failed to delete images.',
        ));
        return;
      }

      /// Remove all deleted images from list
      final List<ImageModel> updatedImages = state.images
          .where((image) => !event.imageIds.contains(image.id))
          .toList();

      /// Fetch updated storage info
      final storageResult = await _imageRepository.getTotalStorageUsed();

      emit(state.toSuccess().copyWith(
        images: updatedImages,
        selectedImageIds: [],
        isSelectionMode: false,
        totalImageCount: updatedImages.length,
        totalStorageUsed: storageResult.data ?? '0 B',
      ));
    } on Exception catch (e) {
      add(HandleImageError(error: e));
    }
  }

  /// ─────────────────────────────────────────
  /// Clear All Images
  /// ─────────────────────────────────────────
  Future<void> _onClearAllImagesRequested(
      ClearAllImagesRequested event,
      Emitter<ImageState> emit,
      ) async {
    try {
      emit(state.toLoading());

      final result = await _imageRepository.clearAllImages();

      if (!result.isSuccess) {
        emit(state.toError(
          result.errorMessage ?? 'Failed to clear images.',
        ));
        return;
      }

      emit(state.toSuccess().copyWith(
        images: [],
        selectedImageIds: [],
        isSelectionMode: false,
        totalImageCount: 0,
        totalStorageUsed: '0 B',
        isReset: false,
      ));
    } on Exception catch (e) {
      add(HandleImageError(error: e));
    }
  }

  /// ─────────────────────────────────────────
  /// Toggle Selection Mode
  /// ─────────────────────────────────────────
  void _onToggleSelectionModeRequested(
      ToggleSelectionModeRequested event,
      Emitter<ImageState> emit,
      ) {
    emit(state.copyWith(
      isSelectionMode: event.isSelectionMode,
      selectedImageIds: event.isSelectionMode ? state.selectedImageIds : [],
    ));
  }

  /// ─────────────────────────────────────────
  /// Toggle Single Image Selection
  /// ─────────────────────────────────────────
  void _onToggleImageSelectionRequested(
      ToggleImageSelectionRequested event,
      Emitter<ImageState> emit,
      ) {
    final List<String> updatedIds =
    List<String>.from(state.selectedImageIds);

    if (updatedIds.contains(event.imageId)) {
      updatedIds.remove(event.imageId);
    } else {
      updatedIds.add(event.imageId);
    }

    /// Auto-exit selection mode if no images selected
    final bool shouldStayInSelectionMode = updatedIds.isNotEmpty;

    emit(state.copyWith(
      selectedImageIds: updatedIds,
      isSelectionMode: shouldStayInSelectionMode,
    ));
  }

  /// ─────────────────────────────────────────
  /// Select All Images
  /// ─────────────────────────────────────────
  void _onSelectAllImagesRequested(
      SelectAllImagesRequested event,
      Emitter<ImageState> emit,
      ) {
    final List<String> allIds =
    state.images.map((image) => image.id).toList();

    emit(state.copyWith(
      selectedImageIds: allIds,
      isSelectionMode: true,
    ));
  }

  /// ─────────────────────────────────────────
  /// Deselect All Images
  /// ─────────────────────────────────────────
  void _onDeselectAllImagesRequested(
      DeselectAllImagesRequested event,
      Emitter<ImageState> emit,
      ) {
    emit(state.copyWith(
      selectedImageIds: [],
      isSelectionMode: false,
    ));
  }

  /// ─────────────────────────────────────────
  /// Update Bottom Nav Index
  /// ─────────────────────────────────────────
  void _onUpdateBottomNavIndexRequested(
      UpdateBottomNavIndexRequested event,
      Emitter<ImageState> emit,
      ) {
    emit(state.copyWith(
      currentBottomNavIndex: event.index,
    ));
  }

  /// ─────────────────────────────────────────
  /// Reset Error
  /// ─────────────────────────────────────────
  void _onResetErrorRequested(
      ResetErrorRequested event,
      Emitter<ImageState> emit,
      ) {
    emit(state.copyWith(
      hasError: false,
      errorMessage: '',
    ));
  }

  /// ─────────────────────────────────────────
  /// Reset State
  /// ─────────────────────────────────────────
  void _onResetImageStateRequested(
      ResetImageStateRequested event,
      Emitter<ImageState> emit,
      ) {
    emit(const ImageState());
  }

  /// ─────────────────────────────────────────
  /// Handle Error
  /// ─────────────────────────────────────────
  void _onHandleImageError(
      HandleImageError event,
      Emitter<ImageState> emit,
      ) {
    final String message = event.customMessage ??
        _parseError(event.error);

    emit(state.toError(message));
  }

  /// ─────────────────────────────────────────
  /// Private: Parse Error to Message
  /// ─────────────────────────────────────────
  String _parseError(Object error) {
    final String message = error.toString();

    if (message.contains('SocketException') ||
        message.contains('NetworkException')) {
      return 'Network error. Please check your connection.';
    }
    if (message.contains('HiveError')) {
      return 'Database error. Please restart the app.';
    }
    if (message.contains('FileSystemException')) {
      return 'File error. Please check storage permissions.';
    }
    if (message.contains('PlatformException')) {
      return 'Device error. Please try again.';
    }

    return 'Something went wrong. Please try again.';
  }
}