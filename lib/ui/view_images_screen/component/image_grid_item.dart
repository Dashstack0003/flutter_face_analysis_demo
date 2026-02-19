import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_face_analysis_demo/helper/theme/app_theme.dart';
import '../../../helper/image_picker_helper.dart';
import '../../../models/image_model.dart';

/// Grid item widget for displaying a single image
class ImageGridItem extends StatelessWidget {
  final ImageModel image;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isProcessing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const ImageGridItem({
    super.key,
    required this.image,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: AppRadius.borderMd,
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            isSelected ? AppRadius.borderMd.topLeft.x - 2 : AppRadius.borderMd.topLeft.x,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              /// Image
              _buildImage(),

              /// Gradient overlay (always visible at bottom for metadata)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    ImagePickerHelper.formatFileSize(image.fileSize),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: Colors.white,
                      fontSize: 9,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              /// ML processing indicator
              if (isProcessing)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.25),
                      borderRadius: AppRadius.borderMd,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

              /// Selection checkbox
              if (isSelectionMode)
                Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.black.withOpacity(0.35),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 13,
                    )
                        : null,
                  ),
                ),

              /// Delete button (non-selection mode)
              if (!isSelectionMode)
                Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.50),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    final file = File(image.path);

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        final fileExists = snapshot.data ?? false;

        if (!fileExists) {
          return _buildErrorPlaceholder();
        }

        return Image.file(
          file,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return _buildLoadingPlaceholder();
          },
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorPlaceholder();
          },
        );
      },
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      color: AppColors.surfaceVariant,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: AppColors.textHint,
            size: 22,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Not found',
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}
