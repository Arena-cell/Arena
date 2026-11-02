import 'core/services/push_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/bookings/pages/payment_return_page.dart';
import 'features/authentication/pages/welcome_page.dart';
import 'features/authentication/pages/profile_completion_page.dart';
import 'core/services/account_access.dart';

import 'core/theme/app_colors.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _logoScale = Tween<double>(begin: .96, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _logoOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0, .62, curve: Curves.easeOut),
    );
    _entranceController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkLogin();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  String? _error;
  Future<void> checkLogin() async {
    if (mounted) setState(() => _error = null);
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      final validPhone =
          user?.phoneConfirmedAt != null &&
          RegExp(r'^\+?968\d{8}$').hasMatch(user?.phone ?? '');
      final complete =
          validPhone &&
          await client
                  .rpc('my_profile_complete')
                  .timeout(const Duration(seconds: 20)) ==
              true;
      final destination = accountDestination(
        hasSession: client.auth.currentSession != null,
        phone: user?.phone,
        phoneConfirmed: validPhone,
        profileComplete: complete,
      );
      if (destination == AccountDestination.phone && user != null) {
        await PushNotificationService.instance.deactivateCurrentToken();
        await client.auth.signOut();
      }
      if (!mounted) return;
      final Widget page = switch (destination) {
        AccountDestination.phone => const WelcomePage(),
        AccountDestination.completeProfile => const ProfileCompletionPage(),
        AccountDestination.home => const PaymentReturnPage(),
      };
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 240),
          transitionsBuilder:
              (_, animation, secondaryAnimation, child) =>
                  FadeTransition(opacity: animation, child: child),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'تعذر التحقق من الحساب. Check your connection and retry.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: AppColors.navy,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
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
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.white)),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: checkLogin,
                      child: const Text('Retry / إعادة المحاولة'),
                    ),
                  ],
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
