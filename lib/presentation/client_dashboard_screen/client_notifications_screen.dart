import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/payment_booking_store.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';

class ClientNotificationsScreen extends StatelessWidget {
  const ClientNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.backgroundLight,
    appBar: AppBar(
      title: const Text('Notifications'),
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        TextButton(
          onPressed: () => PaymentBookingStore.instance.markAllNoticesRead(
            localClientSessionId,
          ),
          child: const Text(
            'Mark all read',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: PaymentBookingStore.instance,
      builder: (context, _) {
        final notices = PaymentBookingStore.instance
            .noticesForClient(localClientSessionId)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (notices.isEmpty) {
          return const _EmptyNotifications();
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            for (final notice in notices)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: notice.isRead ? Colors.white : AppTheme.primaryContainer,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: notice.isRead
                        ? Colors.black12
                        : AppTheme.primary.withAlpha(55),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: CircleAvatar(
                    backgroundColor: _noticeColor(notice.type).withAlpha(25),
                    child: Icon(
                      _noticeIcon(notice.type),
                      color: _noticeColor(notice.type),
                    ),
                  ),
                  title: Text(
                    _noticeTitle(notice.type),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(notice.message),
                        const SizedBox(height: 6),
                        Text(
                          _formatDate(notice.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.onSurfaceVariantLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: notice.isRead
                      ? null
                      : Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                  onTap: () => PaymentBookingStore.instance.markNoticeRead(
                    notice.id,
                    clientId: localClientSessionId,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.clientBookings),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('View bookings and payment details'),
            ),
          ],
        );
      },
    ),
  );

  static String _noticeTitle(ClientNoticeType type) => switch (type) {
    ClientNoticeType.paymentVerified => 'Payment verified',
    ClientNoticeType.paymentRejected => 'Payment proof needs attention',
    ClientNoticeType.proofResubmitted => 'Proof submitted',
    ClientNoticeType.bookingConfirmed => 'Booking confirmed',
    ClientNoticeType.bookingCancelled => 'Booking cancelled',
    ClientNoticeType.balanceCollected => 'Balance paid',
  };

  static IconData _noticeIcon(ClientNoticeType type) => switch (type) {
    ClientNoticeType.paymentVerified => Icons.verified_outlined,
    ClientNoticeType.paymentRejected => Icons.warning_amber_rounded,
    ClientNoticeType.proofResubmitted => Icons.upload_file_rounded,
    ClientNoticeType.bookingConfirmed => Icons.event_available_outlined,
    ClientNoticeType.bookingCancelled => Icons.cancel_outlined,
    ClientNoticeType.balanceCollected => Icons.receipt_long_outlined,
  };

  static Color _noticeColor(ClientNoticeType type) =>
      type == ClientNoticeType.paymentRejected ||
          type == ClientNoticeType.bookingCancelled
      ? AppTheme.error
      : AppTheme.primary;

  static String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 52,
            color: AppTheme.primary.withAlpha(150),
          ),
          const SizedBox(height: 12),
          const Text(
            'You’re all caught up',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Payment and booking updates will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.onSurfaceVariantLight),
          ),
        ],
      ),
    ),
  );
}
