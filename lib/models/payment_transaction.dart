class PaymentTransaction {
  const PaymentTransaction({required this.id,required this.sourceType,required this.sourceId,required this.amount,required this.method,required this.capturedAt,required this.customer,required this.service});
  final String id,sourceType,sourceId,method,customer,service;
  final double amount;
  final DateTime capturedAt;
}
