import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/navigation/main_navigation_page.dart';
import 'features/authentication/pages/login_page.dart';
import 'features/authentication/pages/profile_completion_page.dart';
import 'features/authentication/pages/verify_email_page.dart';
import 'features/onboarding/location_permission_page.dart';
import 'core/services/guest_session.dart';
import 'core/theme/app_colors.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  static const _minimumSplashDuration = Duration(seconds: 2);
  late final AnimationController _entranceController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _logoScale = Tween<double>(begin: .72, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
    _logoOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0, .62, curve: Curves.easeOut),
    );
    _entranceController.forward();
    checkLogin();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> checkLogin() async {
    final splashDelay = Future<void>.delayed(_minimumSplashDuration);

    if (!mounted) return;

    final user = Supabase.instance.client.auth.currentUser;
    var complete = false;
    if (user != null && user.emailConfirmedAt != null) {
      final profile =
          await Supabase.instance.client
              .from('profiles')
              .select('onboarding_complete')
              .eq('id', user.id)
              .maybeSingle();
      // Profile completion is server-side account data. Auth metadata is not a
      // substitute for the required customer profile fields.
      complete = profile?['onboarding_complete'] == true;
    }

    if (!mounted) return;

    final preferences = await SharedPreferences.getInstance();
    final guestMode = await GuestSession.isEnabled();
    final locationSeen =
        preferences.getBool(LocationPermissionPage.seenKey) ?? false;
    if (!mounted) return;

    await splashDelay;
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 720),
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                user == null
                    ? guestMode
                        ? const MainNavigationPage()
                        : const LoginPage()
                    : user.emailConfirmedAt == null
                    ? const VerifyEmailPage()
                    : complete
                    ? locationSeen
                        ? const MainNavigationPage()
                        : const LocationPermissionPage()
                    : const ProfileCompletionPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: .985, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.12),
                radius: .9,
                colors: [Color(0xFF173D64), AppColors.navy],
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(42),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _logoOpacity,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: const Hero(
                        tag: 'playon-brand-logo',
                        child: Image(
                          image: AssetImage(
                            'assets/images/arena_splash_logo.png',
                          ),
                          width: 250,
                          height: 250,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: 54,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      borderRadius: BorderRadius.circular(8),
                      backgroundColor: Color(0x33FFFFFF),
                      color: AppColors.warmWhite,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
