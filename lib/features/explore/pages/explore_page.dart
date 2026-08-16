import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';

import '../../../core/services/production_repository.dart';
import '../../../core/services/guest_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/omr_currency.dart';
import '../../games/pages/create_game_page.dart';
import 'game_filters_sheet.dart';
import 'production_arena_details_page.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _arenas;
  GameFilters _filters = const GameFilters();

  @override
  void initState() {
    super.initState();
    _loadArenas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadArenas() {
    _arenas = ProductionRepository.arenas(
      search: _searchController.text,
      sport: _filters.sport,
    );
  }

  void _reload() {
    setState(_loadArenas);
  }

  Future<void> _refresh() async {
    final future = ProductionRepository.arenas(
      search: _searchController.text,
      sport: _filters.sport,
    );
    setState(() => _arenas = future);
    await future;
  }

  Future<void> _openFilters() async {
    final selected = await showGameFilters(context, initial: _filters);
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _filters = selected;
      _loadArenas();
    });
  }

  Future<void> _openCreateGame() async {
    if (!await GuestSession.requireAccount(context, action: 'create a game')) {
      return;
    }
    if (!mounted) return;
    final sport = await _selectGameSport();
    if (!mounted || sport == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CreateGamePage(sport: sport)),
    );
    if (!mounted) {
      return;
    }
    _reload();
  }

  Future<String?> _selectGameSport() => showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFFFFFDF8),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder:
        (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Choose sport', 'اختر الرياضة'),
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sports_soccer_rounded),
                  title: Text(tr('Football', 'كرة القدم')),
                  onTap: () => Navigator.of(sheetContext).pop('football'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sports_tennis_rounded),
                  title: Text(tr('Padel', 'بادل')),
                  onTap: () => Navigator.of(sheetContext).pop('padel'),
                ),
              ],
            ),
          ),
        ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => _reload(),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: tr(
                          'Search arenas in Muscat',
                          'ابحث عن ملاعب في مسقط',
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.hint,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFFFFDF8),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: _searchBorder,
                        enabledBorder: _searchBorder,
                        focusedBorder: _searchBorder.copyWith(
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _HeaderButton(
                  icon: Icons.tune_rounded,
                  onPressed: _openFilters,
                ),
                const SizedBox(width: 6),
                _HeaderButton(
                  icon: Icons.add_rounded,
                  onPressed: _openCreateGame,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
            child: Row(
              children: [
                Text(
                  tr('Explore arenas', 'استكشف الملاعب'),
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                if (_filters.sport != null)
                  InputChip(
                    label: Text(localizedSport(_filters.sport)),
                    onDeleted: () {
                      setState(() {
                        _filters = GameFilters(
                          distanceKm: _filters.distanceKm,
                          period: _filters.period,
                          size: _filters.size,
                        );
                        _loadArenas();
                      });
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _arenas,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ArenaState(
                    icon: Icons.cloud_off_rounded,
                    title: tr('Could not load arenas', 'تعذر تحميل الملاعب'),
                    subtitle: tr(
                      'Check your connection and try again.',
                      'تحقق من اتصالك وحاول مرة أخرى.',
                    ),
                    actionLabel: tr('Try again', 'حاول مرة أخرى'),
                    onAction: _reload,
                  );
                }
                final arenas = snapshot.data ?? const [];
                if (arenas.isEmpty) {
                  return _ArenaState(
                    icon: Icons.stadium_outlined,
                    title: tr('No arenas found', 'لم يتم العثور على ملاعب'),
                    subtitle:
                        _searchController.text.trim().isEmpty
                            ? tr(
                              'No active arenas have been added yet.',
                              'لم تتم إضافة ملاعب نشطة بعد.',
                            )
                            : tr(
                              'Try another search or remove the filters.',
                              'جرّب بحثًا آخر أو أزل عوامل التصفية.',
                            ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                    itemCount: arenas.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (_, index) => _ArenaCard(arena: arenas[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  static final OutlineInputBorder _searchBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: AppColors.border),
  );
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: const Color(0xFFFFFDF8),
      foregroundColor: AppColors.primary,
      side: const BorderSide(color: AppColors.border),
      fixedSize: const Size(46, 46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    icon: Icon(icon, size: 27),
  );
}

class _ArenaCard extends StatelessWidget {
  const _ArenaCard({required this.arena});
  final Map<String, dynamic> arena;

  @override
  Widget build(BuildContext context) {
    final id = arena['id'] as String?;
    final images =
        (arena['image_urls'] as List?)
            ?.whereType<String>()
            .where((url) => url.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final sports =
        (arena['sports'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final isPadel = sports.any(
      (sport) => sport.toLowerCase() == 'padel' || sport == 'بادل',
    );
    final sportAccent = isPadel ? AppColors.navy : AppColors.brandGreenMedium;
    final surface = isPadel ? const Color(0xFFF1F6FA) : const Color(0xFFF4F8EA);
    final audience = '${arena['audience_gender'] ?? 'mixed'}'.toLowerCase();
    final price = arena['price_per_hour'] as num? ?? 0;
    final rating = arena['rating'] as num?;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: sportAccent.withValues(alpha: .35), width: 1.2),
      ),
      child: InkWell(
        onTap:
            id == null
                ? null
                : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProductionArenaDetailsPage(arenaId: id),
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 134,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child:
                            images.isEmpty
                                ? const _ArenaImagePlaceholder()
                                : Image.network(
                                  images.first,
                                  width: 134,
                                  height: 134,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, _, _) =>
                                          const _ArenaImagePlaceholder(),
                                ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: sportAccent,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Color(0x33000000), blurRadius: 8),
                          ],
                        ),
                        child: Icon(
                          isPadel
                              ? Icons.sports_tennis_rounded
                              : Icons.sports_soccer_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Text(
                              localizedData(
                                arena,
                                'name',
                                englishFallback: 'Arena',
                                arabicFallback: 'ملعب',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (rating != null) ...[
                            const Icon(
                              Icons.star_rounded,
                              size: 19,
                              color: AppColors.navy,
                            ),
                            const SizedBox(width: 3),
                            Text(rating.toStringAsFixed(1)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: AppColors.hint,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              localizedData(
                                arena,
                                'location',
                                englishFallback: 'Location unavailable',
                                arabicFallback: 'الموقع غير متاح',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.hint),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Expanded(child: _AudienceBadge(audience: audience)),
                          const SizedBox(width: 8),
                          OmrPrice(
                            value: price,
                            suffix: tr('/hour', '/ساعة'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudienceBadge extends StatelessWidget {
  const _AudienceBadge({required this.audience});
  final String audience;

  @override
  Widget build(BuildContext context) {
    final women =
        audience == 'women' || audience == 'female' || audience == 'نساء';
    final men = audience == 'men' || audience == 'male' || audience == 'رجال';
    final color =
        women
            ? const Color(0xFF9C4771)
            : men
            ? AppColors.navy
            : const Color(0xFF61706A);
    final icon =
        women
            ? Icons.female_rounded
            : men
            ? Icons.male_rounded
            : Icons.groups_2_outlined;
    final label =
        women
            ? tr('Women', 'نسائي')
            : men
            ? tr('Men', 'رجالي')
            : tr('Mixed', 'مشترك');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ArenaImagePlaceholder extends StatelessWidget {
  const _ArenaImagePlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFFFFDF8),
    child: Center(
      child: Image.asset(
        'assets/images/arena_primary_emblem.png',
        width: 82,
        height: 82,
        fit: BoxFit.contain,
        errorBuilder:
            (_, _, _) => const Icon(
              Icons.stadium_outlined,
              size: 62,
              color: AppColors.purple,
            ),
      ),
    ),
  );
}

class _ArenaState extends StatelessWidget {
  const _ArenaState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: AppColors.hint),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.hint),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
