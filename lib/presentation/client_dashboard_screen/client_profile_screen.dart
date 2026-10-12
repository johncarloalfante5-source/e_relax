import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/payment_booking_store.dart';
import '../../models/booking.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';

class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.backgroundLight,
    appBar: AppBar(
      title: const Text('My Profile'),
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          tooltip: 'Log out',
          onPressed: () => _confirmLogout(context),
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: ClientSession.instance,
      builder: (context, _) => AnimatedBuilder(
        animation: PaymentBookingStore.instance,
        builder: (context, _) {
          final session = ClientSession.instance;
          final bookings = PaymentBookingStore.instance.bookingsForClient(
            session.clientId,
          );
          final upcoming = bookings.where((booking) {
            return booking.bookingStatus != BookingStatus.completed &&
                booking.bookingStatus != BookingStatus.cancelled &&
                !DateUtils.dateOnly(
                  booking.appointmentDate,
                ).isBefore(DateUtils.dateOnly(DateTime.now()));
          }).length;
          final completed = bookings
              .where(
                (booking) => booking.bookingStatus == BookingStatus.completed,
              )
              .length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 110),
            children: [
              _ProfileHeader(name: session.clientName),
              const SizedBox(height: 20),
              _SectionCard(
                title: 'Personal information',
                children: [
                  _InfoRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Full name',
                    value: session.clientName,
                    trailing: TextButton(
                      onPressed: () => _editName(context, session.clientName),
                      child: const Text('Edit'),
                    ),
                  ),
                  const Divider(height: 1),
                  _InfoRow(
                    icon: Icons.email_outlined,
                    label: 'Email address',
                    value: session.email ?? 'Not available',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Your activity',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _ActivityStat(
                          label: 'Total bookings',
                          value: bookings.length,
                          icon: Icons.spa_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActivityStat(
                          label: 'Upcoming',
                          value: upcoming,
                          icon: Icons.event_available_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActivityStat(
                          label: 'Completed',
                          value: completed,
                          icon: Icons.check_circle_outline_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => context.go(AppRoutes.clientBookings),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('View bookings and receipts'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Account',
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: AppTheme.error,
                    ),
                    title: const Text('Log out'),
                    subtitle: const Text('Sign out of this client account'),
                    onTap: () => _confirmLogout(context),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );

  Future<void> _editName(BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit your name'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full name',
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().length < 2
                ? 'Enter at least 2 characters'
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) ClientSession.instance.updateDisplayName(name);
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout_rounded, color: AppTheme.primary),
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
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
    if (shouldLogout == true && context.mounted) {
      ClientSession.instance.signOut();
      context.go(AppRoutes.signUpLogin);
    }
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [AppTheme.primary, Color(0xFF2E7D32)],
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.white,
            child: Text(
              initials.isEmpty ? 'C' : initials,
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Client account',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(10),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Icon(icon, color: AppTheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.onSurfaceVariantLight,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class _ActivityStat extends StatelessWidget {
  const _ActivityStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    decoration: BoxDecoration(
      color: AppTheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        const SizedBox(height: 7),
        Text(
          value.toString(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    ),
  );
}
