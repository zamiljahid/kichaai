import 'dart:ui';

import 'package:flashy_tab_bar2/flashy_tab_bar2.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/app_strings.dart';

/// ki_chai's floating bottom nav: a frosted, primary-tinted pill that page
/// content scrolls behind, wrapping a [FlashyTabBar] whose selected item drops
/// its icon and slides the label up under a moving indicator.
///
/// The tab set, their order and the onTap contract are unchanged.
class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _NavItem(icon: Icons.home_rounded, label: 'হোম', labelEn: 'Home'),
    _NavItem(
        icon: Icons.grid_view_rounded, label: 'সেবা', labelEn: 'Services'),
    _NavItem(
        icon: Icons.receipt_long_rounded, label: 'অর্ডার', labelEn: 'Orders'),
    _NavItem(
        icon: Icons.chat_bubble_rounded, label: 'বার্তা', labelEn: 'Messages'),
    _NavItem(
        icon: Icons.person_rounded, label: 'প্রোফাইল', labelEn: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // labelEn was declared but never read, so the nav stayed Bengali whatever
    // the language toggle said.
    final isBn = context.watch<LanguageNotifier>().isBengali;

    return SafeArea(
      child: Container(
        height: 80,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.30),
              offset: const Offset(0, 12),
              blurRadius: 20,
            ),
          ],
        ),
        // Frosted pill: the page content scrolling underneath shows through
        // blurred, which is what makes it read as floating.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colors.onPrimary.withValues(alpha: 0.25),
                ),
              ),
              child: FlashyTabBar(
                selectedIndex: currentIndex,
                showElevation: false,
                backgroundColor: Colors.transparent,
                iconSize: 28,
                onItemSelected: onTap,
                items: [
                  for (var i = 0; i < _items.length; i++)
                    FlashyTabBarItem(
                      icon: currentIndex == i
                          ? const SizedBox()
                          : Icon(_items[i].icon),
                      title: Text(
                        isBn ? _items[i].label : _items[i].labelEn,
                        style: const TextStyle(fontSize: 14),
                      ),
                      activeColor: colors.onPrimary,
                      inactiveColor: colors.secondaryContainer,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String labelEn;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.labelEn,
  });
}
