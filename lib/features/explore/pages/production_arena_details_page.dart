import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/localization/app_localizations.dart';

import '../../../core/services/production_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/omr_currency.dart';
import '../../bookings/pages/booking_page.dart';

class ProductionArenaDetailsPage extends StatelessWidget {
  const ProductionArenaDetailsPage({super.key, required this.arenaId});
  final String arenaId;
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: ProductionRepository.arenaById(arenaId),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError || snapshot.data == null) {
        return Scaffold(
          body: Center(
            child: Text(
              tr(
                'This stadium is no longer available.',
                'هذا الملعب لم يعد متاحًا.',
              ),
            ),
          ),
        );
      }
      return _ArenaDetails(arena: snapshot.data as Map<String, dynamic>);
    },
  );
}

class _ArenaDetails extends StatefulWidget {
  const _ArenaDetails({required this.arena});
  final Map<String, dynamic> arena;
  @override
  State<_ArenaDetails> createState() => _ArenaDetailsState();
}

class _ArenaDetailsState extends State<_ArenaDetails> {
  int page = 0;
  final PageController _pageController = PageController();
  Timer? _carouselTimer;

  List<String> get _images =>
      (widget.arena['image_urls'] as List?)
          ?.whereType<String>()
          .where((image) => image.trim().isNotEmpty)
          .toList() ??
      const <String>[];

  @override
  void initState() {
    super.initState();
    _scheduleCarousel();
  }

  void _scheduleCarousel() {
    _carouselTimer?.cancel();
    if (_images.length <= 1) return;
    _carouselTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_pageController.hasClients) return;
      _goTo((page + 1) % _images.length);
    });
  }

  void _goTo(int target) {
    if (_images.length <= 1 || !_pageController.hasClients) return;
    _carouselTimer?.cancel();
    _pageController.animateToPage(
      (target + _images.length) % _images.length,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arena = widget.arena;
    final images = _images;
    final price = arena['price_per_hour'] as num? ?? 0;
    final id = arena['id'] as String?;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 330,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      PageView.builder(
                        controller: _pageController,
                        itemCount: images.isEmpty ? 1 : images.length,
                        onPageChanged: (v) {
                          setState(() => page = v);
                          _scheduleCarousel();
                        },
                        itemBuilder:
                            (_, i) =>
                                images.isEmpty
                                    ? const _ImagePlaceholder()
                                    : _ArenaImage(images[i]),
                      ),
                      if (images.length > 1) ...[
                        PositionedDirectional(
                          start: 14,
                          top: 140,
                          child: _CarouselArrow(
                            icon: Icons.chevron_left_rounded,
                            onTap: () => _goTo(page - 1),
                          ),
                        ),
                        PositionedDirectional(
                          end: 14,
                          top: 140,
                          child: _CarouselArrow(
                            icon: Icons.chevron_right_rounded,
                            onTap: () => _goTo(page + 1),
                          ),
                        ),
                      ],
                      if (images.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              images.length,
                              (i) => Container(
                                width: 9,
                                height: 9,
                                margin: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color:
                                      i == page
                                          ? AppColors.navy
                                          : const Color(0x99000000),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -24),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(28, 34, 28, 130),
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizedData(
                            arena,
                            'name',
                            englishFallback: 'Arena',
                            arabicFallback: 'ملعب',
                          ),
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 34),
                        OmrPrice(
                          value: price,
                          suffix: tr('/ hour', '/ ساعة'),
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          localizedData(
                            arena,
                            'location',
                            englishFallback: 'Location unavailable',
                            arabicFallback: 'الموقع غير متاح',
                          ),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          localizedData(
                            arena,
                            'description',
                            englishFallback:
                                'No description has been provided.',
                            arabicFallback: 'لم تتم إضافة وصف.',
                          ),
                          style: const TextStyle(
                            color: AppColors.tealText,
                            fontSize: 18,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _GoogleMapsLink(arena: arena),
                        if (id != null) ...[
                          const SizedBox(height: 30),
                          _ReviewsSection(arenaId: id),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CircleAction(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                  if (id != null) _FavoriteButton(arenaId: id),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 10, 28, 20),
                child: Row(
                  children: [
                    if (id != null)
                      SizedBox(
                        width: 70,
                        height: 58,
                        child: _FavoriteButton(arenaId: id),
                      ),
                    if (id != null) const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: AppColors.arenaBlack,
                        ),
                        onPressed:
                            id == null
                                ? null
                                : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BookingPage(arenaId: id),
                                  ),
                                ),
                        child: Text(tr('Book', 'احجز')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleMapsLink extends StatelessWidget {
  const _GoogleMapsLink({required this.arena});
  final Map<String, dynamic> arena;

  Uri? get _uri {
    final saved = '${arena['google_maps_url'] ?? ''}'.trim();
    final direct = Uri.tryParse(saved);
    if (direct != null &&
        (direct.scheme == 'https' || direct.scheme == 'http')) {
      return direct;
    }
    final latitude = arena['latitude'] as num?;
    final longitude = arena['longitude'] as num?;
    if (latitude != null && longitude != null) {
      return Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '${latitude.toDouble()},${longitude.toDouble()}',
      });
    }
    final location = '${arena['location'] ?? ''}'.trim();
    if (location.isEmpty) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': location,
    });
  }

  @override
  Widget build(BuildContext context) {
    final uri = _uri;
    return OutlinedButton.icon(
      onPressed:
          uri == null
              ? null
              : () async {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
      icon: const Icon(Icons.map_outlined),
      label: Text(
        tr('Open location in Google Maps', 'فتح الموقع في خرائط Google'),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        alignment: AlignmentDirectional.centerStart,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _ArenaImage extends StatelessWidget {
  const _ArenaImage(this.source);
  final String source;
  @override
  Widget build(BuildContext context) {
    final network =
        source.startsWith('http://') || source.startsWith('https://');
    return network
        ? Image.network(
          source,
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, _, _) => const _ImagePlaceholder(),
        )
        : Image.asset(
          source,
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, _, _) => const _ImagePlaceholder(),
        );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFFFFDF8),
    child: Center(
      child: Image.asset(
        'assets/images/arena_primary_emblem.png',
        width: 96,
        height: 96,
        fit: BoxFit.contain,
        errorBuilder:
            (_, _, _) => const Icon(
              Icons.stadium_outlined,
              size: 72,
              color: AppColors.purple,
            ),
      ),
    ),
  );
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFFDF8),
    shape: const CircleBorder(),
    child: IconButton(onPressed: onTap, icon: Icon(icon)),
  );
}

class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .88),
    shape: const CircleBorder(),
    elevation: 2,
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: AppColors.navy),
    ),
  );
}

class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({required this.arenaId});
  final String arenaId;
  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool? favorite;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await ProductionRepository.isFavorite(widget.arenaId);
    if (mounted) setState(() => favorite = v);
  }

  Future<void> _toggle() async {
    final old = favorite;
    if (old == null) return;
    setState(() => favorite = !old);
    try {
      await ProductionRepository.setFavorite(widget.arenaId, !old);
    } catch (_) {
      if (mounted) setState(() => favorite = old);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFFDF8),
    borderRadius: BorderRadius.circular(14),
    child: IconButton(
      onPressed: favorite == null ? null : _toggle,
      icon: Icon(favorite == true ? Icons.favorite : Icons.favorite_border),
    ),
  );
}

class _ReviewsSection extends StatefulWidget {
  const _ReviewsSection({required this.arenaId});
  final String arenaId;

  @override
  State<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<_ReviewsSection> {
  late Future<_ReviewData> _loader = _load();

  Future<_ReviewData> _load() async {
    final client = ProductionRepository.client;
    final reviewRows = await client
        .from('reviews')
        .select('id,booking_id,rating,comment,created_at,user_id')
        .eq('arena_id', widget.arenaId)
        .order('created_at', ascending: false);
    final reviews = List<Map<String, dynamic>>.from(reviewRows);
    final reviewerIds =
        reviews.map((row) => row['user_id'] as String?).whereType<String>().toSet().toList();
    if (reviewerIds.isNotEmpty) {
      final profileRows = await client
          .from('profiles')
          .select('id,first_name,display_name,avatar_url')
          .inFilter('id', reviewerIds);
      final profiles = {
        for (final profile in List<Map<String, dynamic>>.from(profileRows))
          profile['id'] as String: profile,
      };
      for (final review in reviews) {
        review['profiles'] = profiles[review['user_id']] ?? const <String, dynamic>{};
      }
    }
    final userId = client.auth.currentUser?.id;
    String? eligibleBookingId;
    if (userId != null) {
      try {
        await client.rpc('finalize_my_completed_events');
        final bookingRows = await client
            .from('bookings')
            .select('id')
            .eq('arena_id', widget.arenaId)
            .eq('user_id', userId)
            .eq('status', 'previous')
            .lte('ends_at', DateTime.now().toUtc().toIso8601String())
            .order('ends_at', ascending: false);
        final reviewedBookingIds = reviews
            .map((review) => review['booking_id'] as String?)
            .whereType<String>()
            .toSet();
        for (final booking in List<Map<String, dynamic>>.from(bookingRows)) {
          final bookingId = booking['id'] as String?;
          if (bookingId != null && !reviewedBookingIds.contains(bookingId)) {
            eligibleBookingId = bookingId;
            break;
          }
        }
      } on PostgrestException {
        eligibleBookingId = null;
      }
    }
    return _ReviewData(
      reviews: reviews,
      eligibleBookingId: eligibleBookingId,
    );
  }

  Future<void> _addReview(String bookingId) async {
    var rating = 5;
    final comment = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Text(tr('Rate this arena', 'قيّم هذا الملعب')),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          5,
                          (index) => IconButton(
                            onPressed: () => setDialogState(() => rating = index + 1),
                            icon: Icon(
                              index < rating ? Icons.star_rounded : Icons.star_border_rounded,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                      ),
                      TextField(
                        controller: comment,
                        maxLength: 1000,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: tr('Write your experience (optional)', 'اكتب تجربتك (اختياري)'),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(tr('Cancel', 'إلغاء')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(tr('Submit', 'إرسال')),
                    ),
                  ],
                ),
          ),
    );
    if (accepted != true) {
      comment.dispose();
      return;
    }
    try {
      await ProductionRepository.client.rpc(
        'create_booking_review',
        params: {
          'p_booking_id': bookingId,
          'p_rating': rating,
          'p_comment': comment.text.trim(),
        },
      );
      if (mounted) setState(() => _loader = _load());
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      comment.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_ReviewData>(
    future: _loader,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data ?? const _ReviewData();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Player reviews', 'تقييمات اللاعبين'),
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
              ),
              if (data.eligibleBookingId != null)
                TextButton.icon(
                  onPressed:
                      () => _addReview(data.eligibleBookingId as String),
                  icon: const Icon(Icons.star_outline_rounded),
                  label: Text(tr('Rate', 'قيّم')),
                ),
            ],
          ),
          if (data.reviews.isEmpty)
            Text(tr('No reviews yet.', 'لا توجد تقييمات حتى الآن.'))
          else
            ...data.reviews.map((review) {
              final profile = review['profiles'] as Map<String, dynamic>? ?? const {};
              final firstName = '${profile['first_name'] ?? profile['display_name'] ?? tr('Player', 'لاعب')}'
                  .trim()
                  .split(RegExp(r'\s+'))
                  .first;
              final avatar = profile['avatar_url'] as String?;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundImage: avatar == null ? null : NetworkImage(avatar),
                  child: avatar == null ? const Icon(Icons.person_outline) : null,
                ),
                title: Text(firstName),
                subtitle: Text('${review['comment'] ?? ''}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: AppColors.navy, size: 18),
                    Text('${review['rating']}'),
                  ],
                ),
              );
            }),
        ],
      );
    },
  );
}

class _ReviewData {
  const _ReviewData({this.reviews = const [], this.eligibleBookingId});
  final List<Map<String, dynamic>> reviews;
  final String? eligibleBookingId;
}
