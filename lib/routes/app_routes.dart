import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../presentation/sign_up_login_screen/sign_up_login_screen.dart';
import '../presentation/client_dashboard_screen/client_dashboard_screen.dart';
import '../presentation/client_dashboard_screen/client_bookings_screen.dart';
import '../presentation/client_dashboard_screen/client_profile_screen.dart';
import '../presentation/client_dashboard_screen/client_notifications_screen.dart';
import '../presentation/admin_dashboard_screen/therapist_management_screen.dart';
import '../presentation/therapist_dashboard_screen/therapist_dashboard_screen.dart';
import '../presentation/admin_dashboard_screen/admin_dashboard_screen.dart';
import '../presentation/admin_dashboard_screen/online_booking_in_progress_screen.dart';
import '../presentation/Appointment_booking/appointment_booking_screen.dart';
import '../widget/app_scaffold.dart';

class AppRoutes {
  static const String initial = '/';
  static const String signUpLogin = '/sign-up-login-screen';
  static const String clientDashboard = '/client-dashboard-screen';
  static const String clientBookings = '/client-bookings-screen';
  static const String clientProfile = '/client-profile-screen';
  static const String clientNotifications = '/client-notifications-screen';
  static const String therapistManagement =
      '/admin-dashboard-screen/therapists';
  static const String therapistDashboard = '/therapist-dashboard-screen';
  static const String adminDashboard = '/admin-dashboard-screen';
  static const String adminOnlineInProgress =
      '/admin-dashboard-screen/online-in-progress';
  static const String appointmentBooking = '/appointment-booking-screen';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.initial,
  routes: [
    GoRoute(
      path: AppRoutes.initial,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const SignUpLoginScreen(),
        transitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: AppRoutes.signUpLogin,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const SignUpLoginScreen(),
        transitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: AppRoutes.appointmentBooking,
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return CustomTransitionPage(
          key: state.pageKey,
          child: AppointmentBookingScreen(serviceData: extra),
          transitionDuration: const Duration(milliseconds: 280),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
        );
      },
    ),
    GoRoute(
      path: AppRoutes.clientNotifications,
      builder: (context, state) => const ClientNotificationsScreen(),
    ),
    GoRoute(
      path: AppRoutes.therapistManagement,
      builder: (context, state) => const TherapistManagementScreen(),
    ),
    GoRoute(
      path: AppRoutes.therapistDashboard,
      builder: (context, state) =>
          TherapistDashboardScreen(email: state.extra as String? ?? ''),
    ),
    GoRoute(
      path: AppRoutes.adminDashboard,
      builder: (context, state) => const AdminDashboardScreen(),
    ),
    GoRoute(
      path: AppRoutes.adminOnlineInProgress,
      builder: (context, state) => const OnlineBookingInProgressScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppScaffold(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.clientDashboard,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ClientDashboardScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.clientBookings,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ClientBookingsScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.clientProfile,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ClientProfileScreen()),
            ),
          ],
        ),
      ],
    ),
  ],
);
