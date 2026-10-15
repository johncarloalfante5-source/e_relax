import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/payment_booking_store.dart';
import '../../../data/therapist_roster_store.dart';
import '../../../theme/app_theme.dart';

class TherapistSelectorWidget extends StatefulWidget {
  static const anyTherapistId = '__any_therapist__';

  final String? selectedTherapistId;
  final void Function(String) onTherapistSelected;
  final DateTime? selectedDate;
  final String? selectedTimeSlot;
  final int durationMinutes;
  final String? serviceId;
  final String? serviceName;

  const TherapistSelectorWidget({
    super.key,
    required this.selectedTherapistId,
    required this.onTherapistSelected,
    this.selectedDate,
    this.selectedTimeSlot,
    this.durationMinutes = 60,
    this.serviceId,
    this.serviceName,
  });

  @override
  State<TherapistSelectorWidget> createState() => _TherapistSelectorWidgetState();
}

class _TherapistSelectorWidgetState extends State<TherapistSelectorWidget> {
  static const _availabilityRefreshInterval = Duration(seconds: 10);

  Timer? _availabilityTimer;
  Set<String>? _availableTherapistIds;
  String? _requestKey;
  String? _availabilityError;
  bool _isLoadingAvailability = false;

  @override
  void initState() {
    super.initState();
    _availabilityTimer = Timer.periodic(
      _availabilityRefreshInterval,
      (_) => _refreshAvailability(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshAvailability();
    });
  }

  @override
  void didUpdateWidget(covariant TherapistSelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.selectedTimeSlot != widget.selectedTimeSlot ||
        oldWidget.durationMinutes != widget.durationMinutes ||
        oldWidget.serviceId != widget.serviceId) {
      _availableTherapistIds = null;
      _availabilityError = null;
      _requestKey = null;
      _refreshAvailability();
    }
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    super.dispose();
  }

  String? get _currentRequestKey {
    final date = widget.selectedDate;
    final time = widget.selectedTimeSlot;
    if (date == null || time == null || widget.serviceId == null) return null;
    return '${date.year}-${date.month}-${date.day}|$time|${widget.durationMinutes}|${widget.serviceId}';
  }

  Future<void> _refreshAvailability() async {
    final date = widget.selectedDate;
    final time = widget.selectedTimeSlot;
    final serviceId = widget.serviceId;
    final requestKey = _currentRequestKey;
    if (date == null || time == null || serviceId == null || serviceId.isEmpty) {
      if (mounted &&
          (_availableTherapistIds != null ||
              _availabilityError != null ||
              _isLoadingAvailability)) {
        setState(() {
          _availableTherapistIds = null;
          _availabilityError = null;
          _requestKey = null;
          _isLoadingAvailability = false;
        });
      }
      return;
    }
    if (_isLoadingAvailability && requestKey == _requestKey) return;

    setState(() {
      _requestKey = requestKey;
      _isLoadingAvailability = true;
      _availabilityError = null;
    });
    try {
      final available = await TherapistRosterStore.instance.availableForBookingRemote(
        date: date,
        startTime: time,
        durationMinutes: widget.durationMinutes,
        serviceId: serviceId,
      );
      if (!mounted || requestKey != _currentRequestKey) return;
      setState(() {
        _availableTherapistIds = available.map((therapist) => therapist.id).toSet();
        _availabilityError = null;
        _isLoadingAvailability = false;
      });
    } catch (error) {
      if (!mounted || requestKey != _currentRequestKey) return;
      setState(() {
        _availableTherapistIds = <String>{};
        _availabilityError = error.toString();
        _isLoadingAvailability = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      TherapistRosterStore.instance,
      PaymentBookingStore.instance,
    ]),
    builder: (context, _) {
      final date = widget.selectedDate;
      final time = widget.selectedTimeSlot;
      if (date == null || time == null) {
        return _availabilityMessage(
          'Choose a date and time to see therapists assigned and available for that appointment.',
        );
      }

      final assigned = TherapistRosterStore.instance.onDutyForDate(date);
      if (assigned.isEmpty) {
        return _availabilityMessage(
          'No therapists are assigned to work on this date. Choose another date or contact the clinic.',
        );
      }
      final availableIds = _availableTherapistIds ?? const <String>{};

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer.withAlpha(128),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primary.withAlpha(51)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.primary,
                  size: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Busy therapists are grayed out. Availability refreshes automatically.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppTheme.primary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_availabilityError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Could not refresh availability. Busy therapists are disabled; retrying automatically.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: AppTheme.error,
                ),
              ),
            )
          else if (_isLoadingAvailability && _availableTherapistIds == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: assigned.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isAvailable = availableIds.isNotEmpty &&
                      _availabilityError == null;
                  final isSelected =
                      widget.selectedTherapistId ==
                          TherapistSelectorWidget.anyTherapistId &&
                      isAvailable;
                  return GestureDetector(
                    onTap: isAvailable
                        ? () => widget.onTherapistSelected(
                            TherapistSelectorWidget.anyTherapistId,
                          )
                        : null,
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.secondary
                                  : isAvailable
                                  ? AppTheme.primary.withAlpha(51)
                                  : AppTheme.onSurfaceVariantLight.withAlpha(90),
                              width: isSelected ? 3 : 2,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: AppTheme.secondary.withAlpha(102),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: ClipOval(
                            child: ColoredBox(
                              color: isAvailable
                                  ? AppTheme.primaryContainer
                                  : AppTheme.surfaceVariantLight,
                              child: Icon(
                                Icons.auto_awesome,
                                color: isAvailable
                                    ? AppTheme.primary
                                    : AppTheme.onSurfaceVariantLight,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Any therapist',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isAvailable
                                ? (isSelected
                                      ? AppTheme.primary
                                      : AppTheme.onSurfaceLight)
                                : AppTheme.onSurfaceVariantLight,
                          ),
                        ),
                        Text(
                          isAvailable ? 'Auto assign' : 'Unavailable',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: AppTheme.onSurfaceVariantLight,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final therapist = assigned[index];
                final isAvailable = availableIds.contains(therapist.id) &&
                    _availabilityError == null;
                final isSelected =
                    widget.selectedTherapistId == therapist.id && isAvailable;
                return GestureDetector(
                  onTap: isAvailable
                      ? () => widget.onTherapistSelected(therapist.id)
                      : null,
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.secondary
                                : isAvailable
                                    ? AppTheme.primary.withAlpha(51)
                                    : AppTheme.onSurfaceVariantLight.withAlpha(90),
                            width: isSelected ? 3 : 2,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.secondary.withAlpha(102),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        child: ClipOval(
                          child: ColoredBox(
                            color: isAvailable
                                ? AppTheme.primaryContainer
                                : AppTheme.surfaceVariantLight,
                            child: Center(
                              child: Text(
                                isAvailable
                                    ? _therapistInitials(therapist.name)
                                    : '×',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: isAvailable
                                      ? AppTheme.primary
                                      : AppTheme.onSurfaceVariantLight,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        therapist.name.split(' ').first,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        color: isAvailable
                            ? (isSelected
                                ? AppTheme.primary
                                : AppTheme.onSurfaceLight)
                            : AppTheme.onSurfaceVariantLight,
                        ),
                      ),
                      Text(
                        isAvailable ? therapist.specialty : 'Booked',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: AppTheme.onSurfaceVariantLight,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );

  Widget _availabilityMessage(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.primary.withAlpha(40)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: AppTheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    ),
  );

  String _therapistInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
    final initials = parts.take(2).map((part) => part[0].toUpperCase()).join();
    return initials.isEmpty ? '?' : initials;
  }
}
