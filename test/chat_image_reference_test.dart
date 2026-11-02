import 'package:flutter_test/flutter_test.dart';
import 'package:playon/core/services/chat_image_reference.dart';

void main() {
  test('new reference stays an object path', () {
    expect(chatImageObjectPath('chat-images/user/image.jpg'), 'user/image.jpg');
  });
  test('legacy URL becomes an authenticated storage request', () {
    expect(
      chatImageObjectPath(
        'https://gtcrijikfaglqcwqozel.supabase.co/storage/v1/object/public/chat-images/user/image.jpg',
      ),
      'user/image.jpg',
    );
  });
  for (final ref in [
    'https://evil.test/storage/v1/object/public/chat-images/user/x.jpg',
    'chat-images/../x',
    'chat-images/user//x',
    'chat-images/',
    'https://gtcrijikfaglqcwqozel.supabase.co/storage/v1/object/public/chat-images/user/x.jpg?token=bad',
  ]) {
    test(
      'rejects unsupported reference $ref',
      () => expect(chatImageObjectPath(ref), isNull),
    );
  }
}
