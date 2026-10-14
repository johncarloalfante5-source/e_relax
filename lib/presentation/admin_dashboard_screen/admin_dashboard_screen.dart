import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/payment_booking_store.dart';
import '../../data/repositories/client_admin_chat_repository.dart';
import '../../data/stores/auth_session_store.dart';
import '../../data/service_catalog.dart';
import '../../data/therapist_roster_store.dart';
import '../../data/repositories/cashier_repository.dart';
import '../../data/repositories/supabase_cashier_repository.dart';
import '../../models/booking.dart';
import '../../models/client_admin_chat.dart';
import '../../models/payment_transaction.dart';
import '../../models/profile.dart';
import '../../models/walk_in.dart';
import '../../presentation/admin_dashboard_screen/admin_client_chats_panel.dart';
import '../../services/booking_receipt_service.dart';
import '../../services/report_pdf_service.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  _AdminSection _selectedSection = _AdminSection.dashboard;
  final _bookingSearchController = TextEditingController();
  BookingStatus? _bookingStatusFilter;
  PaymentStatus? _paymentStatusFilter;
  DateTimeRange? _bookingDateRange;
  _BookingSort _bookingSort = _BookingSort.appointmentTime;
  _SalesPeriod _salesPeriod = _SalesPeriod.daily;
  DateTimeRange? _customSalesRange;
  _SalesPeriod _servicePeriod = _SalesPeriod.daily;
  DateTimeRange? _customServiceRange;
  _SalesPeriod _therapistProfitPeriod = _SalesPeriod.daily;
  DateTimeRange? _customTherapistProfitRange;
  final List<_Sale> _sales = [];
  final List<WalkIn> _walkIns = [];
  final _cashierRepository = SupabaseCashierRepository();
  final _clientAdminChatRepository = ClientAdminChatRepository();
  final List<ClientAdminConversation> _adminChatInbox = [];
  RealtimeChannel? _adminChatChannel;
  Timer? _adminChatRefreshTimer;
  bool _adminChatLoading = false;
  String? _adminChatError;
  StreamSubscription<List<WalkIn>>? _walkInSubscription;
  StreamSubscription<List<PaymentTransaction>>? _salesSubscription;
  Timer? _walkInTicker;

  double get _salesTotal => _sales.fold<double>(0, (sum, sale) => sum + sale.amount);

  @override
  void initState() {
    super.initState();
    _walkInTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _walkInSubscription = _cashierRepository.watchWalkIns().listen((items) {
      if (mounted) setState(() { _walkIns..clear()..addAll(items); });
    }, onError: (Object error) { if (mounted) _showBackendError(error); });
    _salesSubscription = _cashierRepository.watchPaymentTransactions(
      PaymentDateRange(start: DateTime(2000), end: DateTime(2200)),
    ).listen((items) {
      if (mounted) setState(() {
        _sales
          ..clear()
          ..addAll(items.map((item) => _Sale(item.customer, '${item.service} · ${item.sourceType}', item.amount,
              TimeOfDay.fromDateTime(item.capturedAt).format(context), item.method, createdAt: item.capturedAt, source: _saleSource(item.sourceType))));
      });
    }, onError: (Object error) { if (mounted) _showBackendError(error); });
    if (_isAdmin) {
      _adminChatChannel = _clientAdminChatRepository.watchInbox(
        onChange: _scheduleAdminChatRefresh,
      );
      unawaited(_refreshAdminChatInbox());
    }
  }

  bool get _isAdmin => AuthSessionStore.instance.profile?.role == AppRole.admin;

  int get _unreadAdminConversations =>
      _adminChatInbox.where((conversation) => conversation.unreadCount > 0).length;

  void _scheduleAdminChatRefresh() {
    _adminChatRefreshTimer?.cancel();
    _adminChatRefreshTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_refreshAdminChatInbox()),
    );
  }

  Future<void> _refreshAdminChatInbox() async {
    if (!_isAdmin) return;
    if (mounted) {
      setState(() {
        _adminChatLoading = true;
        _adminChatError = null;
      });
    }
    try {
      final conversations = await _clientAdminChatRepository.fetchAdminInbox();
      if (!mounted) return;
      setState(() {
        _adminChatInbox
          ..clear()
          ..addAll(conversations);
        _adminChatLoading = false;
        _adminChatError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _adminChatLoading = false;
        _adminChatError = 'Could not load chats. Check your connection.';
      });
    }
  }

  void _showBackendError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not sync dashboard: $error')));
  }

  String _saleSource(String sourceType) => switch (sourceType) {
    'booking_deposit' => 'Online booking · down payment',
    'booking_balance' => 'Online booking · balance',
    _ => 'Walk-in checkout',
  };

  @override
  void dispose() {
    _walkInTicker?.cancel();
    _walkInSubscription?.cancel();
    _salesSubscription?.cancel();
    _adminChatRefreshTimer?.cancel();
    final chatChannel = _adminChatChannel;
    if (chatChannel != null) {
      unawaited(_clientAdminChatRepository.removeChannel(chatChannel));
    }
    _bookingSearchController.dispose();
    super.dispose();
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout_rounded, color: AppTheme.primary),
        title: const Text('Log out?'),
        content: const Text(
          'Are you sure you want to log out of the admin dashboard?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      try {
        await AuthSessionStore.instance.signOut();
        await PaymentBookingStore.instance.clearSession();
        await TherapistRosterStore.instance.initialize();
        if (mounted) context.go(AppRoutes.initial);
      } catch (error) {
        _showBackendError(error);
      }
    }
  }

  Future<void> _refreshDashboard() async {
    try {
      await Future.wait([
        PaymentBookingStore.instance.refresh(),
        TherapistRosterStore.instance.refreshTherapists(),
        TherapistRosterStore.instance.refreshDuty(DateTime.now()),
      ]);
      final walks = await _cashierRepository.watchWalkIns().first;
      final transactions = await _cashierRepository.watchPaymentTransactions(
        PaymentDateRange(start: DateTime(2000), end: DateTime(2200)),
      ).first;
      if (!mounted) return;
      setState(() {
        _walkIns..clear()..addAll(walks);
        _sales..clear()..addAll(transactions.map((item) => _Sale(item.customer,
          '${item.service} · ${item.sourceType}', item.amount,
          TimeOfDay.fromDateTime(item.capturedAt).format(context), item.method,
          createdAt: item.capturedAt, source: _saleSource(item.sourceType))));
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dashboard refreshed from Supabase.')));
    } catch (error) {
      if (mounted) _showBackendError(error);
    }
  }

  Future<void> _pickCustomSalesRange() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final initial =
        _customSalesRange ??
        DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: initial,
    );
    if (range != null && mounted) {
      setState(() {
        _customSalesRange = range;
        _salesPeriod = _SalesPeriod.custom;
      });
    }
  }

  List<_TransactionRow> _allSalesTransactions() {
    return _sales.map(_TransactionRow.fromSale).toList();
  }

  List<_SalesBucket> _salesBuckets(List<_TransactionRow> transactions) {
    final today = DateUtils.dateOnly(DateTime.now());
    switch (_salesPeriod) {
      case _SalesPeriod.daily:
        final firstDay = today.subtract(const Duration(days: 6));
        return List.generate(7, (index) {
          final start = firstDay.add(Duration(days: index));
          return _salesBucket(
            transactions,
            start: start,
            endExclusive: start.add(const Duration(days: 1)),
            label:
                '${_weekdayLabel(start.weekday)}\n${start.month}/${start.day}',
          );
        });
      case _SalesPeriod.weekly:
        final thisWeek = today.subtract(Duration(days: today.weekday - 1));
        return List.generate(8, (index) {
          final start = thisWeek.subtract(Duration(days: (7 - index) * 7));
          return _salesBucket(
            transactions,
            start: start,
            endExclusive: start.add(const Duration(days: 7)),
            label: '${start.month}/${start.day}',
          );
        });
      case _SalesPeriod.monthly:
        return List.generate(12, (index) {
          final monthOffset = 11 - index;
          final start = DateTime(today.year, today.month - monthOffset, 1);
          final end = DateTime(start.year, start.month + 1, 1);
          return _salesBucket(
            transactions,
            start: start,
            endExclusive: end,
            label: _monthLabel(start.month),
          );
        });
      case _SalesPeriod.yearly:
        return List.generate(5, (index) {
          final year = today.year - (4 - index);
          final start = DateTime(year, 1, 1);
          return _salesBucket(
            transactions,
            start: start,
            endExclusive: DateTime(year + 1, 1, 1),
            label: '$year',
          );
        });
      case _SalesPeriod.custom:
        final range = _customSalesRange;
        if (range == null) return const [];
        final firstDay = DateUtils.dateOnly(range.start);
        final lastDay = DateUtils.dateOnly(range.end);
        final dayCount = lastDay.difference(firstDay).inDays + 1;
        if (dayCount <= 31) {
          return List.generate(dayCount, (index) {
            final start = firstDay.add(Duration(days: index));
            return _salesBucket(
              transactions,
              start: start,
              endExclusive: start.add(const Duration(days: 1)),
              label: '${start.month}/${start.day}',
            );
          });
        }
        final firstMonth = DateTime(firstDay.year, firstDay.month, 1);
        final endMonth = DateTime(lastDay.year, lastDay.month + 1, 1);
        final monthCount =
            (endMonth.year - firstMonth.year) * 12 +
            endMonth.month -
            firstMonth.month;
        return List.generate(monthCount, (index) {
          final start = DateTime(firstMonth.year, firstMonth.month + index, 1);
          final nextMonth = DateTime(start.year, start.month + 1, 1);
          final bucketStart = start.isBefore(firstDay) ? firstDay : start;
          final bucketEnd =
              nextMonth.isAfter(lastDay.add(const Duration(days: 1)))
              ? lastDay.add(const Duration(days: 1))
              : nextMonth;
          return _salesBucket(
            transactions,
            start: bucketStart,
            endExclusive: bucketEnd,
            label: '${_monthLabel(start.month)} ${start.year}',
          );
        });
    }
  }

  _SalesBucket _salesBucket(
    List<_TransactionRow> transactions, {
    required DateTime start,
    required DateTime endExclusive,
    required String label,
  }) {
    final bucketTransactions = transactions
        .where(
          (transaction) =>
              !transaction.createdAt.isBefore(start) &&
              transaction.createdAt.isBefore(endExclusive),
        )
        .toList();
    final amount = bucketTransactions.fold<double>(
      0,
      (sum, transaction) => sum + transaction.amount,
    );
    return _SalesBucket(
      label: label,
      amount: amount,
      transactionCount: bucketTransactions.length,
    );
  }

  Future<void> _pickCustomServiceRange() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final initial =
        _customServiceRange ??
        DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: initial,
    );
    if (range != null && mounted) {
      setState(() {
        _customServiceRange = range;
        _servicePeriod = _SalesPeriod.custom;
      });
    }
  }

  Future<void> _pickCustomTherapistProfitRange() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final initial = _customTherapistProfitRange ??
        DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: initial,
    );
    if (range != null && mounted) {
      setState(() {
        _customTherapistProfitRange = range;
        _therapistProfitPeriod = _SalesPeriod.custom;
      });
    }
  }

  DateTimeRange? _therapistProfitDateRange() {
    final today = DateUtils.dateOnly(DateTime.now());
    switch (_therapistProfitPeriod) {
      case _SalesPeriod.daily:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today.add(const Duration(days: 1)),
        );
      case _SalesPeriod.weekly:
        final thisWeek = today.subtract(Duration(days: today.weekday - 1));
        return DateTimeRange(
          start: thisWeek.subtract(const Duration(days: 7 * 7)),
          end: today.add(const Duration(days: 1)),
        );
      case _SalesPeriod.monthly:
        return DateTimeRange(
          start: DateTime(today.year, today.month - 11, 1),
          end: today.add(const Duration(days: 1)),
        );
      case _SalesPeriod.yearly:
        return DateTimeRange(
          start: DateTime(today.year - 4, 1, 1),
          end: today.add(const Duration(days: 1)),
        );
      case _SalesPeriod.custom:
        final selected = _customTherapistProfitRange;
        if (selected == null) return null;
        return DateTimeRange(
          start: DateUtils.dateOnly(selected.start),
          end: DateUtils.dateOnly(selected.end).add(const Duration(days: 1)),
        );
    }
  }

  String _therapistProfitPeriodLabel() {
    if (_therapistProfitPeriod != _SalesPeriod.custom) {
      return switch (_therapistProfitPeriod) {
        _SalesPeriod.daily => 'Daily - last 7 days',
        _SalesPeriod.weekly => 'Weekly - last 8 weeks',
        _SalesPeriod.monthly => 'Monthly - last 12 months',
        _SalesPeriod.yearly => 'Yearly - last 5 years',
        _SalesPeriod.custom => 'Custom range',
      };
    }
    final range = _customTherapistProfitRange;
    return range == null
        ? 'Choose a custom date range'
        : '${_shortDate(range.start)} - ${_shortDate(range.end)}';
  }

  List<_TherapistProfitGroup> _therapistProfitGroups(DateTimeRange range) {
    final groups = <String, _TherapistProfitGroup>{};
    bool inRange(DateTime date) =>
        !date.isBefore(range.start) && date.isBefore(range.end);

    void addRow(_TherapistProfitRow row) {
      groups
          .putIfAbsent(
            row.therapistId,
            () => _TherapistProfitGroup(
              id: row.therapistId,
              name: row.therapistName,
            ),
          )
          .rows
          .add(row);
    }

    for (final booking in PaymentBookingStore.instance.bookings.where(
      (item) =>
          _isReportableOnlineBooking(item) &&
          inRange(item.serviceCompletedAt!),
    )) {
      addRow(_TherapistProfitRow(
        therapistId: booking.therapistId,
        therapistName: booking.therapistName,
        clientName: booking.clientName,
        serviceName: booking.serviceName,
        completedAt: booking.serviceCompletedAt!,
        amount: booking.totalAmount,
        source: 'Online booking',
      ));
    }
    for (final walkIn in _walkIns.where(
      (item) => item.isServiceComplete && inRange(item.completedAt),
    )) {
      addRow(_TherapistProfitRow(
        therapistId: walkIn.therapistId,
        therapistName: walkIn.therapistName,
        clientName: walkIn.customer,
        serviceName: walkIn.service,
        completedAt: walkIn.completedAt,
        amount: walkIn.amount,
        source: 'Walk-in',
      ));
    }

    final result = groups.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final group in result) {
      group.rows.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    }
    return result;
  }

  List<_ReportRange> _serviceRanges() {
    final today = DateUtils.dateOnly(DateTime.now());
    _ReportRange range(DateTime start, DateTime end, String label) =>
        _ReportRange(start: start, endExclusive: end, label: label);

    switch (_servicePeriod) {
      case _SalesPeriod.daily:
        final firstDay = today.subtract(const Duration(days: 6));
        return List.generate(7, (index) {
          final start = firstDay.add(Duration(days: index));
          return range(
            start,
            start.add(const Duration(days: 1)),
            '${_weekdayLabel(start.weekday)}\n${start.month}/${start.day}',
          );
        });
      case _SalesPeriod.weekly:
        final thisWeek = today.subtract(Duration(days: today.weekday - 1));
        return List.generate(8, (index) {
          final start = thisWeek.subtract(Duration(days: (7 - index) * 7));
          return range(
            start,
            start.add(const Duration(days: 7)),
            '${start.month}/${start.day}',
          );
        });
      case _SalesPeriod.monthly:
        return List.generate(12, (index) {
          final start = DateTime(today.year, today.month - (11 - index), 1);
          return range(
            start,
            DateTime(start.year, start.month + 1, 1),
            _monthLabel(start.month),
          );
        });
      case _SalesPeriod.yearly:
        return List.generate(5, (index) {
          final year = today.year - (4 - index);
          return range(DateTime(year, 1, 1), DateTime(year + 1, 1, 1), '$year');
        });
      case _SalesPeriod.custom:
        final selected = _customServiceRange;
        if (selected == null) return const [];
        final firstDay = DateUtils.dateOnly(selected.start);
        final lastDay = DateUtils.dateOnly(selected.end);
        final dayCount = lastDay.difference(firstDay).inDays + 1;
        if (dayCount <= 31) {
          return List.generate(dayCount, (index) {
            final start = firstDay.add(Duration(days: index));
            return range(
              start,
              start.add(const Duration(days: 1)),
              '${start.month}/${start.day}',
            );
          });
        }
        final firstMonth = DateTime(firstDay.year, firstDay.month, 1);
        final endMonth = DateTime(lastDay.year, lastDay.month + 1, 1);
        final monthCount =
            (endMonth.year - firstMonth.year) * 12 +
            endMonth.month -
            firstMonth.month;
        return List.generate(monthCount, (index) {
          final monthStart = DateTime(
            firstMonth.year,
            firstMonth.month + index,
            1,
          );
          final nextMonth = DateTime(monthStart.year, monthStart.month + 1, 1);
          final start = monthStart.isBefore(firstDay) ? firstDay : monthStart;
          final dayAfterEnd = lastDay.add(const Duration(days: 1));
          final end = nextMonth.isAfter(dayAfterEnd) ? dayAfterEnd : nextMonth;
          return range(
            start,
            end,
            '${_monthLabel(monthStart.month)} ${monthStart.year}',
          );
        });
    }
  }

  List<_ServiceBucket> _serviceBuckets(List<_ReportRange> ranges) {
    final bookings = PaymentBookingStore.instance.bookings.where(
      _isReportableOnlineBooking,
    );
    return ranges.map((range) {
      final serviceCounts = <String, int>{
        for (final service in ServiceCatalog.services)
          service['id'] as String: 0,
      };
      var walkInCount = 0;
      var onlineCount = 0;
      for (final walkIn in _walkIns.where(
        (item) =>
            item.isServiceComplete &&
            !item.completedAt.isBefore(range.start) &&
            item.completedAt.isBefore(range.endExclusive),
      )) {
        serviceCounts.update(
          walkIn.serviceId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        walkInCount++;
      }
      for (final booking in bookings.where(
        (item) =>
            !item.serviceCompletedAt!.isBefore(range.start) &&
            item.serviceCompletedAt!.isBefore(range.endExclusive),
      )) {
        serviceCounts.update(
          booking.serviceId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        onlineCount++;
      }
      return _ServiceBucket(
        label: range.label,
        walkIns: walkInCount,
        onlineBookings: onlineCount,
        serviceCounts: serviceCounts,
      );
    }).toList();
  }

  List<_ServiceCount> _serviceBreakdown(List<_ReportRange> ranges) {
    final counts = <String, _ServiceCount>{
      for (final service in ServiceCatalog.services)
        service['id'] as String: _ServiceCount(
          id: service['id'] as String,
          name: '${service['name']} (${service['durationMinutes']} min)',
        ),
    };
    bool inRange(DateTime date) => ranges.any(
      (range) =>
          !date.isBefore(range.start) && date.isBefore(range.endExclusive),
    );
    for (final walkIn in _walkIns.where((item) => item.isServiceComplete && inRange(item.completedAt))) {
      final count = counts.putIfAbsent(
        walkIn.serviceId,
        () => _ServiceCount(
          id: walkIn.serviceId,
          name: '${walkIn.service} (${walkIn.durationMinutes} min)',
        ),
      );
      count.walkIns++;
    }
    for (final booking in PaymentBookingStore.instance.bookings.where(
      (item) =>
          _isReportableOnlineBooking(item) && inRange(item.serviceCompletedAt!),
    )) {
      final service = ServiceCatalog.services.firstWhere(
        (item) => item['id'] == booking.serviceId,
        orElse: () => {
          'id': booking.serviceId,
          'name': booking.serviceName,
          'durationMinutes': booking.durationMinutes,
        },
      );
      final count = counts.putIfAbsent(
        booking.serviceId,
        () => _ServiceCount(
          id: booking.serviceId,
          name: '${service['name']} (${service['durationMinutes']} min)',
        ),
      );
      count.onlineBookings++;
    }
    return counts.values.where((item) => item.total > 0).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  bool _isReportableOnlineBooking(Booking booking) =>
      booking.paymentStatus == PaymentStatus.verified &&
      booking.bookingStatus == BookingStatus.completed &&
      booking.serviceCompletedAt != null;

  String _servicePeriodLabel() => switch (_servicePeriod) {
    _SalesPeriod.daily => 'Daily · last 7 days',
    _SalesPeriod.weekly => 'Weekly · last 8 weeks',
    _SalesPeriod.monthly => 'Monthly · last 12 months',
    _SalesPeriod.yearly => 'Yearly · last 5 years',
    _SalesPeriod.custom =>
      _customServiceRange == null
          ? 'Choose a custom date range'
          : '${_shortDate(_customServiceRange!.start)} – ${_shortDate(_customServiceRange!.end)}',
  };

  Future<void> _downloadSalesReport({
    required String periodLabel,
    required List<_SalesBucket> buckets,
    required double periodTotal,
    required int transactionCount,
  }) async {
    try {
      await ReportPdfService.download(
        title: 'Sales Report',
        periodLabel: periodLabel,
        seriesNames: const ['Sales (PHP)'],
        points: [
          for (final bucket in buckets)
            ReportChartPoint(
              label: bucket.label.replaceAll('\n', ' '),
              values: [bucket.amount],
            ),
        ],
        summary: [
          'Gross sales: PHP ${periodTotal.toStringAsFixed(2)}',
          'Transactions: $transactionCount',
        ],
        filename: 'E-Relax-Sales-Report.pdf',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create sales PDF: $error')),
        );
      }
    }
  }

  Future<void> _downloadCurrentSalesReport() async {
    final buckets = _salesBuckets(_allSalesTransactions());
    final periodLabel = switch (_salesPeriod) {
      _SalesPeriod.daily => 'Daily · last 7 days',
      _SalesPeriod.weekly => 'Weekly · last 8 weeks',
      _SalesPeriod.monthly => 'Monthly · last 12 months',
      _SalesPeriod.yearly => 'Yearly · last 5 years',
      _SalesPeriod.custom =>
        _customSalesRange == null
            ? 'Custom range'
            : '${_shortDate(_customSalesRange!.start)} – ${_shortDate(_customSalesRange!.end)}',
    };
    await _downloadSalesReport(
      periodLabel: periodLabel,
      buckets: buckets,
      periodTotal: buckets.fold<double>(
        0,
        (sum, bucket) => sum + bucket.amount,
      ),
      transactionCount: buckets.fold<int>(
        0,
        (sum, bucket) => sum + bucket.transactionCount,
      ),
    );
  }

  Future<void> _downloadServiceReport({
    required String periodLabel,
    required List<_ServiceBucket> buckets,
    required List<_ServiceCount> breakdown,
  }) async {
    final walkIns = breakdown.fold<int>(0, (sum, item) => sum + item.walkIns);
    final online = breakdown.fold<int>(
      0,
      (sum, item) => sum + item.onlineBookings,
    );
    final services = ServiceCatalog.services;
    try {
      await ReportPdfService.download(
        title: 'Service Report',
        periodLabel: periodLabel,
        seriesNames: [
          for (final service in services)
            '${service['name']} (${service['durationMinutes']} min)',
        ],
        seriesColorValues: [
          for (var index = 0; index < services.length; index++)
            _serviceColorValues[index % _serviceColorValues.length],
        ],
        points: [
          for (final bucket in buckets)
            ReportChartPoint(
              label: bucket.label.replaceAll('\n', ' '),
              values: [
                for (final service in services)
                  (bucket.serviceCounts[service['id'] as String] ?? 0)
                      .toDouble(),
              ],
            ),
        ],
        summary: [
          'Total services: ${walkIns + online}',
          'Walk-ins: $walkIns',
          'Online bookings: $online',
        ],
        detailTitle: 'Service breakdown',
        detailHeaders: const [
          'Massage service',
          'Walk-ins',
          'Online bookings',
          'Total',
        ],
        detailRows: [
          for (final item in breakdown)
            [
              item.name,
              '${item.walkIns}',
              '${item.onlineBookings}',
              '${item.total}',
            ],
        ],
        filename: 'E-Relax-Service-Report.pdf',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create service PDF: $error')),
        );
      }
    }
  }

  String _weekdayLabel(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

  String _monthLabel(int month) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];

  void _showWalkInDialog() {
    final name = TextEditingController();
    final phone = TextEditingController();
    final services = ServiceCatalog.services;
    var service = services.first;
    String? selectedTherapistId;

    List<TherapistProfile> availableTherapists(DateTime at) {
      final visitDate = DateUtils.dateOnly(at);
      final startTime = _formatWalkInStartTime(at);
      return TherapistRosterStore.instance
          .availableForBooking(
            date: visitDate,
            startTime: startTime,
            durationMinutes: (service['durationMinutes'] as num).toInt(),
          )
          .where(
            (therapist) => !_walkIns.any(
              (walkIn) =>
                  walkIn.therapistId == therapist.id &&
                  !walkIn.isServiceComplete,
            ),
          )
          .toList(growable: false);
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final candidates = availableTherapists(DateTime.now());
          final selectedIsAvailable = candidates.any(
            (therapist) => therapist.id == selectedTherapistId,
          );
          return AlertDialog(
            title: const Text('New walk-in'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Customer name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: service['id'] as String,
                      decoration: const InputDecoration(labelText: 'Service'),
                      items: services
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['id'] as String,
                              child: Text(
                                '${item['name']} · ${item['durationMinutes']} min · ₱${item['price']}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          service = services.firstWhere(
                            (item) => item['id'] == value,
                          );
                          selectedTherapistId = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedIsAvailable ? selectedTherapistId : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Therapist on duty now',
                        helperText: candidates.isEmpty
                            ? 'No therapist is assigned and available right now. Ask the admin to update today’s duty roster.'
                            : 'Therapists assigned today and available now are listed.',
                      ),
                      items: candidates
                          .map(
                            (therapist) => DropdownMenuItem<String>(
                              value: therapist.id,
                              child: Text(
                                '${therapist.name} · ${therapist.specialty}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: candidates.isEmpty
                          ? null
                          : (value) => setDialogState(
                              () => selectedTherapistId = value,
                            ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (name.text.trim().isEmpty) return;
                  final currentTherapists = availableTherapists(DateTime.now());
                  final selectedTherapists = currentTherapists
                      .where((item) => item.id == selectedTherapistId)
                      .toList(growable: false);
                  if (selectedTherapists.isEmpty) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'That therapist is no longer available. Choose another.',
                        ),
                      ),
                    );
                    setDialogState(() => selectedTherapistId = null);
                    return;
                  }
                  final therapist = selectedTherapists.first;
                  try {
                    await _cashierRepository.startWalkIn(
                      clientName: name.text,
                      clientPhone: phone.text,
                      serviceId: service['id'] as String,
                      therapistId: therapist.id,
                    );
                  } catch (error) {
                    if (mounted) _showBackendError(error);
                    return;
                  }
                  _walkInTicker ??= Timer.periodic(const Duration(seconds: 1), (
                    _,
                  ) {
                    if (mounted) setState(() {});
                  });
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${name.text.trim()} walk-in started with ${therapist.name}. Payment is due at checkout.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.point_of_sale),
                label: const Text('Start service'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatWalkInStartTime(DateTime value) {
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour < 12 ? 'AM' : 'PM';
    return '$hour12:${value.minute.toString().padLeft(2, '0')} $period';
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      drawer: wide
          ? null
          : Drawer(child: SafeArea(child: _adminSidebar(inDrawer: true))),
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'eRelax Operations',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'Admin & cashier dashboard',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {},
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Text(
                'A',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _confirmLogout,
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1450),
          child: Row(
            children: [
              if (wide) ...[
                SizedBox(width: 250, child: _adminSidebar(inDrawer: false)),
                const VerticalDivider(width: 1, thickness: 1),
              ],
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(wide ? 24 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedSection.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const Text(
                                  'Good morning, Admin',
                                  style: TextStyle(
                                    color: AppTheme.onSurfaceVariantLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _refreshDashboard,
                            tooltip: 'Refresh dashboard',
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                          FilledButton.icon(
                            onPressed: _showWalkInDialog,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('New walk-in'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _selectedSectionContent(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _adminSidebar({required bool inDrawer}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 12, 14),
        child: Row(
          children: [
            const Icon(Icons.spa_outlined, color: AppTheme.primary),
            const SizedBox(width: 10),
            Text(
              'ADMIN MENU',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppTheme.onSurfaceVariantLight,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: [
            for (final section in _AdminSection.values.where(
              (section) => _isAdmin || section != _AdminSection.clientChats,
            ))
              ListTile(
                leading: Icon(section.icon),
                title: Text(section.label),
                selected: section == _selectedSection,
                selectedColor: AppTheme.primary,
                selectedTileColor: AppTheme.primary.withAlpha(18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onTap: () => _selectAdminSection(section, inDrawer: inDrawer),
              ),
          ],
        ),
      ),
    ],
  );

  void _selectAdminSection(_AdminSection section, {required bool inDrawer}) {
    if (inDrawer) Navigator.of(context).pop();
    if (section == _AdminSection.therapists) {
      context.push(AppRoutes.therapistManagement);
      return;
    }
    if (section == _AdminSection.onlineInProgress) {
      context.push(AppRoutes.adminOnlineInProgress);
      return;
    }
    setState(() => _selectedSection = section);
  }

  Widget _selectedSectionContent() => switch (_selectedSection) {
    _AdminSection.dashboard => _dashboardOverview(),
    _AdminSection.bookings => _bookingDashboard(),
    _AdminSection.therapists => const SizedBox.shrink(),
    _AdminSection.onlineInProgress => const SizedBox.shrink(),
    _AdminSection.paymentVerification => _paymentReviewPanel(),
    _AdminSection.walkIns => _walkInPanel(),
    _AdminSection.checkout => _cashierPanel(),
    _AdminSection.salesReport => _salesPanel(),
    _AdminSection.serviceReport => _serviceReportPanel(),
    _AdminSection.therapistProfit => _therapistProfitPanel(),
    _AdminSection.clientChats => _adminClientChatsPanel(),
  };

  Widget _adminClientChatsPanel() => _Panel(
    title: 'Customer chats',
    child: AdminClientChatsPanel(
      conversations: _adminChatInbox,
      loading: _adminChatLoading,
      error: _adminChatError,
      onRetry: _refreshAdminChatInbox,
      onOpenConversation: (conversation) async {
        await context.push(
          '${AppRoutes.clientAdminChatThreadBase}/${conversation.id}',
          extra: conversation.clientName,
        );
        await _refreshAdminChatInbox();
      },
    ),
  );

  Widget _dashboardOverview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 720 ? 4 : 2;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              SizedBox(
                width: width,
                child: AnimatedBuilder(
                  animation: PaymentBookingStore.instance,
                  builder: (context, _) => _MetricCard(
                    label: 'Gross sales',
                    value: '₱' + _salesTotal.toStringAsFixed(0),
                    detail: 'Verified payments and cashier sales',
                    icon: Icons.payments_outlined,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              SizedBox(
                width: width,
                child: AnimatedBuilder(
                  animation: PaymentBookingStore.instance,
                  builder: (context, _) {
                    final bookings = PaymentBookingStore.instance.bookings;
                    final confirmed = bookings
                        .where(
                          (booking) =>
                              booking.bookingStatus == BookingStatus.confirmed,
                        )
                        .length;
                    return _MetricCard(
                      label: 'Bookings',
                      value: bookings.length.toString(),
                      detail: confirmed.toString() + ' confirmed',
                      icon: Icons.calendar_month_outlined,
                      color: AppTheme.info,
                    );
                  },
                ),
              ),
              SizedBox(
                width: width,
                child: _MetricCard(
                  label: 'Walk-ins',
                  value: _walkIns.length.toString(),
                  detail:
                      _walkIns
                          .where((walkIn) => !walkIn.isServiceComplete)
                          .length
                          .toString() +
                      ' in progress',
                  icon: Icons.directions_walk,
                  color: AppTheme.secondary,
                ),
              ),
              if (_isAdmin)
                SizedBox(
                  width: width,
                  child: _MetricCard(
                    label: 'Open chats',
                    value: _unreadAdminConversations.toString(),
                    detail: 'Conversations with unread client messages',
                    icon: Icons.chat_bubble_outline,
                    color: const Color(0xFF7B4DBA),
                    onTap: () => _selectAdminSection(
                      _AdminSection.clientChats,
                      inDrawer: false,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 20),
      if (_isAdmin) _chatPanel(),
    ],
  );
  Widget _salesPanel() => _Panel(
    title: 'Sales report',
    trailing: IconButton(
      tooltip: 'Download sales report PDF',
      onPressed: _downloadCurrentSalesReport,
      icon: const Icon(Icons.picture_as_pdf_outlined),
    ),
    child: AnimatedBuilder(
      animation: PaymentBookingStore.instance,
      builder: (context, _) {
        final transactions = _allSalesTransactions()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final buckets = _salesBuckets(transactions);
        final periodTotal = buckets.fold<double>(
          0,
          (sum, bucket) => sum + bucket.amount,
        );
        final periodTransactions = buckets.fold<int>(
          0,
          (sum, bucket) => sum + bucket.transactionCount,
        );
        final periodLabel = switch (_salesPeriod) {
          _SalesPeriod.daily => 'Daily · last 7 days',
          _SalesPeriod.weekly => 'Weekly · last 8 weeks',
          _SalesPeriod.monthly => 'Monthly · last 12 months',
          _SalesPeriod.yearly => 'Yearly · last 5 years',
          _SalesPeriod.custom =>
            _customSalesRange == null
                ? 'Choose a custom date range'
                : '${_shortDate(_customSalesRange!.start)} – ${_shortDate(_customSalesRange!.end)}',
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final period in _SalesPeriod.values)
                  ChoiceChip(
                    label: Text(period.label),
                    selected: _salesPeriod == period,
                    onSelected: (_) {
                      if (period == _SalesPeriod.custom) {
                        _pickCustomSalesRange();
                      } else {
                        setState(() => _salesPeriod = period);
                      }
                    },
                  ),
              ],
            ),
            if (_salesPeriod == _SalesPeriod.custom)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickCustomSalesRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(periodLabel),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₱${periodTotal.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        '$periodLabel · $periodTransactions transactions',
                        style: const TextStyle(
                          color: AppTheme.onSurfaceVariantLight,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (transactions.isNotEmpty)
                  Text(
                    '${transactions.length} total',
                    style: const TextStyle(
                      color: AppTheme.onSurfaceVariantLight,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (buckets.isEmpty || periodTransactions == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 38),
                child: Center(
                  child: Text('No sales recorded for this period.'),
                ),
              )
            else
              _SalesBarChart(buckets: buckets),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent transactions',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${transactions.length} total',
                  style: const TextStyle(
                    color: AppTheme.onSurfaceVariantLight,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('No transactions recorded yet.')),
              ),
            for (final transaction in transactions.take(5))
              _transactionTile(transaction),
          ],
        );
      },
    ),
  );

  Widget _serviceReportPanel() => AnimatedBuilder(
    animation: PaymentBookingStore.instance,
    builder: (context, _) {
      final ranges = _serviceRanges();
      final buckets = _serviceBuckets(ranges);
      final breakdown = _serviceBreakdown(ranges);
      final totalWalkIns = breakdown.fold<int>(
        0,
        (sum, item) => sum + item.walkIns,
      );
      final totalOnline = breakdown.fold<int>(
        0,
        (sum, item) => sum + item.onlineBookings,
      );
      final periodLabel = _servicePeriodLabel();
      return _Panel(
        title: 'Service report',
        trailing: IconButton(
          tooltip: 'Download service report PDF',
          onPressed: () => _downloadServiceReport(
            periodLabel: periodLabel,
            buckets: buckets,
            breakdown: breakdown,
          ),
          icon: const Icon(Icons.picture_as_pdf_outlined),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final period in _SalesPeriod.values)
                  ChoiceChip(
                    label: Text(period.label),
                    selected: _servicePeriod == period,
                    onSelected: (_) {
                      if (period == _SalesPeriod.custom) {
                        _pickCustomServiceRange();
                      } else {
                        setState(() => _servicePeriod = period);
                      }
                    },
                  ),
              ],
            ),
            if (_servicePeriod == _SalesPeriod.custom)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickCustomServiceRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(periodLabel),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Online bookings are counted after payment is verified and the service is marked completed.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.onSurfaceVariantLight,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text('Total services: ${totalWalkIns + totalOnline}'),
                ),
                Chip(label: Text('Walk-ins: $totalWalkIns')),
                Chip(label: Text('Online bookings: $totalOnline')),
              ],
            ),
            const SizedBox(height: 12),
            if (ranges.isEmpty || totalWalkIns + totalOnline == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 38),
                child: Center(
                  child: Text('No services recorded for this period.'),
                ),
              )
            else
              _ServiceBarChart(
                buckets: buckets,
                services: ServiceCatalog.services,
              ),
            if (breakdown.isNotEmpty) ...[
              const Divider(height: 28),
              Text(
                'Services by type',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final item in breakdown)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  subtitle: Text(
                    'Walk-ins ${item.walkIns} · Online ${item.onlineBookings}',
                  ),
                  trailing: Text(
                    '${item.total}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );

  Widget _therapistProfitPanel() => AnimatedBuilder(
    animation: PaymentBookingStore.instance,
    builder: (context, _) {
      final range = _therapistProfitDateRange();
      final groups = range == null ? <_TherapistProfitGroup>[] : _therapistProfitGroups(range);
      final rows = groups.expand((group) => group.rows).toList();
      final total = rows.fold<double>(0, (sum, row) => sum + row.amount);
      final periodLabel = _therapistProfitPeriodLabel();
      return _Panel(
        title: 'Therapist profit',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final period in _SalesPeriod.values)
                  ChoiceChip(
                    label: Text(period.label),
                    selected: _therapistProfitPeriod == period,
                    onSelected: (_) {
                      if (period == _SalesPeriod.custom) {
                        _pickCustomTherapistProfitRange();
                      } else {
                        setState(() => _therapistProfitPeriod = period);
                      }
                    },
                  ),
              ],
            ),
            if (_therapistProfitPeriod == _SalesPeriod.custom)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickCustomTherapistProfitRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(periodLabel),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Shows full service prices for completed online bookings and walk-ins. This is service revenue, before clinic costs or commissions.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.onSurfaceVariantLight,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(label: Text('Therapists: ${groups.length}')),
                Chip(label: Text('Completed services: ${rows.length}')),
                Chip(label: Text('Service value: PHP ${total.toStringAsFixed(2)}')),
              ],
            ),
            const SizedBox(height: 10),
            if (range == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Text('Choose a date range to view therapist service totals.')),
              )
            else if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 38),
                child: Center(child: Text('No completed services recorded for this period.')),
              )
            else
              for (final group in groups)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 0,
                  color: AppTheme.surfaceVariantLight,
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    title: Text(
                      group.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${group.rows.length} completed service${group.rows.length == 1 ? '' : 's'}'),
                    trailing: Text(
                      'PHP ${group.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    children: [
                      for (final row in group.rows)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const CircleAvatar(
                            radius: 17,
                            backgroundColor: Colors.white,
                            child: Icon(Icons.person_outline, size: 18, color: AppTheme.primary),
                          ),
                          title: Text(row.clientName),
                          subtitle: Text(
                            '${row.serviceName} · ${row.source} · ${_shortDate(row.completedAt)} ${TimeOfDay.fromDateTime(row.completedAt).format(context)}',
                          ),
                          trailing: Text(
                            'PHP ${row.amount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      );
    },
  );

  Widget _transactionTile(_TransactionRow transaction) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: AppTheme.primaryContainer,
          child: const Icon(
            Icons.spa_outlined,
            size: 17,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transaction.customer,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${transaction.source} · ${transaction.service} · ${transaction.time}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.onSurfaceVariantLight,
                ),
              ),
            ],
          ),
        ),
        Text(
          '₱${transaction.amount.toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        _PaymentPill(transaction.method),
      ],
    ),
  );

  Widget _chatPanel() => _Panel(
    title: 'Customer chats',
    trailing: TextButton(
      onPressed: () => _selectAdminSection(
        _AdminSection.clientChats,
        inDrawer: false,
      ),
      child: const Text('Open inbox'),
    ),
    child: Text(
      _adminChatInbox.isEmpty
          ? 'No client conversations yet.'
          : '$_unreadAdminConversations conversations have unread client messages.',
    ),
  );

  Future<void> _showCollectBalanceDialog() async {
    final searchController = TextEditingController();
    final booking = await showDialog<Booking>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final availableHeight =
              MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom;
          final contentHeight = (availableHeight - 240)
              .clamp(160.0, 420.0)
              .toDouble();
          return AlertDialog(
            title: const Text('Find booking with balance due'),
            content: SizedBox(
              width: 500,
              height: contentHeight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                TextField(
                  controller: searchController,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText:
                        'Reference, client, service, or appointment date',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: contentHeight - 68,
                  child: AnimatedBuilder(
                    animation: PaymentBookingStore.instance,
                    builder: (context, _) {
                      final query = searchController.text.trim().toLowerCase();
                      final bookings = PaymentBookingStore.instance.bookings
                          .where(
                            (booking) =>
                                booking.paymentStatus ==
                                    PaymentStatus.verified &&
                                (booking.bookingStatus ==
                                        BookingStatus.checkedIn ||
                                    booking.bookingStatus ==
                                        BookingStatus.inProgress ||
                                    booking.bookingStatus ==
                                        BookingStatus.completed) &&
                                booking.balancePayment == null &&
                                booking.remainingBalance > 0,
                          )
                          .where(
                            (booking) =>
                                query.isEmpty ||
                                booking.referenceNumber.toLowerCase().contains(
                                  query,
                                ) ||
                                booking.clientName.toLowerCase().contains(
                                  query,
                                ) ||
                                booking.serviceName.toLowerCase().contains(
                                  query,
                                ) ||
                                booking.appointmentDate
                                    .toLocal()
                                    .toString()
                                    .split(' ')
                                    .first
                                    .contains(query),
                          )
                          .toList();
                      if (bookings.isEmpty) {
                        return const Center(
                          child: Text(
                            'No checked-in bookings with an unpaid balance were found.',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: bookings.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = bookings[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              item.clientName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${item.serviceName} · ${item.referenceNumber}\nBalance due: PHP ${item.remainingBalance.toStringAsFixed(2)}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pop(dialogContext, item),
                          );
                        },
                      );
                    },
                  ),
                ),
                ],
            ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    searchController.dispose();
    if (booking == null || !mounted) return;

    String method = 'Cash';
    final shouldCollect = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Collect remaining balance'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${booking.clientName} · ${booking.referenceNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _detailSection('Payment summary', [
                  'Service total: PHP ${booking.totalAmount.toStringAsFixed(2)}',
                  'Verified down payment: PHP ${booking.paymentAmount.toStringAsFixed(2)}',
                  'Balance due: PHP ${booking.remainingBalance.toStringAsFixed(2)}',
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['Cash', 'Card', 'GCash']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => method = value ?? method),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Confirm collection'),
            ),
          ],
        ),
      ),
    );
    if (shouldCollect != true || !mounted) return;

    final collected = await PaymentBookingStore.instance.collectBalance(
      booking.id,
      amount: booking.remainingBalance,
      method: method,
      cashierId: AuthSessionStore.instance.profile?.id ?? 'staff',
    );
    if (!collected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Balance collection failed. Refresh and try again.'),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Balance collected. ${booking.referenceNumber} is paid in full.',
        ),
        action: SnackBarAction(
          label: 'Receipt',
          onPressed: () {
            BookingReceiptService.download(booking);
          },
        ),
      ),
    );
  }

  Widget _cashierPanel() => _Panel(
    title: 'Cashier · walk-in desk',
    trailing: const _OpenPill(),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Start walk-in services, check out visits, or collect online booking balances after check-in.',
              style: TextStyle(color: AppTheme.onSurfaceVariantLight),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _DeskAction(
                  icon: Icons.person_add_alt_1,
                  label: 'New walk-in',
                  onTap: _showWalkInDialog,
                ),
                _DeskAction(
                  icon: Icons.receipt_long_outlined,
                  label: 'View transactions',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Showing today\'s transactions above.'),
                    ),
                  ),
                ),
                _DeskAction(
                  icon: Icons.point_of_sale,
                  label: 'Checkout',
                  onTap: _showWalkInCheckoutDialog,
                ),
                _DeskAction(
                  icon: Icons.price_check_outlined,
                  label: 'Collect balance',
                  onTap: _showCollectBalanceDialog,
                ),
              ],
            ),
            if (!compact) const SizedBox(height: 4),
          ],
        );
      },
    ),
  );

  Widget _walkInPanel() => _Panel(
    title: 'Walk-in services',
    trailing: Text(
      '${_walkIns.where((w) => !w.isServiceComplete).length} active',
    ),
    child: _walkIns.isEmpty
        ? const Text(
            'No walk-ins yet. Start a visit with New walk-in.',
            style: TextStyle(color: AppTheme.onSurfaceVariantLight),
          )
        : Column(
            children: [
              for (final walkIn in _walkIns)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: walkIn.paymentCollected
                        ? Colors.grey.shade200
                        : AppTheme.primary.withAlpha(25),
                    child: Icon(
                      walkIn.paymentCollected
                          ? Icons.check
                          : Icons.spa_outlined,
                      color: AppTheme.primary,
                    ),
                  ),
                  title: Text(walkIn.customer),
                  subtitle: Text(
                    '${walkIn.service} · ${walkIn.durationMinutes} min · '
                    '${walkIn.therapistName} · ${walkIn.statusLabel}'
                    '${walkIn.paymentCollected ? '' : ' · ${walkIn.remainingLabel}'}',
                  ),
                  isThreeLine: true,
                  trailing: walkIn.paymentCollected
                      ? Text('₱${walkIn.amount.toStringAsFixed(0)} paid')
                      : TextButton(
                          onPressed: () => _checkoutWalkIn(walkIn),
                          child: const Text('Checkout'),
                        ),
                ),
            ],
          ),
  );

  Future<void> _showWalkInCheckoutDialog() async {
    final active = _walkIns
        .where((walkIn) => !walkIn.paymentCollected)
        .toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('There are no active walk-ins to check out.'),
        ),
      );
      return;
    }
    final selected = await showDialog<WalkIn>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Checkout walk-in'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final walkIn in active)
                  ListTile(
                    title: Text(walkIn.customer),
                    subtitle: Text(
                      '${walkIn.service} · ₱${walkIn.amount.toStringAsFixed(0)} · '
                      '${walkIn.therapistName} · ${walkIn.statusLabel}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(dialogContext, walkIn),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (selected != null && mounted) _checkoutWalkIn(selected);
  }

  Future<void> _checkoutWalkIn(WalkIn walkIn) async {
    if (walkIn.paymentCollected) return;
    var method = 'Cash';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Complete checkout'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${walkIn.customer} · ${walkIn.service}'),
              const SizedBox(height: 8),
              Text('Amount due: ₱${walkIn.amount.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: method,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: const ['Cash', 'Card', 'GCash']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => method = value ?? method),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Collect payment'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _cashierRepository.checkoutWalkIn(walkIn.id, method: method);
    } catch (error) {
      _showBackendError(error);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment collected. ${walkIn.customer} checked out.'),
      ),
    );
  }

  Widget _paymentReviewPanel() => AnimatedBuilder(
    animation: PaymentBookingStore.instance,
    builder: (context, _) {
      final bookings = PaymentBookingStore.instance.pendingBookings;
      return _Panel(
        title: 'Payment verification',
        trailing: bookings.isEmpty
            ? const Text(
                'No pending proofs',
                style: TextStyle(color: AppTheme.onSurfaceVariantLight),
              )
            : _PaymentPill('${bookings.length} pending'),
        child: bookings.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Submitted payment screenshots will appear here for review.',
                  style: TextStyle(color: AppTheme.onSurfaceVariantLight),
                ),
              )
            : Column(
                children: [
                  for (final booking in bookings)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          booking.receiptImage,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        booking.serviceName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'PHP ${booking.paymentAmount.toStringAsFixed(0)} · Ref ${booking.transactionReference}\n${booking.appointmentDate.toLocal().toString().split(' ').first} at ${booking.startTime}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _reviewPayment(booking),
                    ),
                ],
              ),
      );
    },
  );

  Widget _bookingDashboard() => AnimatedBuilder(
    animation: PaymentBookingStore.instance,
    builder: (context, _) {
      final allBookings = PaymentBookingStore.instance.bookings;
      final today = DateUtils.dateOnly(DateTime.now());
      final todayBookings = allBookings
          .where(
            (booking) => DateUtils.isSameDay(booking.appointmentDate, today),
          )
          .toList();
      final pendingPayments = allBookings
          .where(
            (booking) =>
                booking.paymentStatus == PaymentStatus.pendingVerification,
          )
          .length;
      final checkedIn = todayBookings
          .where((booking) => booking.bookingStatus == BookingStatus.checkedIn)
          .length;
      final inProgress = todayBookings
          .where((booking) => booking.bookingStatus == BookingStatus.inProgress)
          .length;
      final completed = todayBookings
          .where((booking) => booking.bookingStatus == BookingStatus.completed)
          .length;
      final cancelled = todayBookings
          .where((booking) => booking.bookingStatus == BookingStatus.cancelled)
          .length;
      final confirmed = allBookings
          .where((booking) => booking.bookingStatus == BookingStatus.confirmed)
          .length;
      final visible = _filteredBookings(allBookings);

      return _Panel(
        title: 'Booking dashboard',
        trailing: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${visible.length} of ${allBookings.length}',
              style: const TextStyle(color: AppTheme.onSurfaceVariantLight),
            ),
            TextButton.icon(
              onPressed: () => context.push(AppRoutes.adminOnlineInProgress),
              icon: const Icon(Icons.timer_outlined, size: 18),
              label: const Text('In-progress dashboard'),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 840 ? 4 : 2;
                const gap = 10.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(
                      width: width,
                      child: _BookingMetric(
                        label: 'Appointments today',
                        count: todayBookings.length,
                        icon: Icons.calendar_today_outlined,
                        color: AppTheme.info,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _BookingMetric(
                        label: 'Pending verification',
                        count: pendingPayments,
                        icon: Icons.hourglass_top_rounded,
                        color: AppTheme.warning,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _BookingMetric(
                        label: 'Confirmed bookings',
                        count: confirmed,
                        icon: Icons.event_available_rounded,
                        color: AppTheme.primary,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _BookingMetric(
                        label: 'Clients checked in',
                        count: checkedIn,
                        icon: Icons.how_to_reg_rounded,
                        color: AppTheme.secondary,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _BookingMetric(
                        label: 'Services in progress',
                        count: inProgress,
                        icon: Icons.spa_outlined,
                        color: const Color(0xFF7B4DBA),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _BookingMetric(
                        label: 'Completed today',
                        count: completed,
                        icon: Icons.task_alt_rounded,
                        color: AppTheme.success,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _BookingMetric(
                        label: 'Cancelled today',
                        count: cancelled,
                        icon: Icons.event_busy_outlined,
                        color: AppTheme.error,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _bookingSearchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search client, reference, therapist, service',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<BookingStatus?>(
                    initialValue: _bookingStatusFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Booking status',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<BookingStatus?>(
                        value: null,
                        child: Text(
                          'All booking statuses',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...BookingStatus.values.map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(
                            status.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _bookingStatusFilter = value),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<PaymentStatus?>(
                    initialValue: _paymentStatusFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Payment status',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<PaymentStatus?>(
                        value: null,
                        child: Text(
                          'All payment statuses',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...PaymentStatus.values.map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(
                            status.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _paymentStatusFilter = value),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _pickBookingDateRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _bookingDateRange == null
                        ? 'Any date'
                        : '${_shortDate(_bookingDateRange!.start)} – ${_shortDate(_bookingDateRange!.end)}',
                  ),
                ),
                SizedBox(
                  width: 175,
                  child: DropdownButtonFormField<_BookingSort>(
                    initialValue: _bookingSort,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Sort by',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _BookingSort.appointmentTime,
                        child: Text(
                          'Appointment time',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: _BookingSort.newest,
                        child: Text(
                          'Newest booking',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: _BookingSort.status,
                        child: Text(
                          'Status',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(
                      () =>
                          _bookingSort = value ?? _BookingSort.appointmentTime,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _clearBookingFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear filters'),
                ),
                if (_hasActiveBookingFilters)
                  const Chip(
                    avatar: Icon(Icons.filter_alt, size: 16),
                    label: Text('Filters active'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (allBookings.isEmpty)
              const _BookingEmptyState(
                message: 'No appointments yet. New client bookings will appear here.',
              )
            else if (visible.isEmpty)
              const _BookingEmptyState(
                message: 'No appointments match these filters. Clear filters or change your search.',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < 700
                    ? Column(
                        children: [
                          for (final booking in visible)
                            _mobileBookingCard(booking),
                        ],
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Reference')),
                            DataColumn(label: Text('Appointment')),
                            DataColumn(label: Text('Client / Contact')),
                            DataColumn(label: Text('Service / Therapist')),
                            DataColumn(label: Text('Duration')),
                            DataColumn(label: Text('Booking')),
                            DataColumn(label: Text('Payment')),
                            DataColumn(label: Text('Total')),
                            DataColumn(label: Text('Actions')),
                          ],
                          rows: [
                            for (final booking in visible)
                              DataRow(
                                cells: [
                                  DataCell(
                                    Text(booking.referenceNumber),
                                    onTap: () => _showBookingDetails(booking),
                                  ),
                                  DataCell(
                                    Text(
                                      '${_shortDate(booking.appointmentDate)}\n${booking.startTime}',
                                    ),
                                    onTap: () => _showBookingDetails(booking),
                                  ),
                                  DataCell(
                                    Text(
                                      '${booking.clientName}\n${booking.clientPhone.isEmpty ? booking.clientEmail : booking.clientPhone}',
                                    ),
                                    onTap: () => _showBookingDetails(booking),
                                  ),
                                  DataCell(
                                    Text(
                                      '${booking.serviceName}\n${booking.therapistName}',
                                    ),
                                    onTap: () => _showBookingDetails(booking),
                                  ),
                                  DataCell(
                                    Text('${booking.durationMinutes} min'),
                                  ),
                                  DataCell(
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _bookingStatusBadge(
                                          booking.bookingStatus,
                                        ),
                                        if (booking.bookingStatus ==
                                            BookingStatus.inProgress)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 5,
                                            ),
                                            child: _BookingServiceTimer(
                                              startedAt:
                                                  booking.serviceStartedAt,
                                              durationMinutes:
                                                  booking.durationMinutes,
                                            ),
                                          ),
                                      ],
                                    ),
                                    onTap: () => _showBookingDetails(booking),
                                  ),
                                  DataCell(
                                    _paymentStatusBadge(booking.paymentStatus),
                                  ),
                                  DataCell(
                                    Text(
                                      'PHP ${booking.totalAmount.toStringAsFixed(0)}',
                                    ),
                                  ),
                                  DataCell(
                                    Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          tooltip: 'View details',
                                          onPressed: () =>
                                              _showBookingDetails(booking),
                                          icon: const Icon(Icons.open_in_new),
                                        ),
                                        ..._quickBookingAction(booking),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
              ),
          ],
        ),
      );
    },
  );

  bool get _hasActiveBookingFilters =>
      _bookingSearchController.text.trim().isNotEmpty ||
      _bookingStatusFilter != null ||
      _paymentStatusFilter != null ||
      _bookingDateRange != null;

  List<Booking> _filteredBookings(List<Booking> bookings) {
    final query = _bookingSearchController.text.trim().toLowerCase();
    final result = bookings.where((booking) {
      final matchesQuery =
          query.isEmpty ||
          [
            booking.clientName,
            booking.clientPhone,
            booking.clientEmail,
            booking.referenceNumber,
            booking.serviceName,
            booking.therapistName,
          ].any((field) => field.toLowerCase().contains(query));
      final range = _bookingDateRange;
      final matchesDate =
          range == null ||
          (!DateUtils.dateOnly(booking.appointmentDate)
                  .isBefore(DateUtils.dateOnly(range.start)) &&
              !DateUtils.dateOnly(booking.appointmentDate)
                  .isAfter(DateUtils.dateOnly(range.end)));
      return matchesQuery &&
          matchesDate &&
          (_bookingStatusFilter == null ||
              booking.bookingStatus == _bookingStatusFilter) &&
          (_paymentStatusFilter == null ||
              booking.paymentStatus == _paymentStatusFilter);
    }).toList();
    switch (_bookingSort) {
      case _BookingSort.appointmentTime:
        result.sort(
          (a, b) => _appointmentDateTime(a).compareTo(_appointmentDateTime(b)),
        );
        break;
      case _BookingSort.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _BookingSort.status:
        result.sort(
          (a, b) => a.bookingStatus.index.compareTo(b.bookingStatus.index),
        );
        break;
    }
    return result;
  }

  Future<void> _pickBookingDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
      initialDateRange: _bookingDateRange,
    );
    if (range != null && mounted) setState(() => _bookingDateRange = range);
  }

  void _clearBookingFilters() => setState(() {
    _bookingSearchController.clear();
    _bookingStatusFilter = null;
    _paymentStatusFilter = null;
    _bookingDateRange = null;
  });

  Widget _mobileBookingCard(Booking booking) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.referenceNumber,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'View details',
                onPressed: () => _showBookingDetails(booking),
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
          Text('${_shortDate(booking.appointmentDate)} · ${booking.startTime}'),
          Text('${booking.clientName} · ${booking.serviceName}'),
          Text(
            '${booking.therapistName} · ${booking.durationMinutes} min · PHP ${booking.totalAmount.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _bookingStatusBadge(booking.bookingStatus),
              _paymentStatusBadge(booking.paymentStatus),
            ],
          ),
          if (booking.bookingStatus == BookingStatus.inProgress) ...[
            const SizedBox(height: 8),
            _BookingServiceTimer(
              startedAt: booking.serviceStartedAt,
              durationMinutes: booking.durationMinutes,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: _quickBookingAction(booking)),
        ],
      ),
    ),
  );

  List<Widget> _quickBookingAction(Booking booking) => [
    if (booking.paymentStatus == PaymentStatus.pendingVerification)
      TextButton(
        onPressed: () => _reviewPayment(booking),
        child: const Text('Review payment'),
      ),
    if (_nextBookingAction(booking) case final action?)
      TextButton(
        onPressed: () => _confirmBookingTransition(booking, action),
        child: Text(_actionLabel(action)),
      ),
    if (booking.bookingStatus != BookingStatus.cancelled &&
        booking.bookingStatus != BookingStatus.completed)
      IconButton(
        tooltip: 'Cancel booking',
        onPressed: () => _cancelBooking(booking),
        icon: const Icon(Icons.cancel_outlined, color: AppTheme.error),
      ),
  ];

  BookingStatus? _nextBookingAction(Booking booking) =>
      switch (booking.bookingStatus) {
        BookingStatus.pendingPayment => BookingStatus.confirmed,
        BookingStatus.confirmed => BookingStatus.checkedIn,
        BookingStatus.checkedIn => BookingStatus.inProgress,
        BookingStatus.inProgress => BookingStatus.completed,
        BookingStatus.completed || BookingStatus.cancelled => null,
      };

  String _actionLabel(BookingStatus next) => switch (next) {
    BookingStatus.pendingPayment => 'Pending payment',
    BookingStatus.confirmed => 'Confirm booking',
    BookingStatus.checkedIn => 'Check in',
    BookingStatus.inProgress => 'Start service',
    BookingStatus.completed => 'Complete service',
    BookingStatus.cancelled => 'Cancel booking',
  };

  Future<void> _confirmBookingTransition(
    Booking booking,
    BookingStatus next,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${_actionLabel(next)}?'),
        content: Text(
          'Apply this change to ${booking.referenceNumber}? Booking status and payment status are tracked separately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_actionLabel(next)),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
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
              : 'This action is no longer valid for this booking.',
        ),
      ),
    );
  }

  Future<void> _cancelBooking(Booking booking) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Cancellation reason',
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'A reason is required'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false)
                Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('Confirm cancellation'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    final updated = await PaymentBookingStore.instance.transitionBooking(
      booking.id,
      next: BookingStatus.cancelled,
      adminId: 'demo-admin',
      reason: reason,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated
              ? 'Booking cancelled'
              : 'Booking could not be cancelled from its current state.',
        ),
      ),
    );
  }

  Future<void> _showBookingDetails(Booking booking) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Booking ${booking.referenceNumber}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _bookingStatusBadge(booking.bookingStatus),
                    _paymentStatusBadge(booking.paymentStatus),
                  ],
                ),
                if (booking.bookingStatus == BookingStatus.inProgress) ...[
                  const SizedBox(height: 8),
                  _BookingServiceTimer(
                    startedAt: booking.serviceStartedAt,
                    durationMinutes: booking.durationMinutes,
                  ),
                ],
                const SizedBox(height: 14),
                _detailSection('Booking information', [
                  'Created: ${booking.createdAt.toLocal()}',
                  'Appointment: ${_shortDate(booking.appointmentDate)} at ${booking.startTime}',
                  'Service: ${booking.serviceName}',
                  if (booking.serviceDescription.isNotEmpty)
                    booking.serviceDescription,
                  'Duration: ${booking.durationMinutes} minutes',
                  'Expected end: ${_expectedEnd(booking)}',
                  'Therapist: ${booking.therapistName}',
                  'Client: ${booking.clientName}',
                  'Phone: ${booking.clientPhone.isEmpty ? 'Not provided' : booking.clientPhone}',
                  'Email: ${booking.clientEmail.isEmpty ? 'Not provided' : booking.clientEmail}',
                  'Total: PHP ${booking.totalAmount.toStringAsFixed(2)}',
                  'Balance due: PHP ${booking.remainingBalance.toStringAsFixed(2)}',
                  'Payment completion: ${booking.balancePaid ? 'Paid in full' : 'Balance due'}',
                  'Discount: PHP ${booking.discountAmount.toStringAsFixed(2)}',
                ]),
                _detailSection('Payment information', [
                  'Method: ${booking.paymentMethod}',
                  'Transaction reference: ${booking.transactionReference}',
                  '${booking.paymentStatus == PaymentStatus.verified ? 'Verified' : 'Submitted'} down payment: PHP ${booking.paymentAmount.toStringAsFixed(2)}',
                  'Submitted: ${booking.paymentSubmittedAt.toLocal()}',
                  'Reviewed: ${booking.paymentReviewedAt?.toLocal() ?? 'Not reviewed'}',
                  'Reviewed by: ${booking.paymentReviewedBy ?? '—'}',
                  if (booking.balancePayment case final balance?) ...[
                    'Balance collected: PHP ${balance.amount.toStringAsFixed(2)} by ${balance.method}',
                    'Collected at: ${balance.collectedAt.toLocal()} by ${balance.collectedBy}',
                  ],
                  'Rejection reason: ${booking.paymentRejectionReason ?? '—'}',
                ]),
                _detailSection('Payment proof history', [
                  for (
                    var index = 0;
                    index < booking.proofSubmissions.length;
                    index++
                  )
                    'Submission ${index + 1}: ref ${booking.proofSubmissions[index].transactionReference}, PHP ${booking.proofSubmissions[index].amount.toStringAsFixed(2)}, submitted ${booking.proofSubmissions[index].submittedAt.toLocal()}${booking.proofSubmissions[index].rejectionReason == null ? '' : ', rejection: ${booking.proofSubmissions[index].rejectionReason}'}',
                ]),
                GestureDetector(
                  onTap: () => _showProofImage(booking),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      booking.receiptImage,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => BookingReceiptService.download(booking),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Open current receipt PDF'),
                  ),
                ),
                _detailSection('Appointment activity', [
                  for (final event in booking.activity.reversed)
                    '${event.at.toLocal()} · ${_activityLabel(event.type)} · ${event.actor}${event.note == null ? '' : ' — ${event.note}'}',
                ]),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (booking.paymentStatus ==
                        PaymentStatus.pendingVerification) ...[
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _reviewPayment(booking);
                        },
                        child: const Text('Review payment'),
                      ),
                    ],
                    if (_nextBookingAction(booking) case final action?)
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _confirmBookingTransition(booking, action);
                        },
                        child: Text(_actionLabel(action)),
                      ),
                    if (booking.bookingStatus != BookingStatus.cancelled &&
                        booking.bookingStatus != BookingStatus.completed)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _cancelBooking(booking);
                        },
                        child: const Text('Cancel booking'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailSection(String title, List<String> lines) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const Divider(),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(line),
          ),
      ],
    ),
  );

  Future<void> _showProofImage(Booking booking) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: InteractiveViewer(
        minScale: 0.6,
        maxScale: 4,
        child: Image.memory(booking.receiptImage, fit: BoxFit.contain),
      ),
    ),
  );

  Widget _bookingStatusBadge(BookingStatus status) {
    final mapped = switch (status) {
      BookingStatus.pendingPayment => const _StatusVisual(
        'Pending Payment',
        AppTheme.warning,
        Color(0xFFFFF3E0),
      ),
      BookingStatus.confirmed => const _StatusVisual(
        'Confirmed',
        AppTheme.primary,
        Color(0xFFE8F5E9),
      ),
      BookingStatus.checkedIn => const _StatusVisual(
        'Checked In',
        AppTheme.info,
        Color(0xFFE3F2FD),
      ),
      BookingStatus.inProgress => const _StatusVisual(
        'In Progress',
        Color(0xFF7B4DBA),
        Color(0xFFF1EAF8),
      ),
      BookingStatus.completed => const _StatusVisual(
        'Completed',
        AppTheme.success,
        Color(0xFFE8F5E9),
      ),
      BookingStatus.cancelled => const _StatusVisual(
        'Cancelled',
        AppTheme.error,
        Color(0xFFFFEBEE),
      ),
    };
    return _StatusBadge(
      label: mapped.label,
      foreground: mapped.foreground,
      background: mapped.background,
    );
  }

  Widget _paymentStatusBadge(PaymentStatus status) {
    final mapped = switch (status) {
      PaymentStatus.pendingVerification => const _StatusVisual(
        'Pending Verification',
        AppTheme.warning,
        Color(0xFFFFF3E0),
      ),
      PaymentStatus.verified => const _StatusVisual(
        'Verified',
        AppTheme.success,
        Color(0xFFE8F5E9),
      ),
      PaymentStatus.rejected => const _StatusVisual(
        'Rejected',
        AppTheme.error,
        Color(0xFFFFEBEE),
      ),
    };
    return _StatusBadge(
      label: mapped.label,
      foreground: mapped.foreground,
      background: mapped.background,
    );
  }

  String _shortDate(DateTime date) => '${date.month}/${date.day}/${date.year}';
  DateTime _appointmentDateTime(Booking booking) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(booking.startTime.trim());
    if (match == null) return booking.appointmentDate;
    var hour = int.parse(match.group(1)!);
    if (match.group(3)!.toUpperCase() == 'PM' && hour != 12) hour += 12;
    if (match.group(3)!.toUpperCase() == 'AM' && hour == 12) hour = 0;
    return DateTime(
      booking.appointmentDate.year,
      booking.appointmentDate.month,
      booking.appointmentDate.day,
      hour,
      int.parse(match.group(2)!),
    );
  }

  String _expectedEnd(Booking booking) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(booking.startTime.trim());
    if (match == null)
      return '${booking.startTime} + ${booking.durationMinutes} min';
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (match.group(3)!.toUpperCase() == 'PM' && hour != 12) hour += 12;
    if (match.group(3)!.toUpperCase() == 'AM' && hour == 12) hour = 0;
    final end = DateTime(
      booking.appointmentDate.year,
      booking.appointmentDate.month,
      booking.appointmentDate.day,
      hour,
      minute,
    ).add(Duration(minutes: booking.durationMinutes));
    final displayHour = end.hour % 12 == 0 ? 12 : end.hour % 12;
    final suffix = end.hour >= 12 ? 'PM' : 'AM';
    return '${_shortDate(end)} ${displayHour}:${end.minute.toString().padLeft(2, '0')} $suffix';
  }

  String _activityLabel(BookingActivityType type) => switch (type) {
    BookingActivityType.bookingCreated => 'Booking created',
    BookingActivityType.proofSubmitted => 'Payment proof submitted',
    BookingActivityType.paymentVerified => 'Payment verified',
    BookingActivityType.paymentRejected => 'Payment rejected',
    BookingActivityType.clientCheckedIn => 'Client checked in',
    BookingActivityType.serviceStarted => 'Service started',
    BookingActivityType.serviceCompleted => 'Service completed',
    BookingActivityType.balanceCollected => 'Remaining balance collected',
    BookingActivityType.bookingCancelled => 'Booking cancelled',
    BookingActivityType.bookingConfirmed => 'Booking confirmed',
  };

  Future<void> _reviewPayment(Booking booking) async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review payment proof'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${booking.serviceName} · PHP ${booking.paymentAmount.toStringAsFixed(0)}',
                ),
                Text('Reference: ${booking.transactionReference}'),
                Text(
                  'Submitted down payment: PHP ${booking.paymentAmount.toStringAsFixed(2)} / expected 30%: PHP ${booking.requiredDownPayment.toStringAsFixed(2)}',
                ),
                Text(
                  'Submitted: ${booking.paymentSubmittedAt.toLocal()} · ${booking.paymentMethod}',
                ),
                Text('Client: ${booking.clientName}'),
                Text('Booking: ${booking.referenceNumber}'),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InteractiveViewer(
                    minScale: 0.6,
                    maxScale: 4,
                    child: Image.memory(
                      booking.receiptImage,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Reject payment',
              style: TextStyle(color: AppTheme.error),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verify payment'),
          ),
        ],
      ),
    );
    if (decision == null || !mounted) return;
    if (decision) {
      final updated = await PaymentBookingStore.instance.verifyPayment(
        booking.id,
        adminId: 'demo-admin',
      );
      if (updated && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '30% down payment verified. Booking ${booking.referenceNumber} is confirmed.',
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not verify this proof. Check the 30% down payment, reference, and current status.',
            ),
          ),
        );
      }
      return;
    }

    final reason = await _askRejectionReason();
    if (reason == null || !mounted) return;
    final rejected = await PaymentBookingStore.instance.rejectPayment(
      booking.id,
      adminId: 'demo-admin',
      reason: reason,
    );
    if (rejected && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Payment proof rejected. The client can review the reason and resubmit.',
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This payment has already been reviewed. Refresh the booking list.',
          ),
        ),
      );
    }
  }

  Future<String?> _askRejectionReason() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reason for rejection'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Explain what needs to be corrected',
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'A rejection reason is required'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Reject payment'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }
}

class _MetricCard extends StatelessWidget {
  final String label, value, detail;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => _Panel(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppTheme.onSurfaceVariantLight),
              ),
              Icon(icon, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.onSurfaceVariantLight,
            ),
          ),
        ],
      ),
    ),
  );
}

enum _AdminSection {
  dashboard('Dashboard', Icons.dashboard_outlined),
  bookings('Bookings', Icons.calendar_month_outlined),
  onlineInProgress('Online In Progress', Icons.timer_outlined),
  therapists('Therapists', Icons.people_outline_rounded),
  paymentVerification('Payment Verification', Icons.fact_check_outlined),
  walkIns('Walk-ins', Icons.directions_walk),
  checkout('Checkout', Icons.point_of_sale),
  salesReport('Sales Report', Icons.bar_chart_outlined),
  serviceReport('Service Report', Icons.spa_outlined),
  therapistProfit('Therapist Profit', Icons.account_balance_wallet_outlined),
  clientChats('Customer Chats', Icons.chat_bubble_outline_rounded);

  const _AdminSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum _BookingSort { appointmentTime, newest, status }

class _StatusVisual {
  const _StatusVisual(this.label, this.foreground, this.background);
  final String label;
  final Color foreground;
  final Color background;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.foreground,
    required this.background,
  });
  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _BookingMetric extends StatelessWidget {
  const _BookingMetric({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFECEDE8)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withAlpha(24),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.onSurfaceVariantLight,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _BookingEmptyState extends StatelessWidget {
  const _BookingEmptyState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppTheme.surfaceVariantLight,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppTheme.onSurfaceVariantLight),
    ),
  );
}

class _Panel extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  const _Panel({this.title, this.trailing, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFECEDE8)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  title!,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
        ],
        child,
      ],
    ),
  );
}

enum _SalesPeriod {
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly'),
  yearly('Yearly'),
  custom('Custom');

  const _SalesPeriod(this.label);
  final String label;
}

class _SalesBucket {
  const _SalesBucket({
    required this.label,
    required this.amount,
    required this.transactionCount,
  });

  final String label;
  final double amount;
  final int transactionCount;
}

class _ReportRange {
  const _ReportRange({
    required this.start,
    required this.endExclusive,
    required this.label,
  });

  final DateTime start;
  final DateTime endExclusive;
  final String label;
}

class _ServiceBucket {
  const _ServiceBucket({
    required this.label,
    required this.walkIns,
    required this.onlineBookings,
    required this.serviceCounts,
  });

  final String label;
  final int walkIns;
  final int onlineBookings;
  final Map<String, int> serviceCounts;
  int get total => walkIns + onlineBookings;
}

class _ServiceCount {
  _ServiceCount({required this.id, required this.name});

  final String id;
  final String name;
  int walkIns = 0;
  int onlineBookings = 0;
  int get total => walkIns + onlineBookings;
}

class _TherapistProfitGroup {
  _TherapistProfitGroup({required this.id, required this.name});

  final String id;
  final String name;
  final List<_TherapistProfitRow> rows = [];

  double get total => rows.fold<double>(0, (sum, row) => sum + row.amount);
}

class _TherapistProfitRow {
  const _TherapistProfitRow({
    required this.therapistId,
    required this.therapistName,
    required this.clientName,
    required this.serviceName,
    required this.completedAt,
    required this.amount,
    required this.source,
  });

  final String therapistId;
  final String therapistName;
  final String clientName;
  final String serviceName;
  final DateTime completedAt;
  final double amount;
  final String source;
}

const _serviceColorValues = <int>[
  0xFF2E7D32,
  0xFF1976D2,
  0xFFEF6C00,
  0xFF7B1FA2,
];

Color _massageServiceColor(int index) =>
    Color(_serviceColorValues[index % _serviceColorValues.length]);

class _SalesBarChart extends StatelessWidget {
  const _SalesBarChart({required this.buckets});

  final List<_SalesBucket> buckets;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minWidth = buckets.length * 62.0;
      final chartWidth = constraints.maxWidth > minWidth
          ? constraints.maxWidth
          : minWidth;
      final maxAmount = buckets.fold<double>(
        0,
        (max, bucket) => bucket.amount > max ? bucket.amount : max,
      );
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: chartWidth,
          height: 220,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final bucket in buckets)
                SizedBox(
                  width: chartWidth / buckets.length,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          bucket.amount == 0
                              ? '—'
                              : '₱${bucket.amount.toStringAsFixed(0)}',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.onSurfaceVariantLight,
                          ),
                        ),
                        const SizedBox(height: 7),
                        SizedBox(
                          height: 132,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: maxAmount == 0 || bucket.amount == 0
                                  ? 2
                                  : 118 * bucket.amount / maxAmount,
                              width: 28,
                              decoration: BoxDecoration(
                                color:
                                    bucket.amount == maxAmount && maxAmount > 0
                                    ? AppTheme.primary
                                    : AppTheme.primary.withAlpha(125),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(7),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 30,
                          child: Text(
                            bucket.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.onSurfaceVariantLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _ServiceBarChart extends StatelessWidget {
  const _ServiceBarChart({required this.buckets, required this.services});

  final List<_ServiceBucket> buckets;
  final List<Map<String, dynamic>> services;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 14,
        runSpacing: 8,
        children: [
          for (var index = 0; index < services.length; index++)
            _ChartLegend(
              color: _massageServiceColor(index),
              label:
                  '${services[index]['name']} · ${services[index]['durationMinutes']} min',
            ),
        ],
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final minWidth = buckets.length * 76.0;
          final chartWidth = constraints.maxWidth > minWidth
              ? constraints.maxWidth
              : minWidth;
          final maxCount = buckets.fold<int>(0, (max, bucket) {
            final bucketMax = bucket.serviceCounts.values.fold<int>(
              0,
              (value, count) => count > value ? count : value,
            );
            return bucketMax > max ? bucketMax : max;
          });
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartWidth,
              height: 224,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final bucket in buckets)
                    SizedBox(
                      width: chartWidth / buckets.length,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${bucket.total}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppTheme.onSurfaceVariantLight,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 138,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    for (
                                      var index = 0;
                                      index < services.length;
                                      index++
                                    ) ...[
                                      if (index > 0) const SizedBox(width: 3),
                                      _serviceBar(
                                        bucket.serviceCounts[services[index]['id']
                                                as String] ??
                                            0,
                                        maxCount,
                                        _massageServiceColor(index),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 30,
                              child: Text(
                                bucket.label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.onSurfaceVariantLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ],
  );

  Widget _serviceBar(int value, int maxCount, Color color) => Container(
    height: maxCount == 0 || value == 0 ? 2 : 120 * value / maxCount,
    width: 12,
    decoration: BoxDecoration(
      color: value == 0 ? color.withAlpha(80) : color,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
    ),
  );
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, color: color),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

class _BookingServiceTimer extends StatefulWidget {
  const _BookingServiceTimer({
    required this.startedAt,
    required this.durationMinutes,
  });

  final DateTime? startedAt;
  final int durationMinutes;

  @override
  State<_BookingServiceTimer> createState() => _BookingServiceTimerState();
}

class _BookingServiceTimerState extends State<_BookingServiceTimer> {
  static const _preparationAllowance = Duration(minutes: 5);
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.startedAt != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _clock(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 999999);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.startedAt;
    if (start == null) {
      return const _TimerPill(
        label: 'Timer unavailable',
        color: AppTheme.warning,
      );
    }

    final elapsed = DateTime.now().difference(start);
    if (elapsed.isNegative || elapsed < _preparationAllowance) {
      final remaining = elapsed.isNegative
          ? _preparationAllowance
          : _preparationAllowance - elapsed;
      return _TimerPill(
        label: 'Preparation · ${_clock(remaining)}',
        color: AppTheme.warning,
      );
    }

    final serviceElapsed = elapsed - _preparationAllowance;
    final serviceDuration = Duration(minutes: widget.durationMinutes);
    final serviceRemaining = serviceDuration - serviceElapsed;
    if (serviceRemaining > Duration.zero) {
      return _TimerPill(
        label: 'Service · ${_clock(serviceRemaining)} left',
        color: AppTheme.primary,
      );
    }
    return _TimerPill(
      label: 'Overtime · ${_clock(serviceElapsed - serviceDuration)}',
      color: AppTheme.error,
    );
  }
}

class _TimerPill extends StatelessWidget {
  const _TimerPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: color.withAlpha(22),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _Sale {
  final String customer, service, time, method, source;
  final double amount;
  final DateTime createdAt;
  _Sale(this.customer, this.service, this.amount, this.time, this.method, {DateTime? createdAt, this.source = 'Walk-in checkout'})
    : createdAt = createdAt ?? DateTime.now();
}

typedef _WalkIn = WalkIn;

class _TransactionRow {
  final String customer, service, time, method, source;
  final double amount;
  final DateTime createdAt;

  const _TransactionRow({
    required this.customer,
    required this.service,
    required this.time,
    required this.method,
    required this.source,
    required this.amount,
    required this.createdAt,
  });

  factory _TransactionRow.fromSale(_Sale sale) => _TransactionRow(
    customer: sale.customer,
    service: sale.service,
    time: sale.time,
    method: sale.method,
    source: sale.source,
    amount: sale.amount,
    createdAt: sale.createdAt,
  );

  factory _TransactionRow.fromBooking(Booking booking) {
    final createdAt = booking.paymentReviewedAt ?? booking.createdAt;
    final hour = createdAt.hour % 12 == 0 ? 12 : createdAt.hour % 12;
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return _TransactionRow(
      customer: booking.clientName,
      service: booking.serviceName,
      time: '$hour:$minute ${createdAt.hour >= 12 ? 'PM' : 'AM'}',
      method: booking.paymentMethod,
      source: 'Online booking · down payment',
      amount: booking.paymentAmount,
      createdAt: createdAt,
    );
  }

  factory _TransactionRow.fromBalancePayment(
    Booking booking,
    BalancePayment payment,
  ) {
    final hour = payment.collectedAt.hour % 12 == 0
        ? 12
        : payment.collectedAt.hour % 12;
    final minute = payment.collectedAt.minute.toString().padLeft(2, '0');
    return _TransactionRow(
      customer: booking.clientName,
      service: '${booking.serviceName} · balance',
      time: '$hour:$minute ${payment.collectedAt.hour >= 12 ? 'PM' : 'AM'}',
      method: payment.method,
      source: 'Online booking · balance',
      amount: payment.amount,
      createdAt: payment.collectedAt,
    );
  }
}

class _PaymentPill extends StatelessWidget {
  final String label;
  const _PaymentPill(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.surfaceVariantLight,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        color: AppTheme.onSurfaceVariantLight,
      ),
    ),
  );
}

class _OpenPill extends StatelessWidget {
  const _OpenPill();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFE6F4E8),
      borderRadius: BorderRadius.circular(99),
    ),
    child: const Text(
      'OPEN',
      style: TextStyle(
        color: AppTheme.success,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DeskAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DeskAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      foregroundColor: AppTheme.primary,
    ),
  );
}
