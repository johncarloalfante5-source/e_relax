import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/therapist_roster_store.dart';
import '../../data/stores/auth_session_store.dart';
import '../../data/payment_booking_store.dart';
import '../../models/profile.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import './widget/auth_form_widget.dart';
import './widget/auth_header_widget.dart';

class SignUpLoginScreen extends StatefulWidget {
  const SignUpLoginScreen({super.key});

  @override
  State<SignUpLoginScreen> createState() => _SignUpLoginScreenState();
}

class _SignUpLoginScreenState extends State<SignUpLoginScreen>
    with TickerProviderStateMixin {
  bool _isLogin = true;
  bool _isLoading = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    _fadeController.reverse().then((_) {
      setState(() => _isLogin = !_isLogin);
      _fadeController.forward();
    });
  }

  Future<void> _onSubmit(Map<String, String> formData) async {
    setState(() => _isLoading = true);
    try {
      final session = AuthSessionStore.instance;
      if (_isLogin) {
        final profile = await session.signIn(
          email: formData['email'] ?? '',
          password: formData['password'] ?? '',
        );
        await PaymentBookingStore.instance.initialize();
        await TherapistRosterStore.instance.initialize();
        ClientSession.instance.signIn(
          email: profile.email,
          displayName: profile.displayName,
          clientId: profile.id,
        );
        if (mounted) {
          final destination = switch (profile.role) {
            AppRole.client => AppRoutes.clientDashboard,
            AppRole.admin || AppRole.cashier => AppRoutes.adminDashboard,
            AppRole.therapist => AppRoutes.therapistDashboard,
          };
          context.go(destination, extra: profile.email);
        }
      } else {
        await session.signUpClient(
          email: formData['email'] ?? '',
          password: formData['password'] ?? '',
          displayName: formData['name'] ?? '',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account created. Check your email to confirm it, then sign in.')),
          );
          setState(() => _isLogin = true);
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Authentication failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: size.height - MediaQuery.of(context).padding.top,
            ),
            child: Center(
              child: Container(
                width: isTablet ? 480 : double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 0 : 24,
                  vertical: 24,
                ),
                child: isTablet
                    ? Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(color: AppTheme.surfaceVariantLight),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: _buildContent(),
                        ),
                      )
                    : _buildContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeaderWidget(),
          const SizedBox(height: 32),
          _buildModeToggle(),
          const SizedBox(height: 24),
          AuthFormWidget(
            isLogin: _isLogin,
            isLoading: _isLoading,
            onSubmit: _onSubmit,
            onToggleMode: _toggleMode,
            onResetPassword: (email) => AuthSessionStore.instance.resetPassword(email),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariantLight,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildToggleTab('Sign In', _isLogin),
          _buildToggleTab('Create Account', !_isLogin),
        ],
      ),
    );
  }

  Widget _buildToggleTab(String label, bool isActive) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if ((label == 'Sign In') != _isLogin) _toggleMode();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(20),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive
                  ? AppTheme.primary
                  : AppTheme.onSurfaceVariantLight,
            ),
          ),
        ),
      ),
    );
  }
}
