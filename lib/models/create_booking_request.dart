import 'dart:typed_data';

class CreateBookingRequest {
  const CreateBookingRequest({
    required this.serviceId,
    required this.therapistId,
    required this.appointmentDate,
    required this.startTime,
    required this.clientName,
    required this.clientPhone,
    required this.clientEmail,
    required this.transactionReference,
    required this.proof,
  });
  final String serviceId, therapistId, startTime, clientName, clientPhone, clientEmail, transactionReference;
  final DateTime appointmentDate;
  final Uint8List proof;
}
