class WalkIn {
  WalkIn({required this.id, required this.customer, required this.phone, required this.serviceId, required this.service, required this.therapistId, required this.therapistName, required this.durationMinutes, required this.amount, required this.createdAt, required this.completedAt, this.paymentCollected = false, this.paymentMethod});
  final String id, customer, phone, serviceId, service, therapistId, therapistName;
  final int durationMinutes;
  final double amount;
  final DateTime createdAt, completedAt;
  bool paymentCollected;
  String? paymentMethod;
  Duration get elapsed => DateTime.now().difference(createdAt);
  bool get isServiceComplete => !DateTime.now().isBefore(completedAt);
  String get statusLabel => isServiceComplete
      ? (paymentCollected ? 'Completed · Paid' : 'Service complete · Awaiting payment')
      : paymentCollected
      ? 'Paid · $remainingLabel left'
      : 'In progress · $remainingLabel left';
  String get remainingLabel {
    final seconds = completedAt.difference(DateTime.now()).inSeconds.clamp(0,999999);
    return '${(seconds~/60).toString().padLeft(2,'0')}:${(seconds%60).toString().padLeft(2,'0')}';
  }
  static WalkIn fromJson(Map<String,dynamic> row) => WalkIn(
    id: row['id'] as String,
    customer: row['client_name'] as String,
    phone: row['client_phone'] as String? ?? '',
    serviceId: row['service_id'] as String,
    service: row['service_name'] as String,
    therapistId: row['therapist_id'] as String,
    therapistName: row['therapist_name'] as String,
    durationMinutes: row['duration_minutes'] as int,
    amount: (row['total_amount'] as num).toDouble(),
    createdAt: DateTime.parse(row['started_at'] as String),
    completedAt: DateTime.parse(row['completed_at'] as String),
    paymentCollected: row['checked_out_at'] != null,
    paymentMethod: row['payment_method'] as String?,
  );
}
