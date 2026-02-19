import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_events.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_state.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_state.dart';
import 'package:flutter_face_analysis_demo/helper/image_picker_helper.dart';
import 'package:flutter_face_analysis_demo/helper/theme/app_theme.dart';
import 'package:flutter_face_analysis_demo/models/cluster_model.dart';
import 'cluster_details_screen.dart';
import 'component/cluster_card.dart';
import 'component/people_empty_state.dart';

/// Displays all detected face clusters — one card per person.
/// Purely driven by FaceBloc state. No setState anywhere.
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context),
      body: BlocBuilder<FaceBloc, FaceState>(
        buildWhen: (prev, curr) =>
        prev.clusters != curr.clusters ||
            prev.isLoadingClusters != curr.isLoadingClusters ||
            prev.isClustering != curr.isClustering ||
            prev.isProcessingImage != curr.isProcessingImage,
        builder: (context, state) {
          /// Full loading (first load)
          if (state.isLoadingClusters && state.clusters.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          /// Empty state — no faces detected yet
          if (state.clusters.isEmpty && !state.isProcessingImage) {
            return const PeopleEmptyState();
          }

          return Column(
            children: [
              /// Stats banner
              _buildStatsBanner(state),

              /// Processing banner (shown while image is being analysed)
              if (state.isProcessingImage || state.isClustering)
                _buildProcessingBanner(state),

              /// Cluster grid
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    context
                        .read<FaceBloc>()
                        .add(RunFullClusteringRequested());
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: AppSpacing.md,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: state.clusters.length,
                    itemBuilder: (context, index) {
                      final cluster = state.clusters[index];
                      return ClusterCard(
                        cluster: cluster,
                        onTap: () => _openClusterDetail(context, cluster),
                        onRename: () =>
                            _showRenameDialog(context, cluster),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context) {
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
            child: const Icon(Icons.people_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          const Text('People'),
          const SizedBox(width: AppSpacing.sm),
          /// Live cluster count badge
          BlocBuilder<FaceBloc, FaceState>(
            buildWhen: (prev, curr) => prev.peopleCount != curr.peopleCount,
            builder: (_, state) {
              if (state.peopleCount == 0) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: AppRadius.borderCircular,
                ),
                child: Text(
                  '${state.peopleCount}',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      actions: [
        /// Re-cluster button
        BlocBuilder<FaceBloc, FaceState>(
          buildWhen: (prev, curr) => prev.isClustering != curr.isClustering,
          builder: (context, state) {
            return IconButton(
              onPressed: state.isClustering
                  ? null
                  : () => context
                  .read<FaceBloc>()
                  .add(RunFullClusteringRequested()),
              tooltip: 'Re-analyse all faces',
              icon: state.isClustering
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              )
                  : const Icon(Icons.refresh_rounded,
                  color: AppColors.textSecondary),
            );
          },
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.divider),
      ),
    );
  }

  // ── Stats banner ─────────────────────────────────────────────

  Widget _buildStatsBanner(FaceState state) {
    final stats = state.stats;
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: AppRadius.borderXl,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat(
            icon: Icons.people_rounded,
            value: '${state.peopleCount}',
            label: 'People',
          ),
          _buildStatDivider(),
          _buildStat(
            icon: Icons.face_rounded,
            value: '${stats?.totalFaces ?? 0}',
            label: 'Faces',
          ),
          _buildStatDivider(),
          _buildStat(
            icon: Icons.help_outline_rounded,
            value: '${stats?.unassignedFaces ?? 0}',
            label: 'Unknown',
          ),
        ],
      ),
    );
  }

  Widget _buildStat(
      {required IconData icon, required String value, required String label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 11,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
        width: 1, height: 40, color: Colors.white.withOpacity(0.2));
  }

  // ── Processing banner ─────────────────────────────────────────

  Widget _buildProcessingBanner(FaceState state) {
    final label = state.isClustering
        ? 'Re-grouping faces…'
        : 'Analysing new photo…';

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: AppRadius.borderLg,
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.primary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────

  void _openClusterDetail(BuildContext context, ClusterModel cluster) {
    context.read<FaceBloc>().add(
      LoadClusterFacesRequested(clusterId: cluster.clusterId),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<FaceBloc>(),
          child: ClusterDetailScreen(cluster: cluster),
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, ClusterModel cluster) {
    final controller =
    TextEditingController(text: cluster.isLabelled ? cluster.label : '');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderXl),
        title: Text('Name this person', style: AppTextStyles.headingMedium),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: cluster.displayName,
            hintStyle: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textHint),
            border: OutlineInputBorder(
                borderRadius: AppRadius.borderLg),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.borderLg,
              borderSide:
              const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<FaceBloc>().add(RenameClusterRequested(
                  clusterId: cluster.clusterId,
                  newLabel: name,
                ));
              }
              Navigator.pop(dialogCtx);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary),
            child: const Text('Save',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
