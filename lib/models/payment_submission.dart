class PaymentSubmission {
  const PaymentSubmission({required this.id, required this.bookingId, required this.number, required this.reference, required this.amount, required this.proofPath, required this.status, required this.submittedAt, this.rejectionReason, this.reviewedAt, this.reviewedBy});
  final String id, bookingId, reference, proofPath, status;
  final int number;
  final double amount;
  final DateTime submittedAt;
  final String? rejectionReason, reviewedBy;
  final DateTime? reviewedAt;
}
