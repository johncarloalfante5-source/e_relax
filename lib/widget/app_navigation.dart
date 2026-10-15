import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/payment_booking_store.dart';
import '../data/stores/auth_session_store.dart';

class AppNavigation extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppNavigation({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        PaymentBookingStore.instance,
        AuthSessionStore.instance,
      ]),
      builder: (context, _) {
        final userId = AuthSessionStore.instance.profile?.id;
        final unreadBookings = userId == null
            ? 0
            : PaymentBookingStore.instance.unreadBookingNoticeCountForUser(userId);
        return NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) async {
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
            if (index == 1 && userId != null) {
              try {
                await PaymentBookingStore.instance.markBookingNoticesRead(
                  userId: userId,
                );
              } catch (_) {
                // Keep persisted unread state visible if the read request fails.
              }
            }
          },
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: unreadBookings == 0
                  ? const Icon(Icons.calendar_today_outlined)
                  : Badge(
                      label: Text('$unreadBookings'),
                      child: const Icon(Icons.calendar_today_outlined),
                    ),
              selectedIcon: unreadBookings == 0
                  ? const Icon(Icons.calendar_today_rounded)
                  : Badge(
                      label: Text('$unreadBookings'),
                      child: const Icon(Icons.calendar_today_rounded),
                    ),
              label: 'Bookings',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        );
      },
    );
  }
}
