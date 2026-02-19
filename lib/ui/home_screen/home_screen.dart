import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_events.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_state.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_events.dart';
import 'package:flutter_face_analysis_demo/bloc/image_bloc/image_state.dart';
import 'package:flutter_face_analysis_demo/helper/theme/app_theme.dart';
import 'package:flutter_face_analysis_demo/services/tflite_service.dart';
import 'package:flutter_face_analysis_demo/ui/people_screen/people_screen.dart';
import '../pick_image_screen/pick_image_screen.dart';
import '../view_images_screen/view_images_screen.dart';
import 'component/bottom_nav_bar.dart';

class HomeScreen extends StatefulWidget {
  final TFLiteService tfliteService;

  const HomeScreen({super.key, required this.tfliteService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _pageController;

  late final List<Widget> _screens = [
    PickImageScreen(tfliteService: widget.tfliteService),
    ViewImagesScreen(),
    PeopleScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNavItemTapped(int index) {
    context.read<ImageBloc>().add(UpdateBottomNavIndexRequested(index: index));
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        /// ── ImageBloc listener ──────────────────────────────────────
        /// When a new image is successfully picked → fire ML pipeline
        BlocListener<ImageBloc, ImageState>(
          listenWhen: (prev, curr) =>
              prev.lastPickedImage != curr.lastPickedImage &&
              curr.lastPickedImage != null &&
              curr.status == ImageOperationStatus.success,
          listener: (context, state) {
            /// Trigger face processing for the newly saved image
            context.read<FaceBloc>().add(
              ProcessImageRequested(image: state.lastPickedImage!),
            );
            _showSuccessSnackBar(context, 'Image saved — analysing faces…');
          },
        ),

        /// ── ImageBloc error listener ────────────────────────────────
        BlocListener<ImageBloc, ImageState>(
          listenWhen: (prev, curr) =>
              prev.hasError != curr.hasError && curr.hasError,
          listener: (context, state) {
            _showErrorSnackBar(context, state.errorMessage);
            context.read<ImageBloc>().add(ResetErrorRequested());
          },
        ),

        /// ── FaceBloc listener ───────────────────────────────────────
        /// Show processing result feedback
        BlocListener<FaceBloc, FaceState>(
          listenWhen: (prev, curr) =>
              prev.status != curr.status &&
              curr.status == FaceOperationStatus.success &&
              curr.clusters.isNotEmpty,
          listener: (context, state) {
            final count = state.clusters.length;
            _showFaceSnackBar(
              context,
              count == 1 ? '1 person identified' : '$count people identified',
            );
          },
        ),

        /// ── FaceBloc error listener ─────────────────────────────────
        BlocListener<FaceBloc, FaceState>(
          listenWhen: (prev, curr) =>
              prev.hasError != curr.hasError && curr.hasError,
          listener: (context, state) {
            _showErrorSnackBar(context, state.errorMessage);
            context.read<FaceBloc>().add(ResetFaceErrorRequested());
          },
        ),
      ],

      /// ── Builder ─────────────────────────────────────────────────
      child: BlocBuilder<ImageBloc, ImageState>(
        buildWhen: (prev, curr) =>
            prev.currentBottomNavIndex != curr.currentBottomNavIndex,
        builder: (context, state) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: _screens,
            ),
            bottomNavigationBar: AppBottomNavBar(
              currentIndex: state.currentBottomNavIndex,
              onTap: _onNavItemTapped,
            ),
          );
        },
      ),
    );
  }

  // ── SnackBars ──────────────────────────────────────────────────

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.all(AppSpacing.lg),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(AppSpacing.lg),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showFaceSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.face_rounded, color: Colors.white, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(AppSpacing.lg),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () => _onNavItemTapped(2), // jump to People tab
          ),
        ),
      );
  }
}
