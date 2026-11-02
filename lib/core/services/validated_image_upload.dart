import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../localization/app_localizations.dart';

class ImageUploadFailure implements Exception {
  const ImageUploadFailure(this.code);
  final String code;
  @override
  String toString() => switch (code) {
    'IMAGE_TOO_LARGE' => tr(
      'Image exceeds the size limit (avatar 3MB, chat 5MB, arena 10MB).',
      'الصورة تتجاوز الحد المسموح: الشخصية 3MB، المحادثة 5MB، الملعب 10MB.',
    ),
    'INVALID_IMAGE' ||
    'IMAGE_TYPE_NOT_ALLOWED' ||
    'IMAGE_DIMENSIONS_EXCEEDED' => tr(
      'Choose a valid JPEG, PNG or WebP image with supported dimensions.',
      'اختر صورة JPEG أو PNG أو WebP صالحة وبأبعاد مناسبة.',
    ),
    'IMAGE_UPLOAD_NOT_AUTHORIZED' => tr(
      'You are not allowed to upload this image.',
      'ليس لديك صلاحية رفع هذه الصورة.',
    ),
    _ => tr(
      'Secure image upload is unavailable. Please try again later.',
      'رفع الصور الآمن غير متاح. أعد المحاولة لاحقًا.',
    ),
  };
}

Future<Map<String, dynamic>> uploadValidatedImage({
  required Uint8List bytes,
  required String bucket,
  String? arenaId,
}) async {
  const limits = {
    'avatars': 3 * 1024 * 1024,
    'chat-images': 5 * 1024 * 1024,
    'stadium-images': 10 * 1024 * 1024,
  };
  final limit = limits[bucket];
  if (limit == null) throw const ImageUploadFailure('INVALID_BUCKET');
  if (bytes.length > limit) throw const ImageUploadFailure('IMAGE_TOO_LARGE');
  try {
    final response = await Supabase.instance.client.functions.invoke(
      'image-upload',
      body: bytes,
      headers: {
        'Content-Type': 'application/octet-stream',
        'x-arena-image-bucket': bucket,
        if (arenaId != null) 'x-arena-id': arenaId,
      },
    );
    final data = response.data;
    if (data is! Map || data['path'] is! String) {
      throw const ImageUploadFailure('INVALID_RESPONSE');
    }
    return Map<String, dynamic>.from(data);
  } on FunctionException catch (error) {
    final details = error.details;
    throw ImageUploadFailure(
      details is Map
          ? details['error']?.toString() ?? 'UNAVAILABLE'
          : 'UNAVAILABLE',
    );
  }
}
