import 'dart:async';

import 'package:flutter/material.dart';
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
      return _ArenaDetails(arena: snapshot.data!);
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
    if (_images.length > 1) {
      _carouselTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!mounted || !_pageController.hasClients) {
          return;
        }
        final nextPage = (page + 1) % _images.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        );
      });
    }
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
                        onPageChanged: (v) => setState(() => page = v),
                        itemBuilder:
                            (_, i) =>
                                images.isEmpty
                                    ? const _ImagePlaceholder()
                                    : _ArenaImage(images[i]),
                      ),
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
