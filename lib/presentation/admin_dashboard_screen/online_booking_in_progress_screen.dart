import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/payment_booking_store.dart';
import '../../models/booking.dart';
import '../../theme/app_theme.dart';

/// Live operations view for online appointments that have checked in or begun
/// service. The service clock includes the clinic's five-minute preparation
/// allowance.
class OnlineBookingInProgressScreen extends StatelessWidget {
  const OnlineBookingInProgressScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.backgroundLight,
    appBar: AppBar(
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      title: const Text('Online booking in progress'),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1050),
        child: AnimatedBuilder(
          animation: PaymentBookingStore.instance,
          builder: (context, _) {
            final bookings = PaymentBookingStore.instance.bookings
                .where(
                  (booking) =>
                      booking.bookingStatus == BookingStatus.checkedIn ||
                      booking.bookingStatus == BookingStatus.inProgress,
                )
                .toList()
              ..sort((a, b) {
                final aStart = a.serviceStartedAt ?? a.checkedInAt ?? a.appointmentDate;
                final bStart = b.serviceStartedAt ?? b.checkedInAt ?? b.appointmentDate;
                return aStart.compareTo(bStart);
              });

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Clients being served',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Chip(
                      avatar: const Icon(Icons.spa_outlined, size: 18),
                      label: Text('${bookings.length} active'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Manage checked-in online appointments. The timer starts when staff starts the service and includes 5 minutes for preparation.',
                ),
                const SizedBox(height: 18),
                if (bookings.isEmpty)
                  const _EmptyInProgress()
                else
                  for (final booking in bookings)
                    _OnlineBookingCard(booking: booking),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _OnlineBookingCard extends StatelessWidget {
  const _OnlineBookingCard({required this.booking});

  final Booking booking;

  Future<void> _advance(BuildContext context, BookingStatus next) async {
    final action = next == BookingStatus.inProgress
        ? 'Start service'
        : 'Complete service';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action?'),
        content: Text('$action for ${booking.clientName} (${booking.referenceNumber})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;

    final updated = await PaymentBookingStore.instance.transitionBooking(
      booking.id,
      next: next,
      adminId: 'demo-admin',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated
              ? '${booking.referenceNumber}: ${next.label}'
              : 'This booking could not be updated. Refresh and try again.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final started = booking.bookingStatus == BookingStatus.inProgress;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.clientName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text('${booking.serviceName} · ${booking.referenceNumber}'),
                    ],
                  ),
                ),
                _StatusTag(
                  label: booking.bookingStatus.label,
                  color: started ? AppTheme.primary : AppTheme.warning,
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Detail(
                  icon: Icons.calendar_today_outlined,
                  text: '${_date(booking.appointmentDate)} · ${booking.startTime}',
                ),
                _Detail(
                  icon: Icons.person_outline,
                  text: booking.therapistName,
                ),
                _Detail(
                  icon: Icons.schedule_outlined,
                  text: booking.preparationSkippedAt == null
                      ? '${booking.durationMinutes} min service + 5 min prep'
                      : '${booking.durationMinutes} min service · prep skipped',
                ),
                _Detail(
                  icon: Icons.payments_outlined,
                  text:
                      'Down payment verified · PHP ${booking.paymentAmount.toStringAsFixed(0)}',
                ),
              ],
            ),
            if (started) ...[
              const SizedBox(height: 16),
              _ServiceClock(
                startedAt: booking.serviceStartedAt,
                preparationSkippedAt: booking.preparationSkippedAt,
                durationMinutes: booking.durationMinutes,
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (started) _SkipPreparationButton(booking: booking),
                FilledButton.icon(
                  onPressed: () => _advance(
                    context,
                    started ? BookingStatus.completed : BookingStatus.inProgress,
                  ),
                  icon: Icon(
                    started ? Icons.task_alt_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(started ? 'Complete service' : 'Start service'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.month}/${value.day}/${value.year}';
}

class _ServiceClock extends StatefulWidget {
  const _ServiceClock({
    required this.startedAt,
    required this.preparationSkippedAt,
    required this.durationMinutes,
  });

  final DateTime? startedAt;
  final DateTime? preparationSkippedAt;
  final int durationMinutes;

  @override
  State<_ServiceClock> createState() => _ServiceClockState();
}

class _ServiceClockState extends State<_ServiceClock> {
  static const _preparation = Duration(minutes: 5);
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _format(Duration duration) {
    final seconds = duration.inSeconds.abs();
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.startedAt;
    if (start == null) {
      return const _ClockBanner(
        label: 'Service timer unavailable',
        color: AppTheme.warning,
      );
    }
    final now = DateTime.now();
    final elapsed = now.difference(start);
    final skippedAt = widget.preparationSkippedAt;
    final prepRemaining = _preparation - elapsed;
    if (skippedAt == null && elapsed < _preparation) {
      return _ClockBanner(
        label: 'Preparation · ${_format(prepRemaining)} remaining',
        color: AppTheme.warning,
      );
    }
    final serviceElapsed = now.difference(skippedAt ?? start.add(_preparation));
    final remaining = Duration(minutes: widget.durationMinutes) - serviceElapsed;
    if (remaining > Duration.zero) {
      return _ClockBanner(
        label: 'Service in progress · ${_format(remaining)} remaining',
        color: AppTheme.primary,
      );
    }
    return _ClockBanner(
      label: 'Service time exceeded · ${_format(-remaining)}',
      color: AppTheme.error,
    );
  }
}

class _SkipPreparationButton extends StatefulWidget {
  const _SkipPreparationButton({required this.booking});

  final Booking booking;

  @override
  State<_SkipPreparationButton> createState() => _SkipPreparationButtonState();
}

class _SkipPreparationButtonState extends State<_SkipPreparationButton> {
  static const _preparation = Duration(minutes: 5);
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_canSkip) {
        setState(() {});
      } else {
        _ticker?.cancel();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _canSkip {
    final startedAt = widget.booking.serviceStartedAt;
    if (widget.booking.preparationSkippedAt != null || startedAt == null) {
      return false;
    }
    final elapsed = DateTime.now().difference(startedAt);
    return !elapsed.isNegative && elapsed < _preparation;
  }

  Future<void> _skip() async {
    if (_busy || !_canSkip) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Skip preparation?'),
        content: Text(
          'Start ${widget.booking.serviceName} now without the remaining preparation time?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep preparing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Skip preparation'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    final skipped = await PaymentBookingStore.instance.skipPreparation(
      widget.booking.id,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skipped
              ? 'Preparation skipped; the service timer has started.'
              : 'Preparation could not be skipped. It may have ended or already been skipped.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canSkip) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: _busy ? null : _skip,
      icon: const Icon(Icons.fast_forward_rounded),
      label: Text(_busy ? 'Skipping…' : 'Skip preparation'),
    );
  }
}

class _ClockBanner extends StatelessWidget {
  const _ClockBanner({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withAlpha(20),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(Icons.timer_outlined, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: AppTheme.primary),
      const SizedBox(width: 7),
      Text(text),
    ],
  );
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withAlpha(22),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

class _EmptyInProgress extends StatelessWidget {
  const _EmptyInProgress();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 42),
      child: Column(
        children: [
          Icon(Icons.spa_outlined, size: 42, color: AppTheme.primary),
          const SizedBox(height: 12),
          Text(
            'No online bookings are checked in or in progress.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text('Checked-in clients will appear here for service timing and completion.'),
        ],
      ),
    ),
  );
}
