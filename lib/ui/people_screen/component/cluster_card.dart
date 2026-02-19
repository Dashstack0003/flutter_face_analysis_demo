import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_face_analysis_demo/helper/hive_helper.dart';
import 'package:flutter_face_analysis_demo/helper/theme/app_theme.dart';
import 'package:flutter_face_analysis_demo/models/cluster_model.dart';

/// Displays a single person cluster as a card with:
/// - Representative face thumbnail
/// - Name / auto-generated label
/// - Face count + image count
/// - Tap to view detail, long-press or icon to rename
class ClusterCard extends StatelessWidget {
  final ClusterModel cluster;
  final VoidCallback onTap;
  final VoidCallback onRename;

  const ClusterCard({
    super.key,
    required this.cluster,
    required this.onTap,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onRename,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.borderXl,
          boxShadow: AppShadows.sm,
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            /// Face thumbnail — takes 65% of the card
            Expanded(
              flex: 65,
              child: _RepresentativeThumbnail(
                cluster: cluster,
                onRename: onRename,
              ),
            ),

            /// Info footer
            Expanded(
              flex: 35,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    /// Person name
                    Text(
                      cluster.displayName,
                      style: AppTextStyles.headingSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),

                    /// Face + photo counts
                    Row(
                      children: [
                        const Icon(Icons.face_rounded,
                            size: 11, color: AppColors.textHint),
                        const SizedBox(width: 3),
                        Text(
                          '${cluster.faceCount} faces',
                          style: AppTextStyles.labelSmall
                              .copyWith(fontSize: 10),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        const Icon(Icons.photo_rounded,
                            size: 11, color: AppColors.textHint),
                        const SizedBox(width: 3),
                        Text(
                          '${cluster.imageCount} photos',
                          style: AppTextStyles.labelSmall
                              .copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Representative face thumbnail
// Loads the face crop from disk using the cluster's representativeFaceId
// ─────────────────────────────────────────────────────────────────────────────

class _RepresentativeThumbnail extends StatelessWidget {
  final ClusterModel cluster;
  final VoidCallback onRename;

  const _RepresentativeThumbnail({
    required this.cluster,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    /// Use FutureBuilder to load the representative face crop path from Hive
    return FutureBuilder<String?>(
      future: _loadRepresentativeCropPath(),
      builder: (context, snapshot) {
        final path = snapshot.data;

        return Stack(
          fit: StackFit.expand,
          children: [
            /// Face image or placeholder
            if (path != null && File(path).existsSync())
              Image.file(File(path), fit: BoxFit.cover)
            else
              _buildPlaceholder(),

            /// Dark gradient at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            /// Label/rename button top-right
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: GestureDetector(
                onTap: onRename,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ),

            /// Unlabelled badge top-left
            if (!cluster.isLabelled)
              Positioned(
                top: AppSpacing.xs,
                left: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: AppRadius.borderCircular,
                  ),
                  child: Text(
                    'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Loads the representative face crop path from Hive
  Future<String?> _loadRepresentativeCropPath() async {
    if (cluster.representativeFaceId == null) return null;
    final face = await HiveHelper.getFaceById(cluster.representativeFaceId!);
    return face?.croppedFacePath;
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.primaryLight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person_rounded,
              color: AppColors.primary, size: 40),
          const SizedBox(height: 4),
          Text(
            cluster.displayName[0].toUpperCase(),
            style: AppTextStyles.displayLarge
                .copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
