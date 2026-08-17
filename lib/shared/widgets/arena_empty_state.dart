import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_colors.dart';

class ArenaEmptyState extends StatelessWidget {
  const ArenaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.showFieldBackground = true,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showFieldBackground;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final artworkHeight = (constraints.maxWidth * .54).clamp(150.0, 230.0);
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 60).clamp(0, double.infinity),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showFieldBackground)
                SizedBox(
                  height: artworkHeight,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: .13,
                          child: Image.asset(
                            'assets/images/empty_field_background.png',
                            fit: BoxFit.cover,
                            alignment: Alignment.bottomCenter,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .9),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.navy.withValues(alpha: .14),
                          ),
                        ),
                        child: Icon(icon, size: 38, color: AppColors.navy),
                      ),
                    ],
                  ),
                )
              else
                Icon(icon, size: 64, color: AppColors.navy),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.hint,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (onAction != null) ...[
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: onAction,
                  child: Text(actionLabel ?? tr('Try again', 'حاول مرة أخرى')),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
