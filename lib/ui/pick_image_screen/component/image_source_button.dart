import 'package:flutter/material.dart';
import 'package:flutter_face_analysis_demo/helper/theme/app_theme.dart';

/// Reusable image source selection button
class ImageSourceButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final Color backgroundColor;
  final bool isLoading;
  final VoidCallback onTap;

  const ImageSourceButton({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.backgroundColor,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<ImageSourceButton> createState() => _ImageSourceButtonState();
}

class _ImageSourceButtonState extends State<ImageSourceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.isLoading) return;
    setState(() => _isPressed = true);
    _animController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _isPressed = false);
    _animController.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _animController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.borderLg,
            border: Border.all(
              color: _isPressed ? widget.color : AppColors.divider,
              width: _isPressed ? 1.5 : 1,
            ),
            boxShadow: _isPressed ? [] : AppShadows.sm,
          ),
          child: Row(
            children: [
              /// Icon container
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.backgroundColor,
                  borderRadius: AppRadius.borderMd,
                ),
                child: Icon(
                  widget.icon,
                  color: widget.color,
                  size: 24,
                ),
              ),

              const SizedBox(width: AppSpacing.lg),

              /// Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: AppTextStyles.headingSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.description,
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),

              /// Trailing - loading or arrow
              widget.isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: widget.color,
                      ),
                    )
                  : Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textHint,
                      size: 22,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
