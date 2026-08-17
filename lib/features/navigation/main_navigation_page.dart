import 'dart:ui';

import 'package:flutter/material.dart';

import '../../main.dart';
import '../explore/pages/explore_page.dart';
import '../games/pages/games_page.dart';
import '../home/pages/home_page.dart';
import '../messages/pages/messages_page.dart';
import '../profile/pages/profile_page.dart';
import '../../core/theme/app_colors.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  static const int _gamesIndex = 1;
  int _selectedIndex = _gamesIndex;
  late final PageController _pageController;

  static const List<Widget> _pages = <Widget>[
    HomePage(),
    GamesPage(),
    ExplorePage(),
    MessagesPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    if (index == _selectedIndex) {
      return;
    }

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isArabic = appLanguage.value == 'ar';

    final List<_NavigationItem> items = <_NavigationItem>[
      _NavigationItem(
        label: isArabic ? 'الرئيسية' : 'Home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
      ),
      _NavigationItem(
        label: isArabic ? 'المباريات' : 'Games',
        icon: Icons.sports_soccer_outlined,
        selectedIcon: Icons.sports_soccer_rounded,
      ),
      _NavigationItem(
        label: isArabic ? 'استكشف' : 'Explore',
        icon: Icons.search_rounded,
        selectedIcon: Icons.search_rounded,
      ),
      _NavigationItem(
        label: isArabic ? 'الرسائل' : 'Messages',
        icon: Icons.chat_bubble_outline_rounded,
        selectedIcon: Icons.chat_bubble_rounded,
      ),
      _NavigationItem(
        label: isArabic ? 'الإعدادات' : 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
      ),
    ];

    return PopScope<Object?>(
      canPop: _selectedIndex == _gamesIndex,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _selectedIndex != _gamesIndex) {
          _selectPage(_gamesIndex);
        }
      },
      child: Scaffold(
        extendBody: true,
        body: PageView(
          controller: _pageController,
          allowImplicitScrolling: true,
          onPageChanged: (index) {
            if (_selectedIndex != index) {
              setState(() => _selectedIndex = index);
            }
          },
          children: _pages,
        ),
        bottomNavigationBar: _PlayOnBottomNavigationBar(
          currentIndex: _selectedIndex,
          pageController: _pageController,
          items: items,
          onSelected: _selectPage,
        ),
      ),
    );
  }
}

class _PlayOnBottomNavigationBar extends StatelessWidget {
  const _PlayOnBottomNavigationBar({
    required this.currentIndex,
    required this.pageController,
    required this.items,
    required this.onSelected,
  });

  final int currentIndex;
  final PageController pageController;
  final List<_NavigationItem> items;
  final ValueChanged<int> onSelected;

  static const Color _activeColor = AppColors.navy;
  static const Color _inactiveColor = Color(0x99000000);
  static const Color _barColor = AppColors.courtMist;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
            decoration: BoxDecoration(
              color: _barColor.withValues(alpha: .76),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withValues(alpha: .7)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x1F0D2946),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final segmentWidth = constraints.maxWidth / items.length;
                final activeWidth =
                    (segmentWidth + 34).clamp(82.0, 108.0).toDouble();
                final arabic = Directionality.of(context) == TextDirection.rtl;
                return AnimatedBuilder(
                  animation: pageController,
                  builder: (context, _) {
                    final logicalPage =
                        pageController.hasClients
                            ? (pageController.page ?? currentIndex.toDouble())
                            : currentIndex.toDouble();
                    final physicalPage =
                        arabic ? items.length - 1 - logicalPage : logicalPage;
                    final left =
                        physicalPage * segmentWidth +
                        (segmentWidth - activeWidth) / 2;
                    final labelIndex =
                        logicalPage.round().clamp(0, items.length - 1).toInt();
                    return Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        Row(
                          children: List<Widget>.generate(items.length, (
                            index,
                          ) {
                            return Expanded(
                              child: _NavigationIconButton(
                                item: items[index],
                                hidden: currentIndex == index,
                                onTap: () => onSelected(index),
                              ),
                            );
                          }),
                        ),
                        Positioned(
                          left: left,
                          top: 3,
                          width: activeWidth,
                          height: 46,
                          child: _ActiveNavigationPill(
                            item: items[labelIndex],
                            onTap: () => onSelected(labelIndex),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationIconButton extends StatelessWidget {
  const _NavigationIconButton({
    required this.item,
    required this.hidden,
    required this.onTap,
  });

  final _NavigationItem item;
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: item.label,
      child: IconButton(
        onPressed: onTap,
        icon: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: hidden ? 0 : 1,
          child: Icon(
            item.icon,
            size: 21,
            color: _PlayOnBottomNavigationBar._inactiveColor,
          ),
        ),
      ),
    );
  }
}

class _ActiveNavigationPill extends StatelessWidget {
  const _ActiveNavigationPill({required this.item, required this.onTap});

  final _NavigationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: _PlayOnBottomNavigationBar._activeColor,
    borderRadius: BorderRadius.circular(25),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(25),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.selectedIcon, size: 21, color: AppColors.warmWhite),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.courtMist,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NavigationItem {
  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
