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

  static const List<Widget> _pages = <Widget>[
    HomePage(),
    GamesPage(),
    ExplorePage(),
    MessagesPage(),
    ProfilePage(),
  ];

  void _selectPage(int index) {
    if (index == _selectedIndex) {
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
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
        body: IndexedStack(index: _selectedIndex, children: _pages),
        bottomNavigationBar: _PlayOnBottomNavigationBar(
          currentIndex: _selectedIndex,
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
    required this.items,
    required this.onSelected,
  });

  final int currentIndex;
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List<Widget>.generate(items.length, (int index) {
                return Expanded(
                  child: _NavigationTab(
                    item: items[index],
                    selected: currentIndex == index,
                    onTap: () {
                      onSelected(index);
                    },
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationTab extends StatelessWidget {
  const _NavigationTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: 46,
              constraints: BoxConstraints(
                minWidth: selected ? 80 : 42,
                maxWidth: selected ? 104 : 48,
              ),
              padding: EdgeInsets.symmetric(horizontal: selected ? 10 : 8),
              decoration: BoxDecoration(
                color:
                    selected
                        ? _PlayOnBottomNavigationBar._activeColor
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 21,
                    color:
                        selected
                            ? AppColors.warmWhite
                            : _PlayOnBottomNavigationBar._inactiveColor,
                  ),
                  if (selected) ...<Widget>[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                          color: AppColors.courtMist,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.15,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
