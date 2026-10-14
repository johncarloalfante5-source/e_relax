import '../../models/payment_transaction.dart';
import '../../models/walk_in.dart';

abstract interface class CashierRepository {
  Stream<List<WalkIn>> watchWalkIns();
  Future<WalkIn> startWalkIn({required String clientName, required String clientPhone, required String serviceId, required String therapistId});
  Future<void> checkoutWalkIn(String walkInId, {required String method});
  Future<void> collectOnlineBalance(String bookingId, {required String method});
  Stream<List<PaymentTransaction>> watchPaymentTransactions(PaymentDateRange range);
}

class PaymentDateRange {
  const PaymentDateRange({required this.start,required this.end});
  final DateTime start,end;
}
