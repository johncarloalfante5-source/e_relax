import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/booking.dart';

class BookingReceiptService {
  static Future<void> download(Booking booking) async {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Padding(
          padding: const pw.EdgeInsets.all(36),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'E-Relax Massage Clinic',
                style: pw.TextStyle(
                  fontSize: 23,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Booking and payment receipt',
                style: const pw.TextStyle(fontSize: 16),
              ),
              pw.Divider(),
              pw.SizedBox(height: 14),
              pw.Text('Booking reference: ${booking.referenceNumber}'),
              pw.Text('Client: ${booking.clientName}'),
              if (booking.clientPhone.isNotEmpty)
                pw.Text('Phone: ${booking.clientPhone}'),
              if (booking.clientEmail.isNotEmpty)
                pw.Text('Email: ${booking.clientEmail}'),
              pw.Text('Clinic: E-Relax Massage Clinic'),
              pw.Text('Service: ${booking.serviceName}'),
              pw.Text('Provider: ${booking.therapistName}'),
              pw.Text(
                'Appointment: ${_date(booking.appointmentDate)} at ${booking.startTime}',
              ),
              pw.Text('Duration: ${booking.durationMinutes} minutes'),
              pw.SizedBox(height: 16),
              pw.Text(
                'Total: PHP ${booking.totalAmount.toStringAsFixed(2)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Payment amount: PHP ${booking.paymentAmount.toStringAsFixed(2)}',
              ),
              pw.Text(
                'Required down payment (30%): PHP ${booking.requiredDownPayment.toStringAsFixed(2)}',
              ),
              pw.Text(
                'Remaining balance due after service: PHP ${booking.remainingBalance.toStringAsFixed(2)}',
              ),
              if (booking.balancePayment case final balance?) ...[
                pw.Text(
                  'Balance paid: PHP ${balance.amount.toStringAsFixed(2)} by ${balance.method}',
                ),
                pw.Text('Balance collected at: ${balance.collectedAt.toLocal()}'),
                pw.Text('Cashier: ${balance.collectedBy}'),
              ],
              pw.Text(
                'Total paid: PHP ${(booking.paymentAmount + (booking.balancePayment?.amount ?? 0)).toStringAsFixed(2)}',
              ),
              if (booking.discountAmount > 0)
                pw.Text(
                  'Discount: PHP ${booking.discountAmount.toStringAsFixed(2)}',
                ),
              pw.Text('Payment method: ${booking.paymentMethod}'),
              pw.Text('Transaction reference: ${booking.transactionReference}'),
              pw.Text('Payment status: ${booking.paymentStatus.label}'),
              pw.Text(
                'Balance status: ${booking.balancePaid ? 'Paid in full' : 'Balance due'}',
              ),
              pw.Text('Booking status: ${booking.bookingStatus.label}'),
              if (booking.paymentReviewedAt != null)
                pw.Text('Reviewed at: ${booking.paymentReviewedAt!.toLocal()}'),
              if (booking.paymentReviewedBy != null)
                pw.Text('Reviewed by: ${booking.paymentReviewedBy}'),
              if (booking.paymentRejectionReason != null) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                  'Latest submission feedback: ${booking.paymentRejectionReason}',
                ),
              ],
              pw.Spacer(),
              pw.Text('Created ${booking.createdAt.toLocal()}'),
            ],
          ),
        ),
      ),
    );
    await Printing.layoutPdf(
      onLayout: (_) async => document.save(),
      name: 'E-Relax-Receipt-${booking.referenceNumber}.pdf',
    );
  }

  static String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
