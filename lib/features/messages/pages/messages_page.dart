import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _green = Color(0xFF000000);

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});
  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  late Future<List<_Conversation>> _loader;
  @override
  void initState() {
    super.initState();
    _loader = _load();
  }

  Future<List<_Conversation>> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows =
        await Supabase.instance.client
                .from('direct_messages')
                .select()
                .or('sender_id.eq.$userId,receiver_id.eq.$userId')
                .order('created_at', ascending: false)
            as List<dynamic>;
    final latest = <String, Map<String, dynamic>>{};
    final unread = <String, int>{};
    for (final value in rows.cast<Map<String, dynamic>>()) {
      final other =
          value['sender_id'] == userId
              ? value['receiver_id'] as String
              : value['sender_id'] as String;
      latest.putIfAbsent(other, () => value);
      if (value['receiver_id'] == userId && value['read_at'] == null) {
        unread[other] = (unread[other] ?? 0) + 1;
      }
    }
    if (latest.isEmpty) return [];
    final profiles =
        await Supabase.instance.client
                .from('profiles')
                .select('id, username, display_name')
                .inFilter('id', latest.keys.toList())
            as List<dynamic>;
    final names = {
      for (final p in profiles.cast<Map<String, dynamic>>())
        p['id'] as String:
            p['display_name'] as String? ??
            p['username'] as String? ??
            'Player',
    };
    return latest.entries.map((e) {
      final message = e.value;
      return _Conversation(
        id: e.key,
        name: names[e.key] ?? 'Player',
        message:
            message['image_url'] != null
                ? 'Photo'
                : message['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(message['created_at'] as String? ?? '') ??
            DateTime.now(),
        unread: unread[e.key] ?? 0,
      );
    }).toList();
  }

  void _refresh() => setState(() => _loader = _load());
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFFDF8),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Messages', 'الرسائل'),
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0D2946),
                    ),
                  ),
                ),
                IconButton.outlined(
                  onPressed: _showPeople,
                  icon: const Icon(Icons.edit_square),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: TextField(
              readOnly: true,
              onTap: _showPeople,
              decoration: InputDecoration(
                hintText: tr('Search conversations', 'ابحث في المحادثات'),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: const Color(0xFFFFFDF8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0x33000000)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0x33000000)),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_Conversation>>(
              future: _loader,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) return _ErrorState(onRetry: _refresh);
                final items = snapshot.data ?? [];
                if (items.isEmpty) return const _EmptyState();
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder:
                        (_, i) => _ConversationCard(
                          conversation: items[i],
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => _ChatPage(conversation: items[i]),
                              ),
                            );
                            _refresh();
                          },
                        ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> _showPeople() async {
    final selected = await showSearch<_Person?>(
      context: context,
      delegate: _PeopleSearch(),
    );
    if (selected != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => _ChatPage(
                conversation: _Conversation(
                  id: selected.id,
                  name: selected.name,
                  message: '',
                  createdAt: DateTime.now(),
                ),
              ),
        ),
      );
      _refresh();
    }
  }
}

class _ChatPage extends StatefulWidget {
  const _ChatPage({required this.conversation});
  final _Conversation conversation;
  @override
  State<_ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<_ChatPage> {
  final _text = TextEditingController();
  late Future<List<Map<String, dynamic>>> _loader;
  bool _uploadingImage = false;
  @override
  void initState() {
    super.initState();
    _loader = _load();
    _markRead();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final me = Supabase.instance.client.auth.currentUser!.id;
    final rows =
        await Supabase.instance.client
                .from('direct_messages')
                .select()
                .or(
                  'and(sender_id.eq.$me,receiver_id.eq.${widget.conversation.id}),and(sender_id.eq.${widget.conversation.id},receiver_id.eq.$me)',
                )
                .order('created_at')
            as List<dynamic>;
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> _markRead() async {
    final me = Supabase.instance.client.auth.currentUser!.id;
    await Supabase.instance.client
        .from('direct_messages')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('sender_id', widget.conversation.id)
        .eq('receiver_id', me)
        .isFilter('read_at', null);
  }

  Future<void> _send({String? imageUrl}) async {
    final message = _text.text.trim();
    if (message.isEmpty && imageUrl == null) return;
    final me = Supabase.instance.client.auth.currentUser!.id;
    await Supabase.instance.client.from('direct_messages').insert({
      'sender_id': me,
      'receiver_id': widget.conversation.id,
      'content': message,
      'image_url': imageUrl,
    });
    _text.clear();
    setState(() => _loader = _load());
  }

  Future<void> _actions() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_outlined),
                  title: Text(tr('Send friend request', 'إرسال طلب صداقة')),
                  onTap: () => Navigator.pop(context, 'friend'),
                ),
                ListTile(
                  leading: const Icon(Icons.volume_off_outlined),
                  title: Text(tr('Mute conversation', 'كتم المحادثة')),
                  onTap: () => Navigator.pop(context, 'mute'),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.block_outlined,
                    color: Color(0xFF000000),
                  ),
                  title: Text(
                    tr('Block user', 'حظر المستخدم'),
                    style: const TextStyle(color: Color(0xFF000000)),
                  ),
                  onTap: () => Navigator.pop(context, 'block'),
                ),
              ],
            ),
          ),
    );
    if (value == 'friend') {
      await Supabase.instance.client.from('friend_requests').upsert({
        'sender_id': Supabase.instance.client.auth.currentUser!.id,
        'receiver_id': widget.conversation.id,
        'status': 'pending',
      });
    }
    if (value == 'block') {
      await Supabase.instance.client.from('user_blocks').upsert({
        'blocker_id': Supabase.instance.client.auth.currentUser!.id,
        'blocked_id': widget.conversation.id,
      });
      if (mounted) {
        Navigator.pop(context);
      }
    }
    if (mounted && value != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value == 'friend'
                ? 'Friend request sent'
                : value == 'mute'
                ? 'Conversation muted'
                : 'User blocked',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Supabase.instance.client.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.conversation.name),
        actions: [
          IconButton(
            onPressed: _actions,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _loader,
              builder: (_, snapshot) {
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      tr(
                        'Start your private conversation.',
                        'ابدأ محادثتك الخاصة.',
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final row = rows[i];
                    final mine = row['sender_id'] == me;
                    final image = row['image_url'] as String?;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 9),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 300),
                        decoration: BoxDecoration(
                          color: mine ? _green : const Color(0xFFFFFDF8),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child:
                            image != null
                                ? Image.network(image)
                                : Text(
                                  row['content'] as String? ?? '',
                                  style: TextStyle(
                                    color:
                                        mine
                                            ? const Color(0xFFFFFDF8)
                                            : Colors.black,
                                  ),
                                ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _uploadingImage ? null : _pickAndSendImage,
                    icon:
                        _uploadingImage
                            ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.add_photo_alternate_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: tr('Message', 'رسالة'),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _send,
                    color: _green,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndSendImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingImage = true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser!.id;
      final extension = picked.name.split('.').last.toLowerCase();
      final safeExtension =
          {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)
              ? extension
              : 'jpg';
      final path =
          '$userId/${DateTime.now().microsecondsSinceEpoch}.$safeExtension';
      await client.storage
          .from('chat-images')
          .uploadBinary(
            path,
            await picked.readAsBytes(),
            fileOptions: FileOptions(
              contentType: picked.mimeType ?? 'image/$safeExtension',
              upsert: false,
            ),
          );
      await _send(
        imageUrl: client.storage.from('chat-images').getPublicUrl(path),
      );
    } on StorageException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.conversation, required this.onTap});
  final _Conversation conversation;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFFDF8),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x33000000)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: _green.withValues(alpha: .16),
              child: Text(
                conversation.name.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    conversation.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0x99000000),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _time(conversation.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0x99000000),
                  ),
                ),
                const SizedBox(height: 14),
                if (conversation.unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: const BoxDecoration(
                      color: _green,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${conversation.unread}',
                      style: const TextStyle(
                        color: Color(0xFFFFFDF8),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.fromLTRB(32, 80, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/ui/messages-empty.png',
            height: 240,
            fit: BoxFit.contain,
          ),
          SizedBox(height: 38),
          Text(
            'No conversations',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            'Your conversations will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0x99000000)),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: onRetry,
      child: Text(
        tr(
          'Could not load messages. Try again.',
          'تعذر تحميل الرسائل. حاول مرة أخرى.',
        ),
      ),
    ),
  );
}

class _PeopleSearch extends SearchDelegate<_Person?> {
  @override
  String get searchFieldLabel => 'Search players';
  Future<List<_Person>> _find() async {
    final current = Supabase.instance.client.auth.currentUser?.id;
    final rows =
        await Supabase.instance.client
                .from('profiles')
                .select('id, username, display_name')
                .or('username.ilike.%$query%,display_name.ilike.%$query%')
                .limit(20)
            as List<dynamic>;
    return rows
        .cast<Map<String, dynamic>>()
        .where((p) => p['id'] != current)
        .map(
          (p) => _Person(
            p['id'] as String,
            p['display_name'] as String? ??
                p['username'] as String? ??
                'Player',
            p['username'] as String? ?? '',
          ),
        )
        .toList();
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(onPressed: () => query = '', icon: const Icon(Icons.close)),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );
  @override
  Widget buildResults(BuildContext context) =>
      _PeopleResults(future: _find(), onTap: (p) => close(context, p));
  @override
  Widget buildSuggestions(BuildContext context) =>
      _PeopleResults(future: _find(), onTap: (p) => close(context, p));
}

class _PeopleResults extends StatelessWidget {
  const _PeopleResults({required this.future, required this.onTap});
  final Future<List<_Person>> future;
  final ValueChanged<_Person> onTap;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<_Person>>(
    future: future,
    builder:
        (_, s) =>
            !s.hasData
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                  children:
                      s.data!
                          .map(
                            (p) => ListTile(
                              leading: CircleAvatar(
                                child: Text(p.name.substring(0, 1)),
                              ),
                              title: Text(p.name),
                              subtitle:
                                  p.username.isEmpty
                                      ? null
                                      : Text('@${p.username}'),
                              onTap: () => onTap(p),
                            ),
                          )
                          .toList(),
                ),
  );
}

class _Conversation {
  _Conversation({
    required this.id,
    required this.name,
    required this.message,
    required this.createdAt,
    this.unread = 0,
  });
  final String id, name, message;
  final DateTime createdAt;
  final int unread;
}

class _Person {
  _Person(this.id, this.name, [this.username = '']);
  final String id, name, username;
}

String _time(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final period = time.hour >= 12 ? tr('PM', 'م') : tr('AM', 'ص');
  return '$hour:${time.minute.toString().padLeft(2, '0')} $period';
}
