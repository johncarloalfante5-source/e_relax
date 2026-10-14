import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/payment_transaction.dart';
import '../../models/walk_in.dart';
import '../backend/supabase_client_provider.dart';
import 'cashier_repository.dart';

class SupabaseCashierRepository implements CashierRepository {
  SupabaseClient get _client=>SupabaseClientProvider.client;
  @override Stream<List<WalkIn>> watchWalkIns()=>_client.from('walk_ins').stream(primaryKey:['id']).order('started_at',ascending:false).map((rows)=>rows.map(WalkIn.fromJson).toList());
  @override Future<WalkIn> startWalkIn({required String clientName,required String clientPhone,required String serviceId,required String therapistId}) async {
    final id=await _client.rpc('start_walk_in',params:{'p_client_name':clientName.trim(),'p_client_phone':clientPhone.trim(),'p_service_id':serviceId,'p_therapist_id':therapistId}) as String;
    return WalkIn.fromJson(await _client.from('walk_ins').select().eq('id',id).single());
  }
  @override Future<void> checkoutWalkIn(String walkInId,{required String method}) async { await _client.rpc('checkout_walk_in',params:{'p_walk_in_id':walkInId,'p_method':method}); }
  @override Future<void> collectOnlineBalance(String bookingId,{required String method}) async { await _client.rpc('collect_online_balance',params:{'p_booking_id':bookingId,'p_method':method}); }
  @override Stream<List<PaymentTransaction>> watchPaymentTransactions(PaymentDateRange range)=>_client.from('payment_transactions').stream(primaryKey:['id']).gte('captured_at',range.start.toUtc().toIso8601String()).lt('captured_at',range.end.toUtc().toIso8601String()).asyncMap(_mapTransactions);
  Future<List<PaymentTransaction>> _mapTransactions(List<Map<String,dynamic>> rows) async {
    final result=<PaymentTransaction>[];
    for(final row in rows){
      final sourceType=row['source_type'] as String; final sourceId=row['source_id'] as String;
      final table=sourceType=='walk_in'?'walk_ins':'bookings';
      final source=await _client.from(table).select(sourceType=='walk_in'?'client_name,service_name':'client_name,service_name').eq('id',sourceId).maybeSingle();
      result.add(PaymentTransaction(id:row['id'] as String,sourceType:sourceType,sourceId:sourceId,amount:(row['amount'] as num).toDouble(),method:row['method'] as String,capturedAt:DateTime.parse(row['captured_at'] as String),customer:source?['client_name'] as String? ?? 'Client',service:source?['service_name'] as String? ?? 'Service'));
    }
    return result;
  }
}
