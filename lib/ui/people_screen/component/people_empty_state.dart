import 'package:flutter/material.dart';
import 'package:flutter_face_analysis_demo/helper/theme/app_theme.dart';

/// Empty state shown on the People tab when no clusters exist yet.
class PeopleEmptyState extends StatelessWidget {
  const PeopleEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
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
              child: const Icon(
                Icons.people_outline_rounded,
                color: AppColors.primary,
                size: 60,
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            Text(
              'No People Yet',
              style: AppTextStyles.headingLarge,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.md),

            Text(
              'Pick photos with faces from the Pick Image tab.\n'
              'Faces will be detected and grouped into people automatically.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.xxl),

            /// Step indicators
            _buildStep(
              icon: Icons.add_photo_alternate_rounded,
              color: AppColors.primary,
              label: 'Pick a photo',
            ),
            const SizedBox(height: AppSpacing.md),
            _buildStep(
              icon: Icons.face_rounded,
              color: AppColors.accent,
              label: 'Faces are detected automatically',
            ),
            const SizedBox(height: AppSpacing.md),
            _buildStep(
              icon: Icons.people_rounded,
              color: AppColors.warning,
              label: 'Similar faces are grouped here',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
