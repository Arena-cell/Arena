import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/localization/app_localizations.dart';
import '../navigation/main_navigation_page.dart';

class LocationPermissionPage extends StatefulWidget {
  const LocationPermissionPage({super.key});

  static const seenKey = 'location_onboarding_seen';

  @override
  State<LocationPermissionPage> createState() => _LocationPermissionPageState();
}

class _LocationPermissionPageState extends State<LocationPermissionPage> {
  bool _loading = false;

  Future<void> _finish([Position? position]) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user != null) {
      try {
        await client
            .from('profiles')
            .update({
              'onboarding_complete': true,
              if (position != null) 'latitude': position.latitude,
              if (position != null) 'longitude': position.longitude,
            })
            .eq('id', user.id);
      } catch (_) {
        // Location remains optional when profile persistence is unavailable.
      }
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(LocationPermissionPage.seenKey, true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavigationPage()),
      (_) => false,
    );
  }

  Future<void> _allow() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Turn on location services to continue.',
                'فعّل خدمات الموقع للمتابعة.',
              ),
            ),
          ),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        final open = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(tr('Location permission', 'إذن الموقع')),
                content: Text(
                  tr(
                    'Location access is disabled permanently. You can enable it in app settings.',
                    'تم تعطيل الوصول إلى الموقع نهائيًا. يمكنك تفعيله من إعدادات التطبيق.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr('Not now', 'ليس الآن')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(tr('Open settings', 'فتح الإعدادات')),
                  ),
                ],
              ),
        );
        if (open == true) await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position? position;
        try {
          position = await Geolocator.getCurrentPosition();
        } catch (_) {}
        await _finish(position);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Location access was not granted.',
                'لم يتم منح إذن الوصول إلى الموقع.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(
      child: LayoutBuilder(
        builder:
            (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 210,
                      height: 210,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFFDF8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.sports_soccer_rounded,
                        size: 112,
                        color: AppColors.purple,
                      ),
                    ),
                    const SizedBox(height: 34),
                    Container(
                      width: 112,
                      height: 112,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFFDF8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on, size: 58),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      tr(
                        'Allow Location\nAccess',
                        'السماح بالوصول\nإلى الموقع',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.purple,
                        fontSize: 38,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      tr(
                        'By allowing access to your location, we can show you nearby arenas and provide a more accurate and convenient experience.',
                        'عند السماح بالوصول إلى موقعك، يمكننا عرض الملاعب القريبة وتقديم تجربة أدق وأسهل.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.hint,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 42),
                    FilledButton(
                      onPressed: _loading ? null : _allow,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: AppColors.arenaBlack,
                      ),
                      child:
                          _loading
                              ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFFFFDF8),
                                ),
                              )
                              : Text(tr('ALLOW NOW', 'السماح الآن')),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _finish,
                      child: Text(tr('DISMISS', 'تخطي')),
                    ),
                  ],
                ),
              ),
            ),
      ),
    ),
  );
}
