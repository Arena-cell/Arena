/// Converts stored object references and legacy public URLs without fetching
/// the public URL. Access still requires the storage policy on the server.
String? chatImageObjectPath(String reference) {
  const marker = '/storage/v1/object/public/chat-images/';
  String path;
  if (reference.startsWith('chat-images/')) {
    path = reference.substring('chat-images/'.length);
  } else {
    final uri = Uri.tryParse(reference);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'gtcrijikfaglqcwqozel.supabase.co' ||
        !uri.path.startsWith(marker) ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    path = Uri.decodeComponent(uri.path.substring(marker.length));
  }
  if (path.isEmpty ||
      path.contains('\\') ||
      path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    return null;
  }
  return path;
}
