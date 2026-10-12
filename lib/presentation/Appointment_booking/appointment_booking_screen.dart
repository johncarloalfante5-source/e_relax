import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/payment_booking_store.dart';
import '../../data/service_catalog.dart';
import '../../data/therapist_roster_store.dart';
import '../../models/booking.dart';
import '../../services/booking_receipt_service.dart';
import '../../theme/app_theme.dart';
import '../../widget/custom_icon_widget.dart';
import './widget/booking_service_detail_widget.dart';
import './widget/booking_step_indicator_widget.dart';
import './widget/booking_summary_step_widget.dart';
import './widget/day_selector_widget.dart';
import './widget/payment_step_widget.dart';
import './widget/therapist_selector_widget.dart';
import './widget/time_slot_widget.dart';

class AppointmentBookingScreen extends StatefulWidget {
  final Map<String, dynamic>? serviceData;

  const AppointmentBookingScreen({super.key, this.serviceData});

  @override
  State<AppointmentBookingScreen> createState() =>
      _AppointmentBookingScreenState();
}

class _AppointmentBookingScreenState extends State<AppointmentBookingScreen>
    with TickerProviderStateMixin {
  // TODO: Replace with [Riverpod/Bloc] for production
  int _currentStep = 0; // 0 = Select, 1 = Review, 2 = Payment
  bool _isLoading = false;

  // Booking selections
  DateTime? _selectedDate;
  String? _selectedTimeSlot;
  String? _selectedTherapistId;
  String _paymentReference = '';
  Uint8List? _paymentScreenshot;
  Booking? _booking;

  late PageController _pageController;
  late AnimationController _stepAnimController;

  // Default service data if none passed
  late Map<String, dynamic> _serviceData;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _stepAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();

    _serviceData = widget.serviceData ?? ServiceCatalog.services.first;

    _selectedDate = DateTime.now().add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _pageController.dispose();
    _stepAnimController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0) {
      // Validate step 1
      if (_selectedTimeSlot == null) {
        _showError('Please select a time slot');
        return;
      }
      if (_selectedTherapistId == null) {
        _showError('Please select a therapist');
        return;
      }
      if (!_selectedTherapistIsAvailable()) {
        setState(() => _selectedTherapistId = null);
        _showError('That therapist is no longer available. Choose again.');
        return;
      }
    }
    if (_currentStep == 1) {
      // Show down payment notice on step 2 → step 3
    }

    if (_currentStep < 2) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      context.pop();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _submitBooking() async {
    if (!_selectedTherapistIsAvailable()) {
      setState(() {
        _selectedTherapistId = null;
        _currentStep = 0;
      });
      _pageController.jumpToPage(0);
      _showError('That therapist is no longer available. Please choose again.');
      return;
    }
    if (_paymentReference.trim().isEmpty) {
      _showError('Enter your transaction reference number');
      return;
    }
    if (_paymentScreenshot == null) {
      _showError('Upload your payment screenshot');
      return;
    }
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final bookingReference = 'ER-${now.millisecondsSinceEpoch}';
    final booking = Booking(
      id: bookingReference,
      referenceNumber: bookingReference,
      clientId: localClientSessionId,
      clientName: localClientSessionName,
      serviceId: _serviceData['id']?.toString() ?? 'service-unknown',
      serviceName: _serviceData['name'] as String,
      serviceDescription: _serviceData['description']?.toString() ?? '',
      therapistId: _selectedTherapistId ?? 'Not selected',
      therapistName: _therapistName(_selectedTherapistId),
      appointmentDate: _selectedDate ?? now,
      startTime: _selectedTimeSlot ?? 'Not selected',
      durationMinutes: (_serviceData['durationMinutes'] as num?)?.toInt() ?? 60,
      totalAmount: (_serviceData['price'] as num).toDouble(),
      transactionReference: _paymentReference.trim(),
      paymentAmount: Booking.calculateDownPayment(
        (_serviceData['price'] as num).toDouble(),
      ),
      receiptImage: _paymentScreenshot!,
      paymentSubmittedAt: now,
      createdAt: now,
    );
    PaymentBookingStore.instance.add(booking);
    if (!mounted) return;
    setState(() {
      _booking = booking;
      _isLoading = false;
    });
    _showSuccessDialog();
  }

  bool _selectedTherapistIsAvailable() {
    final therapistId = _selectedTherapistId;
    final date = _selectedDate;
    final time = _selectedTimeSlot;
    if (therapistId == null || date == null || time == null) return false;
    final duration = (_serviceData['durationMinutes'] as num?)?.toInt() ?? 60;
    return TherapistRosterStore.instance
        .availableForBooking(
          date: date,
          startTime: time,
          durationMinutes: duration,
        )
        .any((therapist) => therapist.id == therapistId);
  }

  String _therapistName(String? therapistId) => switch (therapistId) {
    'th_001' => 'Ana Reyes',
    'th_002' => 'Carlo Mendoza',
    'th_003' => 'Liza Cruz',
    'th_004' => 'Rico Santos',
    _ => therapistId ?? 'Not selected',
  };

  Future<void> _downloadReceipt() async {
    final booking = _booking;
    if (booking != null) await BookingReceiptService.download(booking);
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.primary,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Booking Submitted!',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your reservation is now pending admin verification. You will be notified once your booking is confirmed.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppTheme.onSurfaceVariantLight,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _downloadReceipt,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Download receipt (PDF)'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Back to Dashboard',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _ctaLabel {
    switch (_currentStep) {
      case 0:
        return 'Continue to Review';
      case 1:
        return 'Proceed to Payment';
      case 2:
        return 'Submit Booking';
      default:
        return 'Continue';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: Column(
        children: [
          // Hero image + back button (fixed)
          _buildHeroSection(),

          // Step indicator
          BookingStepIndicatorWidget(currentStep: _currentStep),

          // Scrollable content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // Step 1: Select Details
                _buildStep1(),
                // Step 2: Review Summary
                BookingSummaryStepWidget(
                  serviceData: _serviceData,
                  selectedDate: _selectedDate,
                  selectedTimeSlot: _selectedTimeSlot,
                  selectedTherapistId: _selectedTherapistId,
                ),
                // Step 3: Payment
                PaymentStepWidget(
                  amountDue: Booking.calculateDownPayment(
                    (_serviceData['price'] as num).toDouble(),
                  ),
                  onReferenceChanged: (value) => _paymentReference = value,
                  onScreenshotChanged: (value) => _paymentScreenshot = value,
                ),
              ],
            ),
          ),

          // Fixed bottom CTA
          _buildBottomCta(),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return SizedBox(
      height: 220,
      child: Stack(
        children: [
          // Hero image — full bleed, anatomy locked
          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(0),
                bottomRight: Radius.circular(0),
              ),
              child: _buildHeroImage(),
            ),
          ),
          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(77),
                    Colors.black.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: GestureDetector(
              onTap: _prevStep,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(230),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(38),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: CustomIconWidget(
                    iconName: 'arrow_back',
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          // Service name + rating overlay (bottom of image)
          Positioned(
            bottom: 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _serviceData['name'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withAlpha(128),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        (_serviceData['rating'] as num).toStringAsFixed(1),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage() {
    final imageUrl = _serviceData['imageUrl'] as String;
    final semanticLabel = _serviceData['semanticLabel'] as String;
    return Image.network(
      imageUrl,
      width: double.infinity,
      height: 220,
      fit: BoxFit.cover,
      semanticLabel: semanticLabel,
      errorBuilder: (_, __, ___) => Container(
        color: AppTheme.primaryContainer,
        child: Center(
          child: CustomIconWidget(
            iconName: 'spa',
            color: AppTheme.primary,
            size: 48,
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service description + price
          BookingServiceDetailWidget(serviceData: _serviceData),
          const SizedBox(height: 24),

          // Date selector
          Text(
            'Pick Booking Date',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.onSurfaceLight,
            ),
          ),
          const SizedBox(height: 12),
          DaySelectorWidget(
            selectedDate: _selectedDate,
            onDateSelected: (date) => setState(() {
              _selectedDate = date;
              _selectedTherapistId = null;
            }),
          ),
          const SizedBox(height: 24),

          // Time slot selector
          Text(
            'Select Time',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.onSurfaceLight,
            ),
          ),
          const SizedBox(height: 12),
          TimeSlotWidget(
            selectedTimeSlot: _selectedTimeSlot,
            onTimeSelected: (time) => setState(() {
              _selectedTimeSlot = time;
              _selectedTherapistId = null;
            }),
            selectedDate: _selectedDate,
          ),
          const SizedBox(height: 24),

          // Therapist selector
          Text(
            'Choose Therapist',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.onSurfaceLight,
            ),
          ),
          const SizedBox(height: 12),
          TherapistSelectorWidget(
            selectedTherapistId: _selectedTherapistId,
            onTherapistSelected: (id) =>
                setState(() => _selectedTherapistId = id),
            selectedDate: _selectedDate,
            selectedTimeSlot: _selectedTimeSlot,
            durationMinutes:
                (_serviceData['durationMinutes'] as num?)?.toInt() ?? 60,
          ),
          // Space for bottom CTA
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBottomCta() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            OutlinedButton(
              onPressed: _prevStep,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Back',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryLight],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withAlpha(77),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: (_isLoading)
                      ? null
                      : (_currentStep == 2 ? _submitBooking : _nextStep),
                  borderRadius: BorderRadius.circular(12),
                  splashColor: Colors.white.withAlpha(51),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _ctaLabel,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              if (_currentStep < 2) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
