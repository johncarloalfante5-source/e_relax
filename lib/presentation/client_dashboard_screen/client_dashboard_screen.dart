import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/payment_booking_store.dart';
import 'client_admin_chat_entry.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import './widget/dashboard_header_widget.dart';
import './widget/popular_services_widget.dart';
import './widget/quick_stats_widget.dart';
import './widget/therapist_avatar_row_widget.dart';

class ClientDashboardScreen extends StatefulWidget {
  const ClientDashboardScreen({super.key});

  @override
  State<ClientDashboardScreen> createState() => _ClientDashboardScreenState();
}

class _ClientDashboardScreenState extends State<ClientDashboardScreen>
    with SingleTickerProviderStateMixin {
  // TODO: Replace with [Riverpod/Bloc] for production
  bool _isLoading = false;
  late AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _staggerController.forward();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    // TODO: Replace with real Firebase data fetch
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      extendBodyBehindAppBar: true,
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AppTheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Gradient AppBar (V4 Gradient variant)
            SliverAppBar(
              expandedHeight: 160,
              pinned: true,
              backgroundColor: AppTheme.primary,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: DashboardHeaderWidget(
                  staggerController: _staggerController,
                ),
                collapseMode: CollapseMode.pin,
              ),
              actions: [
                AnimatedBuilder(
                  animation: PaymentBookingStore.instance,
                  builder: (context, _) {
                    final unread = PaymentBookingStore.instance
                        .unreadNoticeCountForClient(localClientSessionId);
                    return IconButton(
                      tooltip: unread == 0
                          ? 'Notifications'
                          : '$unread unread notifications',
                      onPressed: () =>
                          context.push(AppRoutes.clientNotifications),
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                          if (unread > 0)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: AppTheme.secondary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.primary,
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),

            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                // Bottom padding for floating pill nav
                100,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Quick stats row
                  _buildFadeSlide(delay: 0, child: const QuickStatsWidget()),
                  const SizedBox(height: 20),

                  // Popular services
                  _buildFadeSlide(
                    delay: 100,
                    child: PopularServicesWidget(
                      isTablet: isTablet,
                      onBookService: (serviceData) {
                        context.push(
                          AppRoutes.appointmentBooking,
                          extra: serviceData,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Therapists row
                  _buildFadeSlide(
                    delay: 200,
                    child: const TherapistAvatarRowWidget(),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const ClientAdminChatEntry(),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'client-chat-fab',
            tooltip: 'Ask E-Relax Assistant',
            onPressed: () => context.push(AppRoutes.clientChat),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            child: const Icon(Icons.chat_bubble_outline_rounded),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'client-booking-fab',
            onPressed: () => context.push(AppRoutes.appointmentBooking),
            backgroundColor: AppTheme.secondary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Book Now',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            elevation: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildFadeSlide({required int delay, required Widget child}) {
    return AnimatedBuilder(
      animation: _staggerController,
      builder: (context, _) {
        final delayedValue = (((_staggerController.value * 800) - delay) / 400)
            .clamp(0.0, 1.0);
        final curved = Curves.easeOutCubic.transform(delayedValue);
        return Opacity(
          opacity: curved,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - curved)),
            child: child,
          ),
        );
      },
    );
  }
}
