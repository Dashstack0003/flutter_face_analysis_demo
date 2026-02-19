// Replace the ClusterDetailScreen class in people_screen.dart with this:

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_state.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_state.dart';
import 'package:flutter_face_analysis_demo/helper/image_picker_helper.dart';
import 'package:flutter_face_analysis_demo/helper/theme/app_theme.dart';
import 'package:flutter_face_analysis_demo/models/cluster_model.dart';

class ClusterDetailScreen extends StatelessWidget {
  final ClusterModel cluster;

  const ClusterDetailScreen({super.key, required this.cluster});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: AppRadius.borderMd,
              child: _ClusterAvatar(cluster: cluster, size: 36),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BlocBuilder<FaceBloc, FaceState>(
                  buildWhen: (prev, curr) => prev.clusters != curr.clusters,
                  builder: (_, state) {
                    final updated = state.clusters.firstWhere(
                          (c) => c.clusterId == cluster.clusterId,
                      orElse: () => cluster,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(updated.displayName,
                            style: AppTextStyles.headingMedium),
                        Text(
                          '${updated.faceCount} faces · ${updated.imageCount} photos',
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      // Show full photos from ImageBloc filtered by the live cluster's imageIds
      body: BlocBuilder<FaceBloc, FaceState>(
        buildWhen: (prev, curr) => prev.clusters != curr.clusters,
        builder: (context, faceState) {
          final liveCluster = faceState.clusters.firstWhere(
            (c) => c.clusterId == cluster.clusterId,
            orElse: () => cluster,
          );
          return BlocBuilder<ImageBloc, ImageState>(
            buildWhen: (prev, curr) => prev.images != curr.images,
            builder: (context, state) {
              final clusterImages = state.images
                  .where((img) => liveCluster.imageIds.contains(img.id))
                  .toList();

          if (clusterImages.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.photo_library_outlined,
                      color: AppColors.textHint, size: 48),
                  const SizedBox(height: AppSpacing.md),
                  Text('No photos found for this person',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              childAspectRatio: 1,
            ),
            itemCount: clusterImages.length,
            itemBuilder: (context, index) {
              final image = clusterImages[index];
              return ClipRRect(
                borderRadius: AppRadius.borderMd,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Full photo from original image
                    Image.file(
                      File(image.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.surfaceVariant,
                        child: const Icon(Icons.broken_image_outlined,
                            color: AppColors.textHint, size: 32),
                      ),
                    ),

                    // Gradient overlay at bottom
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 30,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.6),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // File size badge bottom-right
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: AppRadius.borderCircular,
                        ),
                        child: Text(
                          ImagePickerHelper.formatFileSize(image.fileSize),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
            },
          );
        },
      ),
    );
  }
}


class _ClusterAvatar extends StatelessWidget {
  final ClusterModel cluster;
  final double size;

  const _ClusterAvatar({required this.cluster, this.size = 60});

  @override
  Widget build(BuildContext context) {
    // We load the representative face from the FaceBloc's face list
    // via the croppedFacePath stored in the face. For now we show
    // a placeholder with initials — the real thumbnail is shown in ClusterCard.
    return BlocBuilder<FaceBloc, FaceState>(
      buildWhen: (prev, curr) =>
      prev.selectedClusterFaces != curr.selectedClusterFaces,
      builder: (_, state) {
        final face = state.selectedClusterFaces.isNotEmpty
            ? state.selectedClusterFaces.first
            : null;

        if (face?.croppedFacePath != null &&
            File(face!.croppedFacePath!).existsSync()) {
          return Image.file(
            File(face.croppedFacePath!),
            width: size,
            height: size,
            fit: BoxFit.cover,
          );
        }

        return Container(
          width: size,
          height: size,
          color: AppColors.primaryLight,
          child: Center(
            child: Text(
              cluster.displayName.isNotEmpty
                  ? cluster.displayName[0].toUpperCase()
                  : '?',
              style: AppTextStyles.headingMedium
                  .copyWith(color: AppColors.primary),
            ),
          ),
        );
      },
    );
  }
}