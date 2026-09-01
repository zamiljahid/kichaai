import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_button.dart';
import 'auth_screen.dart';
import 'background_check_screen.dart';
import 'bundles_screen.dart';
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
  // Account avatar (GET /auth/me -> avatarUrl). Held separately from _user because the
  // profile header is built from the cached session values, not from a /auth/me round trip.
  String? _avatarUrl;
  bool _uploadingAvatar = false;
  // Loyalty tier. Provider-only server-side: /auth/tiers/me 404s for an account with no
  // tier record, which is normal, so the badge simply stays hidden.
  String? _tier;
  // Real verification state comes from /auth/me (emailVerifiedAt / phoneVerifiedAt). The
  // header is otherwise built from cached session values, which never carried these — so the
  // "Verified" badge could never appear, and there was no way to start verification either.
  bool _emailVerified = false;
  bool _phoneVerified = false;
  bool _sendingVerify = false;

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
        _loadAvatarAndTier();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Best-effort extras for the header — neither should ever block the screen.
  Future<void> _loadAvatarAndTier() async {
    try {
      final me = await AuthService.instance.getCurrentUser();
      if (mounted) {
        setState(() {
          _avatarUrl = me.profileImageUrl;
          _emailVerified = me.isEmailVerified;
          _phoneVerified = me.isPhoneVerified;
        });
      }
    } catch (_) {
      // Offline or a transient failure — the initial-letter avatar still renders.
    }
    try {
      final t = await AuthService.instance.getMyTier();
      final name = (t['tier'] ?? t['name'] ?? t['currentTier'])?.toString();
      if (mounted && name != null && name.isNotEmpty) setState(() => _tier = name);
    } catch (_) {
      // 404 "Provider not found" is the normal case for a customer — no badge.
    }
  }

  /// Sends a verification code to the account's phone or email.
  Future<void> _startVerification({required bool phone}) async {
    if (_sendingVerify) return;
    final isBn = context.read<LanguageNotifier>().isBengali;
    setState(() => _sendingVerify = true);
    try {
      if (phone) {
        await AuthService.instance.startPhoneVerification();
      } else {
        await AuthService.instance.startEmailVerification();
      }
      if (!mounted) return;
      _showSuccess(isBn
          ? 'কোড পাঠানো হয়েছে — যাচাই করে আবার এই স্ক্রিনে আসুন'
          : 'Code sent — verify it, then reopen this screen');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _sendingVerify = false);
    }
  }

  /// Tappable "Verify" chip shown next to an unverified email/phone.
  Widget _verifyChip(bool isBn, {required bool phone}) {
    return GestureDetector(
      onTap: _sendingVerify ? null : () => _startVerification(phone: phone),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x33F59E0B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x66F59E0B), width: 1),
        ),
        child: Text(
          isBn ? 'যাচাই করুন' : 'Verify',
          style: const TextStyle(
              color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// Pick a photo and set it as the account avatar (POST /auth/me/profile-photo).
  /// This is the everyday account picture, not the provider verification selfie.
  Future<void> _pickAndUploadAvatar() async {
    final isBn = context.read<LanguageNotifier>().isBengali;
    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1024);
      if (picked == null) return;
      setState(() => _uploadingAvatar = true);
      final bytes = await picked.readAsBytes();
      final url = await AuthService.instance.uploadProfilePhoto(base64Encode(bytes));
      if (!mounted) return;
      setState(() {
        _avatarUrl = url ?? _avatarUrl;
        _uploadingAvatar = false;
      });
      _showSuccess(isBn ? 'ছবি আপডেট হয়েছে' : 'Photo updated');
    } catch (e) {
      if (mounted) setState(() => _uploadingAvatar = false);
      _showError(e.toString());
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
    final colors = Theme.of(context).colorScheme;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: colors.onPrimary)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showSuccess(String message) {
    final colors = Theme.of(context).colorScheme;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: colors.onPrimary)),
      backgroundColor: const Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);
    return RefreshIndicator(
      onRefresh: _loadData,
      color: colors.primary,
      backgroundColor: colors.surface,
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
            SliverToBoxAdapter(child: _buildDeleteAccount()),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ],
      ),
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: colors.surface,
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
                color: colors.surface,
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
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.outlineVariant, width: 1.5),
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
    final colors = Theme.of(context).colorScheme;
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
                  gradient: AppGradients.primary(colors),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                      ? Image.network(
                          _avatarUrl!,
                          width: 86,
                          height: 86,
                          fit: BoxFit.cover,
                          // A broken/expired URL must never leave an empty circle.
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              initial,
                              style: TextStyle(
                                color: colors.onPrimary,
                                fontSize: 36,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            initial,
                            style: TextStyle(
                              color: colors.onPrimary,
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
              ),
              GestureDetector(
                onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: AppGradients.accent(colors),
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surfaceContainerHighest, width: 2),
                  ),
                  child: _uploadingAvatar
                      ? Padding(
                          padding: EdgeInsets.all(6),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: colors.onPrimary),
                        )
                      : Icon(Icons.photo_camera_rounded,
                          color: colors.onPrimary, size: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            user.fullName,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (user.email?.isNotEmpty ?? false) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.email_outlined, color: colors.outline, size: 14),
                const SizedBox(width: 6),
                Text(user.email!,
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
                const SizedBox(width: 8),
                if (_emailVerified) _verifiedBadge(isBn) else _verifyChip(isBn, phone: false),
              ],
            ),
            const SizedBox(height: 4),
          ],
          if (user.phone != null && user.phone!.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.phone_android_rounded, color: colors.outline, size: 14),
                const SizedBox(width: 6),
                Text(user.phone!,
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
                const SizedBox(width: 8),
                if (_phoneVerified) _verifiedBadge(isBn) else _verifyChip(isBn, phone: true),
              ],
            ),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _roleBadge(user.role, isBn),
              if (_tier != null) ...[
                const SizedBox(width: 8),
                _tierBadge(_tier!),
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
    final colors = Theme.of(context).colorScheme;
    final isProvider = role == 'provider' || role == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        gradient: isProvider ? AppGradients.accent(colors) : AppGradients.primary(colors),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isProvider
            ? (isBn ? 'সেবা প্রদানকারী' : 'Provider')
            : (isBn ? 'গ্রাহক' : 'Customer'),
        style: TextStyle(
            color: colors.onPrimary, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _tierBadge(String tier) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant, width: 1),
      ),
      child: Text(
        tier.toUpperCase(),
        style: TextStyle(
            color: colors.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ── Account section ───────────────────────────────────────────────

  Widget _buildAccountSection(AppStrings strings) {
    final colors = Theme.of(context).colorScheme;
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
                          gradient: AppGradients.primary(colors),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: colors.onPrimary, size: 18),
                      ),
                      title: Text(label,
                          style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      trailing: Icon(Icons.arrow_forward_ios_rounded,
                          color: colors.outline, size: 14),
                      onTap: () => action(strings),
                    ),
                    if (i < items.length - 1)
                      Divider(height: 1, color: colors.outlineVariant, indent: 60),
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
    final colors = Theme.of(context).colorScheme;
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
            gradient: AppGradients.primary(colors), // pine
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: colors.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(gradient: AppGradients.accent(colors), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.store_rounded, color: Color(0xFF3D2A00), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBn ? 'Provider হিসেবে যোগ দিন' : 'Become a Provider',
                      style: TextStyle(color: colors.onPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isBn ? 'আপনার দক্ষতাকে কাজে লাগিয়ে আয় করুন' : 'Earn by offering your skills',
                      style: TextStyle(color: colors.onPrimary.withValues(alpha: 0.8), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: colors.secondary, size: 16),
            ],
          ),
        ),
      ),
    ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.05);
  }

  // ── Settings section ──────────────────────────────────────────────

  Widget _buildSettingsSection(AppStrings strings) {
    final colors = Theme.of(context).colorScheme;
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
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Icon(Icons.language_rounded,
                        color: colors.onSurfaceVariant, size: 18),
                  ),
                  title: Text(
                    isBn ? 'ভাষা' : 'Language',
                    style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    isBn ? 'বাংলা' : 'English',
                    style: TextStyle(color: colors.outline, fontSize: 11),
                  ),
                  trailing: GestureDetector(
                    onTap: () => context.read<LanguageNotifier>().toggle(),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: AppGradients.primary(colors),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        strings.langToggle,
                        style: TextStyle(
                            color: colors.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  onTap: () => context.read<LanguageNotifier>().toggle(),
                ),
                Divider(height: 1, color: colors.outlineVariant, indent: 60),
                ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Icon(Icons.help_rounded,
                        color: colors.onSurfaceVariant, size: 18),
                  ),
                  title: Text(
                    isBn ? 'সাহায্য ও সহায়তা' : 'Help & Support',
                    style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  trailing: Icon(Icons.arrow_forward_ios_rounded,
                      color: colors.outline, size: 14),
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
    final colors = Theme.of(context).colorScheme;
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
      _profileTile(Icons.star_outline_rounded, isBn ? 'সাবস্ক্রিপশন' : 'Subscription', () => nav(const SubscriptionScreen()), color: colors.primary),
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
    final colors = Theme.of(context).colorScheme;
    final out = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      out.add(tiles[i]);
      if (i < tiles.length - 1) {
        out.add(Divider(height: 1, color: colors.outlineVariant, indent: 60));
      }
    }
    return out;
  }

  // ── Provider section ──────────────────────────────────────────────

  // Provider tools, filtered to the services this provider actually offers.
  // A lawyer sees Go Online / Wallet / NID etc. — never Portfolio, Pricing or
  // Teach-a-Course, which belong to photographers, technicians and instructors.
  Widget _buildProviderSection() {
    final colors = Theme.of(context).colorScheme;
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
      // Multi-service discount packages. The catalog has always had these endpoints;
      // no screen ever reached them, so a provider could not make or see a bundle.
      _profileTile(Icons.inventory_2_rounded, isBn ? 'আমার প্যাকেজ' : 'My Bundles', () => nav(const BundlesScreen()), color: const Color(0xFF8B5CF6),
          subtitle: isBn ? 'কয়েকটা সেবা একসাথে ছাড়ে' : 'Several services together, at a discount'),
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
      _profileTile(Icons.tune_rounded, isBn ? 'নোটিফিকেশন সেটিংস' : 'Notification Settings', () => nav(const NotificationPreferencesScreen()), color: colors.outline),
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
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: (color ?? colors.primary).withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color ?? colors.primary, size: 18),
      ),
      title: Text(label, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: colors.outline, fontSize: 12))
          : null,
      trailing: Icon(Icons.arrow_forward_ios_rounded, color: colors.outline, size: 14),
      onTap: onTap,
    );
  }

  Widget _sectionLabel(String label) {
    final colors = Theme.of(context).colorScheme;
    return Text(
      label,
      style: TextStyle(
        color: colors.outline,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }

  // ── Delete account ────────────────────────────────────────────────

  // Google Play requires an in-app route to account deletion for any app with accounts.
  // The endpoint existed from the start but nothing ever reached it.
  Widget _buildDeleteAccount() {
    final isBn = context.read<LanguageNotifier>().isBengali;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Center(
        child: TextButton(
          onPressed: _confirmDeleteAccount,
          child: Text(
            isBn ? 'অ্যাকাউন্ট মুছে ফেলুন' : 'Delete my account',
            style: const TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final colors = Theme.of(context).colorScheme;
    final isBn = context.read<LanguageNotifier>().isBengali;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          isBn ? 'অ্যাকাউন্ট মুছে ফেলবেন?' : 'Delete your account?',
          style: TextStyle(
              color: colors.onSurface, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          isBn
              ? 'আপনার প্রোফাইল, ঠিকানা ও ইতিহাস মুছে যাবে এবং সব ডিভাইস থেকে লগআউট হবে। এটি ফেরানো যাবে না।'
              : 'Your profile, addresses and history will be removed and every session signed out. This cannot be undone.',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isBn ? 'বাতিল' : 'Cancel',
                style: TextStyle(color: colors.outline)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isBn ? 'মুছে ফেলুন' : 'Delete',
                style: const TextStyle(
                    color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AuthService.instance.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    } catch (e) {
      // The session is deliberately kept on failure so the user can retry.
      _showError(e.toString());
    }
  }

  // ── Logout ────────────────────────────────────────────────────────

  Future<void> _handleLogout(AppStrings strings) async {
    final colors = Theme.of(context).colorScheme;
    final isBn = context.read<LanguageNotifier>().isBengali;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isBn ? 'লগআউট নিশ্চিত করুন' : 'Confirm Logout',
          style: TextStyle(
              color: colors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        content: Text(
          isBn
              ? 'আপনি কি নিশ্চিতভাবে লগআউট করতে চান?'
              : 'Are you sure you want to log out?',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.cancel,
                style: TextStyle(color: colors.outline)),
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

  Future<void> _showEditProfileSheet(AppStrings strings) async {
    final nameCtrl = TextEditingController(text: _user?.fullName ?? '');
    final phoneCtrl = TextEditingController(text: _user?.phone ?? '');
    final isProvider = _user?.providerProfileId != null;
    String initialSpecialNote = '';
    if (isProvider) {
      try {
        final me = await AuthService.instance.getMeRaw();
        final pp = me['providerProfile'];
        if (pp is Map) initialSpecialNote = (pp['specialNote'] as String?) ?? '';
      } catch (_) {}
    }
    final specialNoteCtrl = TextEditingController(text: initialSpecialNote);
    if (!mounted) return;
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
                if (isProvider) ...[
                  const SizedBox(height: 14),
                  _sheetTextField(
                    controller: specialNoteCtrl,
                    hint: isBn ? 'বিশেষ নোট — আপনি কিসে বেশি পারদর্শী? (ঐচ্ছিক)' : 'Special note — what are you especially good at? (optional)',
                    icon: Icons.star_rounded,
                    maxLines: 2,
                  ),
                ],
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
                      if (isProvider) {
                        await AuthService.instance.updateSpecialNote(specialNoteCtrl.text.trim());
                      }
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
    final colors = Theme.of(context).colorScheme;
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
              color: colors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: colors.outlineVariant, width: 1),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.outlineVariant,
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
                        style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _showAddressSheet(strings);
                          if (mounted) _showAddressesSheet(strings);
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: AppGradients.primary(colors),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.add_rounded,
                              color: colors.onPrimary, size: 20),
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
                            style: TextStyle(
                                color: colors.outline, fontSize: 14),
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
                                      ? colors.primary.withValues(alpha: 0.08)
                                      : colors.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: addr.isDefault
                                        ? colors.primary.withValues(alpha: 0.20)
                                        : colors.outlineVariant,
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
                                                    style: TextStyle(
                                                      color:
                                                          colors.onSurface,
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
                                                      gradient:
                                                          AppGradients.primary(
                                                              colors),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    child: Text(
                                                      isBn
                                                          ? 'ডিফল্ট'
                                                          : 'Default',
                                                      style: TextStyle(
                                                          color: colors.onPrimary,
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
                                              style: TextStyle(
                                                  color:
                                                      colors.onSurfaceVariant,
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
                                                color: colors.surface,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color: colors.outlineVariant,
                                                    width: 1),
                                              ),
                                              child: Text(
                                                isBn ? 'ডিফল্ট' : 'Set default',
                                                style: TextStyle(
                                                    color: colors.outline,
                                                    fontSize: 10),
                                              ),
                                            ),
                                          ),
                                        GestureDetector(
                                          onTap: () async {
                                            Navigator.pop(ctx);
                                            await _showAddressSheet(strings,
                                                existing: addr);
                                            if (mounted) {
                                              _showAddressesSheet(strings);
                                            }
                                          },
                                          child: Padding(
                                            padding:
                                                EdgeInsets.only(bottom: 8),
                                            child: Icon(Icons.edit_rounded,
                                                color: colors.outline,
                                                size: 18),
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

  /// Add sheet when [existing] is null, edit sheet when it isn't. Editing was missing
  /// entirely — a wrong address could only be deleted and retyped from scratch.
  Future<void> _showAddressSheet(AppStrings strings, {AddressModel? existing}) async {
    final editing = existing != null;
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final line1Ctrl = TextEditingController(text: existing?.line1 ?? '');
    final areaCtrl = TextEditingController(text: existing?.area ?? '');
    final cityCtrl = TextEditingController(text: existing?.city ?? '');
    final districtCtrl = TextEditingController(text: existing?.district ?? '');
    final isBn = context.read<LanguageNotifier>().isBengali;
    // Captured via "use my current location" below — powers the go-online location-mismatch
    // nudge in dispatch-service (comparing live GPS against this address). A plain text
    // address with no pin still saves fine, it just skips that check.
    double? capturedLat;
    double? capturedLng;
    bool capturingLocation = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _bottomSheet(
            title: editing
                ? (isBn ? 'ঠিকানা সম্পাদনা' : 'Edit address')
                : strings.addAddress,
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
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: capturingLocation
                        ? null
                        : () async {
                            setSheet(() => capturingLocation = true);
                            try {
                              final serviceEnabled = await Geolocator.isLocationServiceEnabled();
                              var permission = await Geolocator.checkPermission();
                              if (permission == LocationPermission.denied) {
                                permission = await Geolocator.requestPermission();
                              }
                              final denied = permission == LocationPermission.denied ||
                                  permission == LocationPermission.deniedForever;
                              if (!serviceEnabled || denied) {
                                _showError(isBn ? 'লোকেশন অনুমতি প্রয়োজন' : 'Location permission required');
                              } else {
                                final pos = await Geolocator.getCurrentPosition(
                                    timeLimit: const Duration(seconds: 15));
                                capturedLat = pos.latitude;
                                capturedLng = pos.longitude;
                              }
                            } catch (_) {
                              _showError(isBn ? 'অবস্থান পাওয়া যায়নি' : 'Could not get location');
                            } finally {
                              setSheet(() => capturingLocation = false);
                            }
                          },
                    icon: capturingLocation
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(capturedLat != null ? Icons.check_circle_rounded : Icons.my_location_rounded,
                            color: capturedLat != null ? const Color(0xFF10B981) : null, size: 18),
                    label: Text(capturedLat != null
                        ? (isBn ? 'অবস্থান যুক্ত হয়েছে' : 'Location captured')
                        : (isBn ? 'বর্তমান অবস্থান ব্যবহার করুন' : 'Use my current location')),
                  ),
                  const SizedBox(height: 12),
                  _SheetSaveButton(
                    label: editing
                        ? (isBn ? 'আপডেট করুন' : 'Update')
                        : strings.addAddress,
                    onPressed: (setSaving) async {
                      if (line1Ctrl.text.trim().isEmpty) {
                        _showError(isBn
                            ? 'ঠিকানার লাইন ১ দিন'
                            : 'Enter address line 1');
                        return;
                      }
                      setSaving(true);
                      try {
                        final label = labelCtrl.text.trim().isNotEmpty
                            ? labelCtrl.text.trim()
                            : null;
                        final area = areaCtrl.text.trim().isNotEmpty
                            ? areaCtrl.text.trim()
                            : null;
                        final city = cityCtrl.text.trim().isNotEmpty
                            ? cityCtrl.text.trim()
                            : null;
                        final district = districtCtrl.text.trim().isNotEmpty
                            ? districtCtrl.text.trim()
                            : null;
                        if (editing) {
                          await AuthService.instance.updateAddress(
                            existing.id,
                            line1: line1Ctrl.text.trim(),
                            label: label,
                            area: area,
                            city: city,
                            district: district,
                          );
                        } else {
                          await AuthService.instance.createAddress(
                            line1: line1Ctrl.text.trim(),
                            label: label,
                            area: area,
                            city: city,
                            district: district,
                            latitude: capturedLat,
                            longitude: capturedLng,
                          );
                        }
                        final updated =
                            await AuthService.instance.listAddresses();
                        if (mounted) setState(() => _addresses = updated);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _showSuccess(editing
                            ? (isBn ? 'ঠিকানা আপডেট হয়েছে' : 'Address updated')
                            : (isBn ? 'ঠিকানা যোগ হয়েছে' : 'Address added'));
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
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: colors.outlineVariant, width: 1),
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
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: TextStyle(
                  color: colors.onSurface,
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
    int maxLines = 1,
  }) {
    final colors = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: colors.onSurface, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: colors.outline, size: 20),
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
