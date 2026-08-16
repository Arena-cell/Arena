import 'package:flutter/material.dart';
import '../../core/localization/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();

  final passwordController = TextEditingController();

  bool loading = false;

  Future login() async {
    setState(() {
      loading = true;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: emailController.text,

        password: passwordController.text,
      );
      debugPrint(Supabase.instance.client.auth.currentUser.toString());

      if (!mounted) return;

      Navigator.pop(context);
    } catch (e) {
      debugPrint(e.toString());
    }

    setState(() {
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Login', 'تسجيل الدخول'))),

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [
            TextField(
              controller: emailController,

              decoration: const InputDecoration(labelText: 'Email'),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: passwordController,

              obscureText: true,

              decoration: const InputDecoration(labelText: 'Password'),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: loading ? null : login,

                child: Text(
                  loading
                      ? tr('Loading...', 'جارٍ التحميل...')
                      : tr('Login', 'تسجيل الدخول'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
