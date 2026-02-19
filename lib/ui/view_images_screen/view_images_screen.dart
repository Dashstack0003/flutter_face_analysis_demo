import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_state.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_events.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_state.dart';
import 'package:flutter_face_analysis_demo/helper/theme/app_theme.dart';
import 'component/image_grid_item.dart';
import 'component/empty_state_widget.dart';

class ViewImagesScreen extends StatelessWidget {
  const ViewImagesScreen({super.key});

  void _onDeleteSelected(BuildContext context, List<String> ids) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderXl),
        title: Text(
          'Delete ${ids.length} ${ids.length == 1 ? 'Image' : 'Images'}?',
          style: AppTextStyles.headingMedium,
        ),
        content: Text(
          'This action cannot be undone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<ImageBloc>().add(
                DeleteMultipleImagesRequested(imageIds: ids),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _onClearAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderXl),
        title: Text(
          'Clear All Images?',
          style: AppTextStyles.headingMedium,
        ),
        content: Text(
          'All saved images will be permanently deleted. This cannot be undone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<ImageBloc>().add(ClearAllImagesRequested());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ImageBloc, ImageState>(
      buildWhen: (previous, current) =>
      previous.images != current.images ||
          previous.isSelectionMode != current.isSelectionMode ||
          previous.selectedImageIds != current.selectedImageIds ||
          previous.isLoadingImages != current.isLoadingImages ||
          previous.isDeletingImage != current.isDeletingImage,
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: _buildAppBar(context, state),
          body: _buildBody(context, state),

          /// Selection mode bottom action bar
          bottomNavigationBar: state.isSelectionMode
              ? _buildSelectionActionBar(context, state)
              : null,
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context,
      ImageState state,
      ) {
    return AppBar(
      backgroundColor: AppColors.surface,
      title: state.isSelectionMode
          ? Text(
        '${state.selectedCount} Selected',
        style: AppTextStyles.headingLarge,
      )
          : Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: AppRadius.borderMd,
            ),
            child: const Icon(
              Icons.photo_library_rounded,
              color: AppColors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Text('My Images'),
          const SizedBox(width: AppSpacing.sm),
          if (state.totalImageCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: AppRadius.borderCircular,
              ),
              child: Text(
                '${state.totalImageCount}',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      actions: [
        if (state.isSelectionMode) ...[
          /// Select all toggle
          TextButton(
            onPressed: () {
              if (state.isAllSelected) {
                context
                    .read<ImageBloc>()
                    .add(DeselectAllImagesRequested());
              } else {
                context
                    .read<ImageBloc>()
                    .add(SelectAllImagesRequested());
              }
            },
            child: Text(
              state.isAllSelected ? 'Deselect All' : 'Select All',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),

          /// Cancel selection
          IconButton(
            onPressed: () => context.read<ImageBloc>().add(
              const ToggleSelectionModeRequested(
                isSelectionMode: false,
              ),
            ),
            icon: const Icon(Icons.close_rounded),
          ),
        ] else if (state.images.isNotEmpty) ...[
          /// Clear all button
          IconButton(
            onPressed: () => _onClearAll(context),
            icon: const Icon(
              Icons.delete_sweep_rounded,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.divider),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ImageState state) {
    /// Loading state
    if (state.isLoadingImages) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    /// Empty state
    if (state.isEmpty) {
      return const EmptyStateWidget();
    }

    /// Grid + optional deleting overlay
    return Stack(
      children: [
        /// Read face processing state for per-image badges
        BlocBuilder<FaceBloc, FaceState>(
          buildWhen: (prev, curr) =>
          prev.isProcessingImage != curr.isProcessingImage ||
              prev.stats != curr.stats,
          builder: (context, faceState) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: AppSpacing.sm,
                  mainAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1,
                ),
                itemCount: state.images.length,
                itemBuilder: (context, index) {
                  final image = state.images[index];
                  final isSelected = state.selectedImageIds.contains(image.id);

                  return ImageGridItem(
                    image: image,
                    isSelected: isSelected,
                    isSelectionMode: state.isSelectionMode,
                    isProcessing: faceState.isProcessingImage &&
                        index == 0, // newest image being processed
                    onTap: () {
                      if (state.isSelectionMode) {
                        context.read<ImageBloc>().add(
                          ToggleImageSelectionRequested(imageId: image.id),
                        );
                      }
                    },
                    onLongPress: () {
                      if (!state.isSelectionMode) {
                        context.read<ImageBloc>()
                          ..add(const ToggleSelectionModeRequested(
                              isSelectionMode: true))
                          ..add(ToggleImageSelectionRequested(
                              imageId: image.id));
                      }
                    },
                    onDelete: () => context.read<ImageBloc>().add(
                      DeleteImageRequested(imageId: image.id),
                    ),
                  );
                },
              ),
            );
          },
        ),

        /// Deleting overlay
        if (state.isDeletingImage)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _buildSelectionActionBar(
      BuildContext context,
      ImageState state,
      ) {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider),
        ),
        boxShadow: AppShadows.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${state.selectedCount} ${state.selectedCount == 1 ? 'image' : 'images'} selected',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: state.hasSelectedImages
                ? () => _onDeleteSelected(context, state.selectedImageIds)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              disabledBackgroundColor: AppColors.divider,
            ),
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
