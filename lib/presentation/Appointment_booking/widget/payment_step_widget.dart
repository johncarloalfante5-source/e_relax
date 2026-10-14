import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';

class PaymentStepWidget extends StatefulWidget {
  final double totalAmount;
  final double amountDue;
  final ValueChanged<String>? onReferenceChanged;
  final ValueChanged<Uint8List?>? onScreenshotChanged;

  const PaymentStepWidget({
    super.key,
    required this.totalAmount,
    required this.amountDue,
    this.onReferenceChanged,
    this.onScreenshotChanged,
  });

  @override
  State<PaymentStepWidget> createState() => _PaymentStepWidgetState();
}

class _PaymentStepWidgetState extends State<PaymentStepWidget> {
  final _referenceController = TextEditingController();
  Uint8List? _screenshot;
  String? _fileName;

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _screenshot = bytes;
      _fileName = file.name;
    });
    widget.onScreenshotChanged?.call(_screenshot);
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = GoogleFonts.plusJakartaSans(
      fontSize: 13,
      color: AppTheme.onSurfaceLight,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment method',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.onSurfaceLight,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppTheme.primary.withAlpha(38)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _paymentAmountRow('Service total', widget.totalAmount),
                const SizedBox(height: 10),
                _paymentAmountRow(
                  'Down payment due now (30%)',
                  widget.amountDue,
                ),
                const SizedBox(height: 10),
                _paymentAmountRow(
                  'Balance due after service',
                  widget.totalAmount - widget.amountDue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppTheme.primary.withAlpha(38)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/payment_qr.jpg',
                    width: 220,
                    fit: BoxFit.contain,
                    semanticLabel: 'E-Relax InstaPay QR code and payment recipient details',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Recipient: JO*N CA**O A.',
                  textAlign: TextAlign.center,
                ),
                const Text(
                  'Mobile No.: +63 951 951 531',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Transfer ₱${widget.amountDue.toStringAsFixed(0)} (30% down payment) and keep your transaction reference number.',
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'After payment',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.onSurfaceLight,
            ),
          ),
          const SizedBox(height: 8),
          for (final instruction in [
            'Open your banking app and scan the QR code',
            'Send ₱${widget.amountDue.toStringAsFixed(0)} down payment',
            'Save your transaction screenshot',
            'Enter the transaction reference and upload proof',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(instruction, style: textStyle)),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Text(
            'Transaction reference number',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.onSurfaceLight,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: _referenceController,
            onChanged: widget.onReferenceChanged,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              prefixIcon: const Icon(
                Icons.tag_rounded,
                color: AppTheme.primary,
              ),
              hintText: 'e.g. 1234567890',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Upload payment screenshot',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.onSurfaceLight,
            ),
          ),
          const SizedBox(height: 7),
          InkWell(
            onTap: _pickScreenshot,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 88),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppTheme.primary.withAlpha(75)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _screenshot == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.upload_file_rounded,
                          color: AppTheme.primary,
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Tap to upload screenshot',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _screenshot!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _fileName ?? 'Payment proof uploaded',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.check_circle, color: AppTheme.success),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Your booking will be marked Pending Verification. An admin will review your payment proof.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.primary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentAmountRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.onSurfaceVariantLight),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '₱${amount.toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
