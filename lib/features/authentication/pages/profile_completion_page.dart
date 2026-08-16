import 'package:flutter/material.dart';

import '../../onboarding/location_permission_page.dart';

/// Compatibility entry point used by the existing authentication flow.
class ProfileCompletionPage extends StatelessWidget {
  const ProfileCompletionPage({super.key});

  @override
  Widget build(BuildContext context) => const LocationPermissionPage();
}
