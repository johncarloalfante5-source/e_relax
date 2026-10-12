import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class BookingStepIndicatorWidget extends StatelessWidget {
  final int currentStep;

  const BookingStepIndicatorWidget({super.key, required this.currentStep});

  static const List<String> _stepLabels = ['Select', 'Review', 'Payment'];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: List.generate(_stepLabels.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line
            final stepIndex = i ~/ 2;
            final isCompleted = stepIndex < currentStep;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 2,
                color: isCompleted
                    ? AppTheme.primary
                    : AppTheme.surfaceVariantLight,
              ),
            );
          } else {
            final stepIndex = i ~/ 2;
            final isCompleted = stepIndex < currentStep;
            final isActive = stepIndex == currentStep;
            return Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppTheme.primary
                        : isActive
                        ? AppTheme.primary
                        : AppTheme.surfaceVariantLight,
                    shape: BoxShape.circle,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppTheme.primary.withAlpha(89),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [],
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 16,
                          )
                        : Text(
                            '${stepIndex + 1}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isActive
                                  ? Colors.white
                                  : AppTheme.onSurfaceVariantLight,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _stepLabels[stepIndex],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    color: isActive
                        ? AppTheme.primary
                        : AppTheme.onSurfaceVariantLight,
                  ),
                ),
              ],
            );
          }
        }),
      ),
    );
  }
}
