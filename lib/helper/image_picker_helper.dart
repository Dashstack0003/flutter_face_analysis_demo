import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/image_model.dart';

/// Enum representing available image source options
enum ImageSourceType {
  camera,
  gallery,
  files,
}

/// Result wrapper for image picking operations
class ImagePickResult {
  final ImageModel? image;
  final String? errorMessage;
  final bool isCancelled;

  const ImagePickResult._({
    this.image,
    this.errorMessage,
    this.isCancelled = false,
  });

  factory ImagePickResult.success(ImageModel image) {
    return ImagePickResult._(image: image);
  }

  factory ImagePickResult.error(String message) {
    return ImagePickResult._(errorMessage: message);
  }

  factory ImagePickResult.cancelled() {
    return ImagePickResult._(isCancelled: true);
  }

  bool get isSuccess => image != null;

  @override
  String toString() {
    return 'ImagePickResult(isSuccess: $isSuccess, isCancelled: $isCancelled, error: $errorMessage)';
  }
}

/// Helper class to manage image picking from camera, gallery, and files
class ImagePickerHelper {
  ImagePickerHelper._();

  static final ImagePicker _imagePicker = ImagePicker();
  static const Uuid _uuid = Uuid();

  /// Supported image extensions for file picker
  static const List<String> _supportedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
  ];

  /// Main method to pick an image from the given source
  static Future<ImagePickResult> pickImage(ImageSourceType source) async {
    switch (source) {
      case ImageSourceType.camera:
        return await _pickFromCamera();
      case ImageSourceType.gallery:
        return await _pickFromGallery();
      case ImageSourceType.files:
        return await _pickFromFiles();
    }
  }

  /// Pick image from camera
  static Future<ImagePickResult> _pickFromCamera() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (pickedFile == null) {
        return ImagePickResult.cancelled();
      }

      return await _buildImageModel(pickedFile.path);
    } on Exception catch (e) {
      return ImagePickResult.error(
        _parseErrorMessage(e),
      );
    }
  }

  /// Pick image from gallery
  static Future<ImagePickResult> _pickFromGallery() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        return ImagePickResult.cancelled();
      }

      return await _buildImageModel(pickedFile.path);
    } on Exception catch (e) {
      return ImagePickResult.error(
        _parseErrorMessage(e),
      );
    }
  }

  /// Pick image from files
  static Future<ImagePickResult> _pickFromFiles() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _supportedExtensions,
        allowMultiple: false,
        withData: false,
        withReadStream: false,
      );

      if (result == null || result.files.isEmpty) {
        return ImagePickResult.cancelled();
      }

      final String? filePath = result.files.single.path;

      if (filePath == null) {
        return ImagePickResult.error('Unable to access file path.');
      }

      return await _buildImageModel(filePath);
    } on Exception catch (e) {
      return ImagePickResult.error(
        _parseErrorMessage(e),
      );
    }
  }

  /// Builds an ImageModel from a given file path
  static Future<ImagePickResult> _buildImageModel(String filePath) async {
    try {
      final File file = File(filePath);

      /// Validate file exists
      if (!await file.exists()) {
        return ImagePickResult.error('Selected file does not exist.');
      }

      /// Get file size in bytes
      final int fileSize = await file.length();

      /// Validate file size (max 10MB)
      if (!_isValidFileSize(fileSize)) {
        return ImagePickResult.error(
          'File size exceeds the 10MB limit. Please select a smaller image.',
        );
      }

      /// Validate file extension
      final String extension = _getFileExtension(filePath);
      if (!_isValidExtension(extension)) {
        return ImagePickResult.error(
          'Unsupported file format. Please select a valid image file.',
        );
      }

      final ImageModel imageModel = ImageModel(
        id: _uuid.v4(),
        path: filePath,
        name: _getFileName(filePath),
        createdAt: DateTime.now(),
        fileSize: fileSize,
      );

      return ImagePickResult.success(imageModel);
    } on Exception catch (e) {
      return ImagePickResult.error(
        _parseErrorMessage(e),
      );
    }
  }

  /// Validates file size (max 10MB)
  static bool _isValidFileSize(int sizeInBytes) {
    const int maxSizeInBytes = 10 * 1024 * 1024;
    return sizeInBytes <= maxSizeInBytes;
  }

  /// Validates file extension
  static bool _isValidExtension(String extension) {
    return _supportedExtensions.contains(extension.toLowerCase());
  }

  /// Extracts file name from path
  static String _getFileName(String filePath) {
    return filePath.split('/').last;
  }

  /// Extracts file extension from path
  static String _getFileExtension(String filePath) {
    final parts = filePath.split('.');
    return parts.isNotEmpty ? parts.last.toLowerCase() : '';
  }

  /// Checks if file still exists on disk
  static Future<bool> fileExists(String filePath) async {
    return await File(filePath).exists();
  }

  /// Returns human-readable file size string
  static String formatFileSize(int sizeInBytes) {
    if (sizeInBytes < 1024) return '$sizeInBytes B';
    if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Parses exception to readable message
  static String _parseErrorMessage(Exception e) {
    final message = e.toString();

    if (message.contains('camera')) {
      return 'Camera access denied. Please enable camera permission in settings.';
    }
    if (message.contains('photo') || message.contains('gallery')) {
      return 'Gallery access denied. Please enable photo permission in settings.';
    }
    if (message.contains('storage')) {
      return 'Storage access denied. Please enable storage permission in settings.';
    }

    return 'Something went wrong. Please try again.';
  }
}