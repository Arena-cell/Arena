import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/services/chat_image_reference.dart';

class PrivateChatImage extends StatefulWidget {
  const PrivateChatImage({super.key, required this.reference});
  final String reference;
  @override
  State<PrivateChatImage> createState() => _PrivateChatImageState();
}

class _PrivateChatImageState extends State<PrivateChatImage> {
  late Future<String> _url;
  Future<String> _resolve() async {
    final path = chatImageObjectPath(widget.reference);
    if (path == null) throw const FormatException('Invalid image reference');
    return Supabase.instance.client.storage
        .from('chat-images')
        .createSignedUrl(path, 60);
  }

  @override
  void initState() {
    super.initState();
    _url = _resolve();
  }

  @override
  void didUpdateWidget(covariant PrivateChatImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reference != oldWidget.reference) _url = _resolve();
  }

  Widget _retry() => SizedBox(
    width: 190,
    height: 130,
    child: TextButton.icon(
      onPressed: () => setState(() => _url = _resolve()),
      icon: const Icon(Icons.refresh),
      label: Text(
        tr('Image unavailable. Retry', 'الصورة غير متاحة. أعد المحاولة'),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, snapshot) {
      if (snapshot.hasError) return _retry();
      if (!snapshot.hasData) {
        return const SizedBox(
          width: 190,
          height: 130,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Image.network(
        snapshot.data!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _retry(),
      );
    },
  );
}
