import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_bloc.dart';
import 'package:flutter_face_analysis_demo/bloc/face_bloc/face_state.dart';
import 'package:flutter_face_analysis_demo/helper/theme/app_theme.dart';

/// Data model for each nav item
class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// Custom bottom navigation bar
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const List<_NavItem> _navItems = [
    _NavItem(
      icon: Icons.add_photo_alternate_outlined,
      activeIcon: Icons.add_photo_alternate_rounded,
      label: 'Pick Image',
    ),
    _NavItem(
      icon: Icons.photo_library_outlined,
      activeIcon: Icons.photo_library_rounded,
      label: 'My Images',
    ),
    _NavItem(
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      label: 'People',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        boxShadow: AppShadows.md,
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: BlocBuilder<FaceBloc, FaceState>(
            buildWhen: (prev, curr) =>
            prev.isProcessingImage != curr.isProcessingImage ||
                prev.peopleCount != curr.peopleCount,
            builder: (context, faceState) {
              return Row(
                children: List.generate(
                  _navItems.length,
                      (index) => _NavBarItem(
                    item: _navItems[index],
                    isSelected: currentIndex == index,
                    onTap: () => onTap(index),
                    // Show spinner on People tab while processing
                    isProcessing: index == 2 && faceState.isProcessingImage,
                    // Show count badge on People tab
                    badgeCount: index == 2 && faceState.peopleCount > 0
                        ? faceState.peopleCount
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Individual nav bar item with animated indicator
class _NavBarItem extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isProcessing;
  final int? badgeCount;

  const _NavBarItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
    this.isProcessing = false,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              /// Icon with optional badge / spinner
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    padding: EdgeInsets.symmetric(
                      horizontal: isSelected ? AppSpacing.lg : AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryLight
                          : Colors.transparent,
                      borderRadius: AppRadius.borderCircular,
                    ),
                    child: Icon(
                      isSelected ? item.activeIcon : item.icon,
                      color: isSelected
                          ? AppColors.bottomNavSelected
                          : AppColors.bottomNavUnselected,
                      size: 22,
                    ),
                  ),

                  /// Processing spinner overlay
                  if (isProcessing)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  /// People count badge
                  else if (badgeCount != null)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          badgeCount! > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 3),

              /// Label
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: AppTextStyles.labelSmall.copyWith(
                  color: isSelected
                      ? AppColors.bottomNavSelected
                      : AppColors.bottomNavUnselected,
                  fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                child: Text(item.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
