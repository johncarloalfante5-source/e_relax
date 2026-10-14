import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';
import 'data/backend/supabase_client_provider.dart';
import 'data/stores/auth_session_store.dart';
import 'data/therapist_roster_store.dart';
import 'data/repositories/supabase_clinic_repository.dart';
import 'data/service_catalog.dart';
import 'data/payment_booking_store.dart';

import 'core/app_export.dart';
import 'widget/custom_error_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? startupError;

  bool hasShownError = false;

  // 🚨 CRITICAL: Custom error handling - DO NOT REMOVE
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (!hasShownError) {
      hasShownError = true;

      // Reset flag after 3 seconds to allow error widget on new screens
      Future.delayed(Duration(seconds: 5), () {
        hasShownError = false;
      });

      return CustomErrorWidget(errorDetails: details);
    }
    return SizedBox.shrink();
  };

  // 🚨 CRITICAL: Device orientation lock - DO NOT REMOVE
  try {
    await SupabaseClientProvider.initialize();
    await AuthSessionStore.instance.initialize();
    final restoredProfile = AuthSessionStore.instance.profile;
    if (restoredProfile != null) {
      ClientSession.instance.signIn(
        email: restoredProfile.email,
        displayName: restoredProfile.displayName,
        clientId: restoredProfile.id,
      );
    }
    await TherapistRosterStore.instance.initialize();
    await TherapistRosterStore.instance.watchDutyForDate(DateTime.now());
    final clinicRepository = SupabaseClinicRepository();
    final remoteServices = await clinicRepository.watchServices().first;
    ServiceCatalog.replaceFromBackend(remoteServices.map((service) => {
      'id': service.id,
      'name': service.name,
      'description': service.description,
      'price': service.price,
      'durationMinutes': service.durationMinutes,
      'rating': service.rating ?? 0,
      'imageUrl': service.imageUrl ?? '',
      'semanticLabel': service.semanticLabel ?? service.name,
      'category': service.category,
    }).toList());
    ServiceCatalog.connect(clinicRepository.watchServices());
    if (restoredProfile != null) await PaymentBookingStore.instance.initialize();
  } catch (error) {
    startupError = error.toString();
  }

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  GoRouter.optionURLReflectsImperativeAPIs = true;
  runApp(MyApp(startupError: startupError));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.startupError});
  final String? startupError;

  @override
  Widget build(BuildContext context) {
    if (startupError != null) {
      return MaterialApp(
        title: 'E-Relax setup',
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: SelectableText(
                    'E-Relax could not connect to Supabase.\n\n$startupError\n\n'
                    'Check SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY, then apply the migrations in supabase/ before launching again.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Sizer(
      builder: (context, orientation, screenType) {
        return MaterialApp.router(
          title: 'erelax',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          // 🚨 CRITICAL: NEVER REMOVE OR MODIFY
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.0)),
              child: BrandLaunchAnimation(child: child!),
            );
          },
          // 🚨 END CRITICAL SECTION
          debugShowCheckedModeBanner: false,
          routerConfig: appRouter,
        );
      },
    );
  }
}

class BrandLaunchAnimation extends StatefulWidget {
  const BrandLaunchAnimation({super.key, required this.child});

  final Widget child;

  @override
  State<BrandLaunchAnimation> createState() => _BrandLaunchAnimationState();
}

class _BrandLaunchAnimationState extends State<BrandLaunchAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..forward();

  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 0.0, end: 1.0).chain(
        CurveTween(curve: Curves.easeOut),
      ),
      weight: 68,
    ),
    TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 18),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.0, end: 0.0).chain(
        CurveTween(curve: Curves.easeIn),
      ),
      weight: 14,
    ),
  ]).animate(_controller);

  late final Animation<double> _scale = Tween<double>(begin: 0.82, end: 1)
      .animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      );

  bool _showBrand = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _showBrand = false);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showBrand)
          Material(
            color: Colors.white,
            child: FadeTransition(
              opacity: _opacity,
              child: Center(
                child: ScaleTransition(
                  scale: _scale,
                  child: Image.asset(
                    'assets/images/brand_logo.png',
                    width: MediaQuery.sizeOf(context).shortestSide * 0.72,
                    height: MediaQuery.sizeOf(context).shortestSide * 0.72,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
