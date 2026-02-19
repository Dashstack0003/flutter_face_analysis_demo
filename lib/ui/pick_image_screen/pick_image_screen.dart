import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_events.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_state.dart';
import 'package:flutter_face_analysis_demo/helper/theme/app_theme.dart';
import 'package:flutter_face_analysis_demo/services/tflite_service.dart';
import 'package:flutter_face_analysis_demo/ui/debug_screen/ml_debug_screen.dart';
import '../../helper/image_picker_helper.dart';
import 'component/image_source_button.dart';

class PickImageScreen extends StatelessWidget {
  final TFLiteService tfliteService;
  const PickImageScreen({super.key, required this.tfliteService});

  void _onSourceSelected(BuildContext context, ImageSourceType source) {
    context.read<ImageBloc>().add(PickImageRequested(source: source));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: BlocBuilder<ImageBloc, ImageState>(
        buildWhen: (previous, current) =>
            previous.isPickingImage != current.isPickingImage ||
            previous.totalImageCount != current.totalImageCount,
        builder: (context, state) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Header banner
                  _buildHeaderBanner(context, state),

                  const SizedBox(height: AppSpacing.xxl),

                  /// Section title
                  Text('Select Source', style: AppTextStyles.headingMedium),

                  const SizedBox(height: AppSpacing.sm),

                  Text(
                    'Choose where you\'d like to import your image from.',
                    style: AppTextStyles.bodySmall,
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  /// Source buttons
                  ImageSourceButton(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    description: 'Take a new photo',
                    color: AppColors.primary,
                    backgroundColor: AppColors.primaryLight,
                    isLoading: state.isPickingImage,
                    onTap: () =>
                        _onSourceSelected(context, ImageSourceType.camera),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  ImageSourceButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    description: 'Pick from your photos',
                    color: AppColors.accent,
                    backgroundColor: AppColors.accentLight,
                    isLoading: state.isPickingImage,
                    onTap: () =>
                        _onSourceSelected(context, ImageSourceType.gallery),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  ImageSourceButton(
                    icon: Icons.folder_rounded,
                    label: 'Files',
                    description: 'Browse from file manager',
                    color: AppColors.warning,
                    backgroundColor: AppColors.warningLight,
                    isLoading: state.isPickingImage,
                    onTap: () =>
                        _onSourceSelected(context, ImageSourceType.files),
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MLDebugScreen(
                          tfliteService: tfliteService, // pass from main.dart
                        ),
                      ),
                    ),
                    child: const Text('🐛 Debug ML'),
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  /// Supported formats info
                  _buildSupportedFormatsCard(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: AppRadius.borderMd,
            ),
            child: const Icon(
              Icons.add_photo_alternate_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Text('Pick Image'),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.divider),
      ),
    );
  }

  Widget _buildHeaderBanner(BuildContext context, ImageState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: AppRadius.borderXl,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: AppRadius.borderMd,
                ),
                child: const Icon(
                  Icons.photo_size_select_actual_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                'Image Vault',
                style: AppTextStyles.headingLarge.copyWith(color: Colors.white),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          Text(
            'Store and manage your images\nlocally on your device.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.white.withOpacity(0.85),
              height: 1.5,
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          /// Stats row
          Row(
            children: [
              _buildStatChip(
                icon: Icons.image_rounded,
                value: '${state.totalImageCount}',
                label: 'Images',
              ),
              const SizedBox(width: AppSpacing.md),
              _buildStatChip(
                icon: Icons.storage_rounded,
                value: state.totalStorageUsed,
                label: 'Used',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: AppRadius.borderLg,
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$value  $label',
            style: AppTextStyles.labelSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportedFormatsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.borderLg,
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.textSecondary,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Supported Formats',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'JPG, JPEG, PNG, GIF, WEBP, BMP, HEIC, HEIF  •  Max size: 10MB',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}
