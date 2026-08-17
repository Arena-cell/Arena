import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final username = TextEditingController();
  final bio = TextEditingController();
  final address = TextEditingController();
  XFile? pickedImage;
  String? avatarUrl;
  String? gender;
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [firstName, lastName, username, bio, address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    try {
      final profile =
          await client
              .from('profiles')
              .select('username, display_name, avatar_url, bio, city, gender')
              .eq('id', user.id)
              .maybeSingle();
      final display = (profile?['display_name'] as String? ?? '').trim().split(
        RegExp(r'\s+'),
      );
      username.text =
          profile?['username'] as String? ??
          metadata['username'] as String? ??
          '';
      firstName.text =
          metadata['first_name'] as String? ??
          (display.isEmpty ? '' : display.first);
      lastName.text =
          metadata['last_name'] as String? ??
          (display.length < 2 ? '' : display.skip(1).join(' '));
      bio.text = profile?['bio'] as String? ?? metadata['bio'] as String? ?? '';
      address.text =
          profile?['city'] as String? ?? metadata['address'] as String? ?? '';
      avatarUrl = profile?['avatar_url'] as String?;
      gender = profile?['gender'] as String? ?? metadata['gender'] as String?;
    } catch (_) {
      username.text = metadata['username'] as String? ?? '';
      firstName.text = metadata['first_name'] as String? ?? '';
      lastName.text = metadata['last_name'] as String? ?? '';
      bio.text = metadata['bio'] as String? ?? '';
      address.text = metadata['address'] as String? ?? '';
      gender = metadata['gender'] as String?;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _pick() async {
    final value = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
    );
    if (!mounted || value == null) return;
    setState(() => pickedImage = value);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || saving) return;
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    setState(() => saving = true);
    try {
      var uploadedUrl = avatarUrl;
      final selectedImage = pickedImage;
      if (selectedImage != null) {
        final extension =
            selectedImage.name.contains('.')
                ? selectedImage.name.split('.').last
                : 'jpg';
        final path = '${user.id}/avatar.$extension';
        await client.storage
            .from('avatars')
            .upload(
              path,
              File(selectedImage.path),
              fileOptions: const FileOptions(upsert: true),
            );
        uploadedUrl = client.storage.from('avatars').getPublicUrl(path);
      }
      final data = {
        'username': username.text.trim(),
        'first_name': firstName.text.trim(),
        'last_name': lastName.text.trim(),
        'bio': bio.text.trim(),
        'address': address.text.trim(),
        'gender': gender,
      };
      await client.auth.updateUser(UserAttributes(data: data));
      await client
          .from('profiles')
          .update({
            'username': username.text.trim(),
            'display_name':
                '${firstName.text.trim()} ${lastName.text.trim()}'.trim(),
            'bio': bio.text.trim(),
            'city': address.text.trim(),
            'gender': gender,
            if (uploadedUrl != null) 'avatar_url': uploadedUrl,
          })
          .eq('id', user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Profile updated successfully.', 'تم تحديث الملف الشخصي بنجاح.'),
          ),
        ),
      );
      Navigator.pop(context, true);
    } on AuthException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('Could not update your profile.', 'تعذر تحديث ملفك الشخصي.'),
            ),
          ),
        );
      }
    } on PostgrestException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('Could not update your profile.', 'تعذر تحديث ملفك الشخصي.'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('Could not update your profile.', 'تعذر تحديث ملفك الشخصي.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  ImageProvider? _profileImage() {
    final selectedImage = pickedImage;
    if (selectedImage != null) return FileImage(File(selectedImage.path));
    final remoteAvatar = avatarUrl;
    if (remoteAvatar != null && remoteAvatar.isNotEmpty) {
      return NetworkImage(remoteAvatar);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: Text(tr('Edit Profile', 'تعديل الملف الشخصي')),
      backgroundColor: AppColors.background,
    ),
    body:
        loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 14, 28, 28),
                  children: [
                    Center(
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 72,
                            backgroundColor: const Color(0xFFFFFDF8),
                            backgroundImage: _profileImage(),
                            child:
                                pickedImage == null && avatarUrl == null
                                    ? const Icon(
                                      Icons.person,
                                      size: 78,
                                      color: AppColors.purple,
                                    )
                                    : null,
                          ),
                          Material(
                            color: const Color(0x52000000),
                            shape: const CircleBorder(),
                            child: IconButton(
                              onPressed: _pick,
                              icon: const Icon(Icons.camera_alt),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    _Field(
                      label: tr('First name', 'الاسم الأول'),
                      controller: firstName,
                    ),
                    _Field(
                      label: tr('Last name', 'اسم العائلة'),
                      controller: lastName,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('Gender', 'الجنس'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'men',
                          label: Text(tr('Male', 'ذكر')),
                        ),
                        ButtonSegment(
                          value: 'women',
                          label: Text(tr('Female', 'أنثى')),
                        ),
                      ],
                      selected:
                          gender == null
                              ? const <String>{}
                              : <String>{gender as String},
                      emptySelectionAllowed: true,
                      onSelectionChanged:
                          (value) => setState(() => gender = value.firstOrNull),
                    ),
                    _Field(
                      label: tr('Username', 'اسم المستخدم'),
                      controller: username,
                      validator:
                          (v) =>
                              RegExp(
                                    r'^[a-z][a-z0-9_]{3,}$',
                                  ).hasMatch(v?.trim() ?? '')
                                  ? null
                                  : 'Use 4+ lowercase letters, numbers, or underscores.',
                    ),
                    _Field(
                      label: tr('Bio', 'نبذة'),
                      controller: bio,
                      maxLines: 3,
                    ),
                    _Field(
                      label: tr('Address', 'العنوان'),
                      controller: address,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: saving ? null : _save,
                      child:
                          saving
                              ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFFFFDF8),
                                ),
                              )
                              : Text(tr('Save', 'حفظ')),
                    ),
                  ],
                ),
              ),
            ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.validator,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final int maxLines;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(labelText: label),
    ),
  );
}
