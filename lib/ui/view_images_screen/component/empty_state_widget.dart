import 'package:flutter/material.dart';
import 'package:flutter_face_analysis_demo/helper/theme/app_theme.dart';

/// Empty state widget shown when no images are saved
class EmptyStateWidget extends StatefulWidget {
  const EmptyStateWidget({super.key});

  @override
  State<EmptyStateWidget> createState() => _EmptyStateWidgetState();
}

class _EmptyStateWidgetState extends State<EmptyStateWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxxl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                /// Illustration container
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      /// Background circle
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                      ),
                      /// Icon
                      const Icon(
                        Icons.photo_library_outlined,
                        color: AppColors.primary,
                        size: 42,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xxl),

                /// Title
                Text(
                  'No Images Yet',
                  style: AppTextStyles.headingLarge,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppSpacing.sm),

                /// Description
                Text(
                  'Your saved images will appear here.\nTap "Pick Image" to get started.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppSpacing.xxxl),

                /// Steps hint
                _buildHintStep(
                  step: '1',
                  icon: Icons.touch_app_rounded,
                  text: 'Go to Pick Image tab',
                ),
                const SizedBox(height: AppSpacing.md),
                _buildHintStep(
                  step: '2',
                  icon: Icons.add_photo_alternate_rounded,
                  text: 'Select camera, gallery or files',
                ),
                const SizedBox(height: AppSpacing.md),
                _buildHintStep(
                  step: '3',
                  icon: Icons.check_circle_outline_rounded,
                  text: 'Image is saved automatically',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHintStep({
    required String step,
    required IconData icon,
    required String text,
  }) {
    return Row(
      children: [
        /// Step number
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

        const SizedBox(width: AppSpacing.md),

        /// Icon
        Icon(
          icon,
          color: AppColors.textSecondary,
          size: 18,
        ),

        const SizedBox(width: AppSpacing.sm),

        /// Text
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
