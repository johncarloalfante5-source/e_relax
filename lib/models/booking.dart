import 'dart:typed_data';

enum BookingStatus {
  pendingPayment,
  confirmed,
  checkedIn,
  inProgress,
  completed,
  cancelled,
}

enum PaymentStatus { pendingVerification, verified, rejected }

enum BookingActivityType {
  bookingCreated,
  proofSubmitted,
  paymentVerified,
  paymentRejected,
  clientCheckedIn,
  serviceStarted,
  serviceCompleted,
  balanceCollected,
  bookingCancelled,
  bookingConfirmed,
}

class BookingActivity {
  const BookingActivity({
    required this.type,
    required this.at,
    required this.actor,
    this.note,
  });

  final BookingActivityType type;
  final DateTime at;
  final String actor;
  final String? note;
}

class PaymentProofSubmission {
  PaymentProofSubmission({
    this.id,
    required this.transactionReference,
    required this.amount,
    required this.screenshot,
    required this.submittedAt,
    this.rejectionReason,
    this.reviewedAt,
    this.reviewedBy,
  });

  final String? id;
  final String transactionReference;
  final double amount;
  final Uint8List screenshot;
  final DateTime submittedAt;
  String? rejectionReason;
  DateTime? reviewedAt;
  String? reviewedBy;
}

class BalancePayment {
  const BalancePayment({
    required this.amount,
    required this.method,
    required this.collectedAt,
    required this.collectedBy,
  });

  final double amount;
  final String method;
  final DateTime collectedAt;
  final String collectedBy;
}

class Booking {
  static const double downPaymentRate = 0.30;

  static double calculateDownPayment(double totalAmount) =>
      (totalAmount * downPaymentRate).roundToDouble();

  Booking({
    required this.id,
    required this.referenceNumber,
    required this.clientId,
    required this.clientName,
    this.clientPhone = '',
    this.clientEmail = '',
    required this.serviceId,
    required this.serviceName,
    this.serviceDescription = '',
    required this.therapistId,
    required this.therapistName,
    required this.appointmentDate,
    required this.startTime,
    required this.durationMinutes,
    required this.totalAmount,
    this.discountAmount = 0,
    this.paymentMethod = 'InstaPay',
    required String transactionReference,
    required double paymentAmount,
    required Uint8List receiptImage,
    required DateTime paymentSubmittedAt,
    required this.createdAt,
  }) : paymentAmount = paymentAmount,
       paymentSubmittedAt = paymentSubmittedAt,
       updatedAt = createdAt {
    paymentStatus = PaymentStatus.pendingVerification;
    bookingStatus = BookingStatus.pendingPayment;
    proofSubmissions.add(
      PaymentProofSubmission(
        transactionReference: transactionReference,
        amount: paymentAmount,
        screenshot: receiptImage,
        submittedAt: paymentSubmittedAt,
      ),
    );
    activity.add(
      BookingActivity(
        type: BookingActivityType.bookingCreated,
        at: createdAt,
        actor: clientName,
      ),
    );
    activity.add(
      BookingActivity(
        type: BookingActivityType.proofSubmitted,
        at: paymentSubmittedAt,
        actor: clientName,
      ),
    );
  }

  final String id;
  final String referenceNumber;
  final String clientId;
  final String clientName;
  final String clientPhone;
  final String clientEmail;
  final String serviceId;
  final String serviceName;
  final String serviceDescription;
  final String therapistId;
  final String therapistName;
  final DateTime appointmentDate;
  final String startTime;
  final int durationMinutes;
  final double totalAmount;
  final double discountAmount;
  double get requiredDownPayment => calculateDownPayment(totalAmount);
  double get remainingBalance =>
      (totalAmount -
              (paymentStatus == PaymentStatus.verified ? paymentAmount : 0) -
              (balancePayment?.amount ?? 0))
          .clamp(0, double.infinity)
          .toDouble();
  bool get balancePaid => remainingBalance == 0;
  final String paymentMethod;
  double paymentAmount;
  DateTime paymentSubmittedAt;
  DateTime? paymentReviewedAt;
  String? paymentReviewedBy;
  String? paymentRejectionReason;
  DateTime? checkedInAt;
  DateTime? serviceStartedAt;
  DateTime? serviceCompletedAt;
  String? cancellationReason;
  BalancePayment? balancePayment;
  final DateTime createdAt;
  DateTime updatedAt;

  BookingStatus bookingStatus = BookingStatus.pendingPayment;
  PaymentStatus paymentStatus = PaymentStatus.pendingVerification;
  final List<PaymentProofSubmission> proofSubmissions = [];
  final List<BookingActivity> activity = [];

  PaymentProofSubmission get latestProof => proofSubmissions.last;
  String get transactionReference => latestProof.transactionReference;
  Uint8List get receiptImage => latestProof.screenshot;
}

extension BookingStatusLabel on BookingStatus {
  String get label => switch (this) {
    BookingStatus.pendingPayment => 'Pending Payment',
    BookingStatus.confirmed => 'Confirmed',
    BookingStatus.checkedIn => 'Checked In',
    BookingStatus.inProgress => 'In Progress',
    BookingStatus.completed => 'Completed',
    BookingStatus.cancelled => 'Cancelled',
  };
}

extension PaymentStatusLabel on PaymentStatus {
  String get label => switch (this) {
    PaymentStatus.pendingVerification => 'Pending Verification',
    PaymentStatus.verified => 'Verified',
    PaymentStatus.rejected => 'Rejected',
  };
}
