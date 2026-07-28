import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_button.dart';
import 'auth_screen.dart';
import 'background_check_screen.dart';
import 'commission_screen.dart';
import 'course_authoring_screen.dart';
import 'lawyer_areas_screen.dart';
import 'dispute_screen.dart';
import 'nid_screen.dart';
import 'notification_preferences_screen.dart';
import 'notifications_screen.dart';
import 'my_ads_screen.dart';
import 'my_match_requests_screen.dart';
import 'payment_screen.dart';
import 'portfolio_screen.dart';
import 'provider_online_screen.dart';
import 'provider_onboarding_screen.dart';
import 'provider_pricing_screen.dart';
import 'technician_specializations_screen.dart';
import 'referral_screen.dart';
import 'subscription_screen.dart';
import 'wallet_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserModel? _user;
  List<AddressModel> _addresses = [];
  bool _isLoading = true;
  // serviceTypeIds this provider offers (e.g. st_lawyer, st_technician) — drives
  // which provider tools show, so a lawyer never sees photographer/course tools.
  Set<String> _serviceTypeIds = {};

  bool get _isProvider => _user?.role == 'provider' || _user?.role == 'PROVIDER';
  bool _offers(List<String> keys) => _serviceTypeIds.any((id) => keys.any(id.contains));

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiClient.getUserId(),
        ApiClient.getFullName(),
        ApiClient.getEmail(),
        ApiClient.getPhone(),
        ApiClient.getRole(),
        AuthService.instance.listAddresses(),
      ]);
      if (mounted) {
        final userId = results[0] as String? ?? '';
        final fullName = results[1] as String? ?? '';
        final email = results[2] as String?;
        final phone = results[3] as String?;
        final role = results[4] as String? ?? 'user';
        final addresses = results[5] as List<AddressModel>;
        setState(() {
          _user = UserModel(
            id: userId,
            fullName: fullName,
            email: email,
            phone: phone,
            role: role,
          );
          _addresses = addresses;
          _isLoading = false;
        });
        if (_isProvider) _loadProviderServices();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProviderServices() async {
    try {
      final apps = await OnboardingService.instance.getMyServices();
      final ids = apps
          .map((a) => (a['serviceTypeId'] ?? '').toString().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet();
      if (mounted) setState(() => _serviceTypeIds = ids);
    } catch (_) {
      // no service data → provider section falls back to the universal tools only
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: AppColors.ivory)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: AppColors.ivory)),
      backgroundColor: const Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.deepBlue,
      backgroundColor: AppColors.bgMid,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            // Language toggle lives in the global nav bar (MainNavigation); no
            // per-screen chip here, or two "EN" chips stack in the corner.
            title: Text(strings.profile),
            floating: true,
            snap: true,
            backgroundColor: Colors.transparent,
          ),
          if (_isLoading)
            SliverToBoxAdapter(child: _buildSkeleton())
          else ...[
            SliverToBoxAdapter(child: _buildProfileHeader(strings)),
            SliverToBoxAdapter(child: _buildAccountSection(strings)),
            if (_user?.role != 'provider' && _user?.role != 'admin')
              SliverToBoxAdapter(child: _buildBecomeProviderSection()),
            SliverToBoxAdapter(child: _buildServicesSection()),
            if (_user?.role == 'provider' || _user?.role == 'PROVIDER')
              SliverToBoxAdapter(child: _buildProviderSection()),
            SliverToBoxAdapter(child: _buildSettingsSection(strings)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: GlassButton(
                  label: strings.logout,
                  icon: Icons.logout_rounded,
                  isOutlined: true,
                  onPressed: () => _handleLogout(strings),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildDangerZone()),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ],
      ),
    );
  }

  // ── Danger zone: delete account (Play Store / privacy compliance) ──

  Widget _buildDangerZone() {
    final isBn = context.read<LanguageNotifier>().isBengali;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(isBn ? 'বিপজ্জনক অঞ্চল' : 'DANGER ZONE'),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _handleDeleteAccount,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isBn ? 'অ্যাকাউন্ট মুছে ফেলুন' : 'Delete my account',
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isBn ? 'স্থায়ীভাবে মুছে যাবে — ফেরানো যাবে না' : 'Permanent — this cannot be undone',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ).animate(delay: 320.ms).fadeIn().slideY(begin: 0.05),
        ],
      ),
    );
  }

  Future<void> _handleDeleteAccount() async {
    final isBn = context.read<LanguageNotifier>().isBengali;
    // Two-step confirmation: intent, then a typed word.
    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isBn ? 'অ্যাকাউন্ট মুছবেন?' : 'Delete account?',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          isBn
              ? 'আপনার প্রোফাইল, বুকিং ও ডেটা স্থায়ীভাবে মুছে যাবে এবং সব সেশন বন্ধ হবে। এটি ফেরানো যাবে না।'
              : 'Your profile, bookings and data will be permanently removed and all sessions signed out. This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(isBn ? 'বাতিল' : 'Cancel', style: const TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(isBn ? 'চালিয়ে যান' : 'Continue',
                  style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    final confirmWord = isBn ? 'DELETE' : 'DELETE';
    final ctrl = TextEditingController();
    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isBn ? 'নিশ্চিত করুন' : 'Final confirmation',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isBn ? 'নিশ্চিত হতে নিচে "DELETE" লিখুন।' : 'Type "DELETE" below to confirm.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(hintText: 'DELETE'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(isBn ? 'বাতিল' : 'Cancel', style: const TextStyle(color: AppColors.textMuted))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().toUpperCase() == confirmWord),
            child: Text(isBn ? 'মুছে ফেলুন' : 'Delete forever',
                style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (step2 != true || !mounted) return;

    try {
      await AuthService.instance.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    } catch (e) {
      _showError(e.toString());
    }
  }

  // ── Skeleton ──────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 86,
              height: 86,
              decoration: const BoxDecoration(
                color: AppColors.glassWhite,
                shape: BoxShape.circle,
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 600.ms),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 140,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(9),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 600.ms),
          ),
          const SizedBox(height: 24),
          ...List.generate(
            3,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.glassBorder, width: 1.5),
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 600.ms),
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile header ────────────────────────────────────────────────

  Widget _buildProfileHeader(AppStrings strings) {
    final user = _user;
    if (user == null) return const SizedBox.shrink();
    final initial = user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?';
    final isBn = context.read<LanguageNotifier>().isBengali;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  gradient: AppColors.blueGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.deepBlue.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: AppColors.ivory,
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _showEditProfileSheet(strings),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: AppColors.fuchsiaGradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bgDark, width: 2),
                  ),
                  child: const Icon(Icons.edit_rounded, color: AppColors.ivory, size: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            user.fullName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (user.email?.isNotEmpty ?? false) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.email_outlined, color: AppColors.textMuted, size: 14),
                const SizedBox(width: 6),
                Text(user.email!,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                if (user.isEmailVerified) ...[
                  const SizedBox(width: 8),
                  _verifiedBadge(isBn),
                ],
              ],
            ),
            const SizedBox(height: 4),
          ],
          if (user.phone != null && user.phone!.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.phone_android_rounded, color: AppColors.textMuted, size: 14),
                const SizedBox(width: 6),
                Text(user.phone!,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                if (user.isPhoneVerified) ...[
                  const SizedBox(width: 8),
                  _verifiedBadge(isBn),
                ],
              ],
            ),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _roleBadge(user.role, isBn),
              if (user.tier != null) ...[
                const SizedBox(width: 8),
                _tierBadge(user.tier!),
              ],
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05);
  }

  Widget _verifiedBadge(bool isBn) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x334CAF50),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x664CAF50), width: 1),
      ),
      child: Text(
        isBn ? 'যাচাইকৃত' : 'Verified',
        style: const TextStyle(
            color: Color(0xFF4CAF50), fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _roleBadge(String role, bool isBn) {
    final isProvider = role == 'provider' || role == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        gradient: isProvider ? AppColors.fuchsiaGradient : AppColors.blueGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isProvider
            ? (isBn ? 'সেবা প্রদানকারী' : 'Provider')
            : (isBn ? 'গ্রাহক' : 'Customer'),
        style: const TextStyle(
            color: AppColors.ivory, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _tierBadge(String tier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder, width: 1),
      ),
      child: Text(
        tier.toUpperCase(),
        style: const TextStyle(
            color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ── Account section ───────────────────────────────────────────────

  Widget _buildAccountSection(AppStrings strings) {
    final isBn = context.read<LanguageNotifier>().isBengali;
    final items = [
      (Icons.person_rounded, strings.editProfile, _showEditProfileSheet),
      (Icons.location_on_rounded, strings.myAddresses, _showAddressesSheet),
      (Icons.lock_rounded, strings.changePassword, _showChangePasswordSheet),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(isBn ? 'অ্যাকাউন্ট' : 'ACCOUNT'),
          const SizedBox(height: 12),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: List.generate(items.length, (i) {
                final (icon, label, action) = items[i];
                return Column(
                  children: [
                    ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: AppColors.blueGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: AppColors.ivory, size: 18),
                      ),
                      title: Text(label,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded,
                          color: AppColors.textMuted, size: 14),
                      onTap: () => action(strings),
                    ),
                    if (i < items.length - 1)
                      const Divider(height: 1, color: AppColors.glassBorder, indent: 60),
                  ],
                );
              }),
            ),
          ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.05),
        ],
      ),
    );
  }

  // ── Become Provider section ───────────────────────────────────────

  Widget _buildBecomeProviderSection() {
    final isBn = context.read<LanguageNotifier>().isBengali;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProviderOnboardingScreen()),
        ).then((_) => _loadData()),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.blueGradient, // pine
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: AppColors.deepBlue.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(gradient: AppColors.fuchsiaGradient, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.store_rounded, color: Color(0xFF3D2A00), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBn ? 'Provider হিসেবে যোগ দিন' : 'Become a Provider',
                      style: const TextStyle(color: AppColors.ivory, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isBn ? 'আপনার দক্ষতাকে কাজে লাগিয়ে আয় করুন' : 'Earn by offering your skills',
                      style: const TextStyle(color: Color(0xCCFDFBF6), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.fuchsia, size: 16),
            ],
          ),
        ),
      ),
    ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.05);
  }

  // ── Settings section ──────────────────────────────────────────────

  Widget _buildSettingsSection(AppStrings strings) {
    final isBn = context.read<LanguageNotifier>().isBengali;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(isBn ? 'সেটিংস' : 'SETTINGS'),
          const SizedBox(height: 12),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: const Icon(Icons.language_rounded,
                        color: AppColors.textSecondary, size: 18),
                  ),
                  title: Text(
                    isBn ? 'ভাষা' : 'Language',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    isBn ? 'বাংলা' : 'English',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                  trailing: GestureDetector(
                    onTap: () => context.read<LanguageNotifier>().toggle(),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: AppColors.blueGradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        strings.langToggle,
                        style: const TextStyle(
                            color: AppColors.ivory,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  onTap: () => context.read<LanguageNotifier>().toggle(),
                ),
                const Divider(height: 1, color: AppColors.glassBorder, indent: 60),
                ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: const Icon(Icons.help_rounded,
                        color: AppColors.textSecondary, size: 18),
                  ),
                  title: Text(
                    isBn ? 'সাহায্য ও সহায়তা' : 'Help & Support',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded,
                      color: AppColors.textMuted, size: 14),
                  onTap: () {},
                ),
              ],
            ),
          ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.05),
        ],
      ),
    );
  }

  // ── Services section (all users) ─────────────────────────────────

  // Account-level activity every user has — NOT a launcher for bookable services
  // (those live on the home / services page). Keeps the profile focused.
  Widget _buildServicesSection() {
    final isBn = context.read<LanguageNotifier>().isBengali;
    void nav(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    final tiles = <Widget>[
      // The landlord entry point — an owner advertises their mess/house from here.
      _profileTile(Icons.home_work_outlined, isBn ? 'আমার বিজ্ঞাপন' : 'My Listings', () => nav(const MyAdsScreen()),
          color: const Color(0xFFB45309),
          subtitle: isBn ? 'বাসা / মেস ভাড়া দিন' : 'Rent out your house / mess'),
      _profileTile(Icons.notifications_outlined, isBn ? 'নোটিফিকেশন' : 'Notifications', () => nav(const NotificationListScreen()), color: const Color(0xFF8B5CF6)),
      _profileTile(Icons.assignment_outlined, isBn ? 'আমার অনুরোধ' : 'My Requests', () => nav(const MyMatchRequestsScreen()), color: const Color(0xFF06B6D4)),
      _profileTile(Icons.receipt_outlined, isBn ? 'পেমেন্ট ইতিহাস' : 'Payments', () => nav(const PaymentScreen()), color: const Color(0xFF10B981)),
      _profileTile(Icons.report_outlined, isBn ? 'অভিযোগ' : 'Disputes', () => nav(const DisputeScreen()), color: const Color(0xFFEF4444)),
      _profileTile(Icons.people_outline_rounded, isBn ? 'রেফারেল' : 'Referral', () => nav(const ReferralScreen()), color: const Color(0xFF06B6D4)),
      _profileTile(Icons.star_outline_rounded, isBn ? 'সাবস্ক্রিপশন' : 'Subscription', () => nav(const SubscriptionScreen()), color: AppColors.deepBlue),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(isBn ? 'আমার কার্যকলাপ' : 'MY ACTIVITY'),
          const SizedBox(height: 12),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(children: _withDividers(tiles)),
          ).animate(delay: 260.ms).fadeIn().slideY(begin: 0.05),
        ],
      ),
    );
  }

  // Insert hairline dividers between tiles (so a variable-length list stays tidy).
  List<Widget> _withDividers(List<Widget> tiles) {
    final out = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      out.add(tiles[i]);
      if (i < tiles.length - 1) {
        out.add(const Divider(height: 1, color: AppColors.glassBorder, indent: 60));
      }
    }
    return out;
  }

  // ── Provider section ──────────────────────────────────────────────

  // Provider tools, filtered to the services this provider actually offers.
  // A lawyer sees Go Online / Wallet / NID etc. — never Portfolio, Pricing or
  // Teach-a-Course, which belong to photographers, technicians and instructors.
  Widget _buildProviderSection() {
    final isBn = context.read<LanguageNotifier>().isBengali;
    void nav(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    final isTechnician = _offers(['technician']);
    final isVisual = _offers(['photograph', 'cinema', 'makeup']);
    final isInstructor = _offers(['learning', 'course', 'tutor', 'skill']);
    final isLawyer = _offers(['lawyer', 'legal']);

    final tiles = <Widget>[
      _profileTile(Icons.wifi_rounded, isBn ? 'অনলাইন স্ট্যাটাস' : 'Go Online', () => nav(const ProviderOnlineScreen()), color: const Color(0xFF10B981)),
      // Technician specialization picker — a live-verified backend snapshot
      // decides which specialization codes each online technician receives.
      // Without ticking any, they get no specialized jobs.
      if (isTechnician)
        _profileTile(
          Icons.build_rounded,
          isBn ? 'আমার বিশেষত্ব' : 'My Specializations',
          () => nav(const TechnicianSpecializationsScreen()),
          color: const Color(0xFF0EA5E9),
        ),
      // FIXED/CUSTOM per task-category pricing only applies to technician jobs.
      if (isTechnician)
        _profileTile(Icons.price_change_rounded, isBn ? 'মূল্য নির্ধারণ' : 'Pricing', () => nav(const ProviderPricingScreen()), color: const Color(0xFF14B8A6)),
      // Course authoring is for micro-learning / skill instructors only.
      if (isInstructor)
        _profileTile(Icons.cast_for_education_rounded, isBn ? 'কোর্স তৈরি' : 'Teach a Course', () => nav(const CourseAuthoringScreen()), color: const Color(0xFFAD1457)),
      // Lawyers: consultation broadcasts route by practice area — editable here
      // so changing focus doesn't require redoing onboarding.
      if (isLawyer)
        _profileTile(Icons.gavel_rounded, isBn ? 'প্র্যাকটিস এরিয়া' : 'Practice Areas', () => nav(const LawyerAreasScreen()), color: const Color(0xFF7C3AED)),
      // A visual portfolio is for photographers / cinematographers / makeup artists.
      if (isVisual)
        _profileTile(Icons.photo_library_outlined, isBn ? 'পোর্টফোলিও' : 'Portfolio', () => nav(const PortfolioScreen()), color: const Color(0xFFEF4444)),
      _profileTile(Icons.account_balance_wallet_outlined, isBn ? 'ওয়ালেট' : 'Wallet', () => nav(const WalletScreen()), color: const Color(0xFF3B82F6)),
      _profileTile(Icons.percent_rounded, isBn ? 'কমিশন' : 'Commission', () => nav(const CommissionScreen()), color: const Color(0xFFF59E0B)),
      _profileTile(Icons.credit_card_outlined, isBn ? 'NID যাচাইকরণ' : 'NID Verification', () => nav(const NidScreen()), color: const Color(0xFF8B5CF6)),
      _profileTile(Icons.shield_outlined, isBn ? 'ব্যাকগ্রাউন্ড চেক' : 'Background Check', () => nav(const BackgroundCheckScreen()), color: const Color(0xFF8B5CF6)),
      _profileTile(Icons.tune_rounded, isBn ? 'নোটিফিকেশন সেটিংস' : 'Notification Settings', () => nav(const NotificationPreferencesScreen()), color: AppColors.textMuted),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(isBn ? 'প্রোভাইডার' : 'PROVIDER'),
          const SizedBox(height: 12),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(children: _withDividers(tiles)),
          ).animate(delay: 280.ms).fadeIn().slideY(begin: 0.05),
        ],
      ),
    );
  }

  Widget _profileTile(IconData icon, String label, VoidCallback onTap, {Color? color, String? subtitle}) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: (color ?? AppColors.deepBlue).withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color ?? AppColors.deepBlue, size: 18),
      ),
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12))
          : null,
      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
      onTap: onTap,
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }

  // ── Logout ────────────────────────────────────────────────────────

  Future<void> _handleLogout(AppStrings strings) async {
    final isBn = context.read<LanguageNotifier>().isBengali;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isBn ? 'লগআউট নিশ্চিত করুন' : 'Confirm Logout',
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        content: Text(
          isBn
              ? 'আপনি কি নিশ্চিতভাবে লগআউট করতে চান?'
              : 'Are you sure you want to log out?',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.cancel,
                style: const TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.logout,
                style: const TextStyle(
                    color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await AuthService.instance.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    }
  }

  // ── Edit Profile sheet ────────────────────────────────────────────

  void _showEditProfileSheet(AppStrings strings) {
    final nameCtrl = TextEditingController(text: _user?.fullName ?? '');
    final phoneCtrl = TextEditingController(text: _user?.phone ?? '');
    final isBn = context.read<LanguageNotifier>().isBengali;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _bottomSheet(
            title: strings.editProfile,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetTextField(
                  controller: nameCtrl,
                  hint: isBn ? 'পুরো নাম' : 'Full name',
                  icon: Icons.person_rounded,
                ),
                const SizedBox(height: 14),
                _sheetTextField(
                  controller: phoneCtrl,
                  hint: isBn ? 'মোবাইল নম্বর' : 'Mobile number',
                  icon: Icons.phone_android_rounded,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 24),
                _SheetSaveButton(
                  label: strings.saveChanges,
                  onPressed: (setSaving) async {
                    setSaving(true);
                    try {
                      final updated = await AuthService.instance.updateProfile(
                        fullName: nameCtrl.text.trim().isNotEmpty
                            ? nameCtrl.text.trim()
                            : null,
                        phone: phoneCtrl.text.trim().isNotEmpty
                            ? phoneCtrl.text.trim()
                            : null,
                      );
                      if (mounted) setState(() => _user = updated);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showSuccess(isBn ? 'প্রোফাইল আপডেট হয়েছে' : 'Profile updated');
                    } catch (e) {
                      _showError(e.toString());
                    } finally {
                      setSaving(false);
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Change Password sheet ─────────────────────────────────────────

  void _showChangePasswordSheet(AppStrings strings) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final isBn = context.read<LanguageNotifier>().isBengali;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _bottomSheet(
            title: strings.changePassword,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetTextField(
                  controller: oldCtrl,
                  hint: isBn ? 'বর্তমান পাসওয়ার্ড' : 'Current password',
                  icon: Icons.lock_outline_rounded,
                  obscure: true,
                ),
                const SizedBox(height: 14),
                _sheetTextField(
                  controller: newCtrl,
                  hint: isBn ? 'নতুন পাসওয়ার্ড' : 'New password',
                  icon: Icons.lock_rounded,
                  obscure: true,
                ),
                const SizedBox(height: 14),
                _sheetTextField(
                  controller: confirmCtrl,
                  hint: isBn ? 'নতুন পাসওয়ার্ড নিশ্চিত করুন' : 'Confirm new password',
                  icon: Icons.lock_rounded,
                  obscure: true,
                ),
                const SizedBox(height: 24),
                _SheetSaveButton(
                  label: strings.saveChanges,
                  onPressed: (setSaving) async {
                    if (newCtrl.text != confirmCtrl.text) {
                      _showError(isBn
                          ? 'নতুন পাসওয়ার্ড মিলছে না'
                          : 'New passwords do not match');
                      return;
                    }
                    if (newCtrl.text.length < 6) {
                      _showError(strings.errPasswordShort);
                      return;
                    }
                    setSaving(true);
                    try {
                      await AuthService.instance.changePassword(
                        oldPassword: oldCtrl.text,
                        newPassword: newCtrl.text,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showSuccess(isBn ? 'পাসওয়ার্ড পরিবর্তন হয়েছে' : 'Password changed');
                    } catch (e) {
                      _showError(e.toString());
                    } finally {
                      setSaving(false);
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Addresses sheet ───────────────────────────────────────────────

  void _showAddressesSheet(AppStrings strings) {
    final isBn = context.read<LanguageNotifier>().isBengali;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (_, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: AppColors.bgMid,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: AppColors.glassBorder, width: 1),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.glassBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        strings.myAddresses,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _showAddAddressSheet(strings);
                          if (mounted) _showAddressesSheet(strings);
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: AppColors.blueGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.add_rounded,
                              color: AppColors.ivory, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _addresses.isEmpty
                      ? Center(
                          child: Text(
                            isBn ? 'কোনো ঠিকানা নেই' : 'No addresses saved',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 14),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _addresses.length,
                          itemBuilder: (_, i) {
                            final addr = _addresses[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: addr.isDefault
                                      ? AppColors.glassBlue
                                      : AppColors.glassWhite,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: addr.isDefault
                                        ? AppColors.glassBorderBlue
                                        : AppColors.glassBorder,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (addr.label != null &&
                                              addr.label!.isNotEmpty) ...[
                                            Row(
                                              children: [
                                                Text(addr.label!,
                                                    style: const TextStyle(
                                                      color:
                                                          AppColors.textPrimary,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    )),
                                                if (addr.isDefault) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      gradient: AppColors
                                                          .blueGradient,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    child: Text(
                                                      isBn
                                                          ? 'ডিফল্ট'
                                                          : 'Default',
                                                      style: const TextStyle(
                                                          color: AppColors.ivory,
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.w600),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                          ],
                                          Text(addr.displayText,
                                              style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      children: [
                                        if (!addr.isDefault)
                                          GestureDetector(
                                            onTap: () async {
                                              try {
                                                await AuthService.instance
                                                    .setDefaultAddress(addr.id);
                                                final updated =
                                                    await AuthService.instance
                                                        .listAddresses();
                                                if (mounted) {
                                                  setState(() =>
                                                      _addresses = updated);
                                                }
                                                setSheet(() {});
                                              } catch (e) {
                                                _showError(e.toString());
                                              }
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              margin: const EdgeInsets.only(
                                                  bottom: 6),
                                              decoration: BoxDecoration(
                                                color: AppColors.glassWhite,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color: AppColors.glassBorder,
                                                    width: 1),
                                              ),
                                              child: Text(
                                                isBn ? 'ডিফল্ট' : 'Set default',
                                                style: const TextStyle(
                                                    color: AppColors.textMuted,
                                                    fontSize: 10),
                                              ),
                                            ),
                                          ),
                                        GestureDetector(
                                          onTap: () async {
                                            try {
                                              await AuthService.instance
                                                  .deleteAddress(addr.id);
                                              final updated =
                                                  await AuthService.instance
                                                      .listAddresses();
                                              if (mounted) {
                                                setState(() =>
                                                    _addresses = updated);
                                              }
                                              setSheet(() {});
                                            } catch (e) {
                                              _showError(e.toString());
                                            }
                                          },
                                          child: const Icon(
                                              Icons.delete_outline_rounded,
                                              color: Color(0xFFEF4444),
                                              size: 20),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Add Address sheet ─────────────────────────────────────────────

  Future<void> _showAddAddressSheet(AppStrings strings) async {
    final labelCtrl = TextEditingController();
    final line1Ctrl = TextEditingController();
    final areaCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final districtCtrl = TextEditingController();
    final isBn = context.read<LanguageNotifier>().isBengali;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _bottomSheet(
            title: strings.addAddress,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetTextField(
                      controller: labelCtrl,
                      hint: isBn
                          ? 'লেবেল (বাড়ি, অফিস...)'
                          : 'Label (Home, Office…)',
                      icon: Icons.label_rounded),
                  const SizedBox(height: 12),
                  _sheetTextField(
                      controller: line1Ctrl,
                      hint: isBn ? 'ঠিকানা (আবশ্যক)' : 'Address line 1 *',
                      icon: Icons.home_rounded),
                  const SizedBox(height: 12),
                  _sheetTextField(
                      controller: areaCtrl,
                      hint: isBn ? 'এলাকা' : 'Area',
                      icon: Icons.location_city_rounded),
                  const SizedBox(height: 12),
                  _sheetTextField(
                      controller: cityCtrl,
                      hint: isBn ? 'শহর' : 'City',
                      icon: Icons.location_on_rounded),
                  const SizedBox(height: 12),
                  _sheetTextField(
                      controller: districtCtrl,
                      hint: isBn ? 'জেলা' : 'District',
                      icon: Icons.map_rounded),
                  const SizedBox(height: 24),
                  _SheetSaveButton(
                    label: strings.addAddress,
                    onPressed: (setSaving) async {
                      if (line1Ctrl.text.trim().isEmpty) {
                        _showError(isBn
                            ? 'ঠিকানার লাইন ১ দিন'
                            : 'Enter address line 1');
                        return;
                      }
                      setSaving(true);
                      try {
                        await AuthService.instance.createAddress(
                          line1: line1Ctrl.text.trim(),
                          label: labelCtrl.text.trim().isNotEmpty
                              ? labelCtrl.text.trim()
                              : null,
                          area: areaCtrl.text.trim().isNotEmpty
                              ? areaCtrl.text.trim()
                              : null,
                          city: cityCtrl.text.trim().isNotEmpty
                              ? cityCtrl.text.trim()
                              : null,
                          district: districtCtrl.text.trim().isNotEmpty
                              ? districtCtrl.text.trim()
                              : null,
                        );
                        final updated =
                            await AuthService.instance.listAddresses();
                        if (mounted) setState(() => _addresses = updated);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _showSuccess(
                            isBn ? 'ঠিকানা যোগ হয়েছে' : 'Address added');
                      } catch (e) {
                        _showError(e.toString());
                      } finally {
                        setSaving(false);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared bottom sheet wrapper ───────────────────────────────────

  Widget _bottomSheet({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.glassBorder, width: 1),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.glassBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _sheetTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
      ),
    );
  }
}

// ── Inline save button with own loading state ─────────────────────

class _SheetSaveButton extends StatefulWidget {
  final String label;
  final Future<void> Function(void Function(bool) setSaving) onPressed;

  const _SheetSaveButton({required this.label, required this.onPressed});

  @override
  State<_SheetSaveButton> createState() => _SheetSaveButtonState();
}

class _SheetSaveButtonState extends State<_SheetSaveButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      label: widget.label,
      isLoading: _loading,
      onPressed: () => widget.onPressed((v) {
        if (mounted) setState(() => _loading = v);
      }),
    );
  }
}
