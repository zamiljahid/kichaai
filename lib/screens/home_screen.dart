import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../models/dispatch_model.dart';
import '../services/dispatch_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'courses_screen.dart';
import 'grocery_screen.dart';
import 'job_request_screen.dart';
import 'lawyer_consultation_screen.dart';
import 'mess_screen.dart';
import 'provider_browse_screen.dart';
import 'provider_profile_screen.dart';
import 'scrap_screen.dart';
import 'service_selection_screen.dart';
import 'skill_share_screen.dart';

class _ServiceItem {
  final String nameBn;
  final String nameEn;
  final IconData icon;
  final String flow;
  final String? kind;

  const _ServiceItem({
    required this.nameBn,
    required this.nameEn,
    required this.icon,
    required this.flow,
    this.kind,
  });
}

// Matches the backend catalog (GET /catalog/service-types) — the real service
// kinds. Electrician/Plumber/AC/Cleaning are NOT separate kinds; they are task
// categories under `technician`.
const _kServices = [
  _ServiceItem(nameBn: 'টেকনিশিয়ান', nameEn: 'Technician', icon: Icons.build_rounded, flow: 'dispatch', kind: 'technician'),
  _ServiceItem(nameBn: 'কাজের লোক', nameEn: 'Quick Help', icon: Icons.handyman_rounded, flow: 'dispatch', kind: 'task_runner'),
  _ServiceItem(nameBn: 'কেয়ারগিভার', nameEn: 'Caregiver', icon: Icons.health_and_safety_rounded, flow: 'dispatch', kind: 'caregiver'),
  _ServiceItem(nameBn: 'আইনজীবী', nameEn: 'Lawyer', icon: Icons.gavel_rounded, flow: 'lawyer', kind: 'lawyer'),
  _ServiceItem(nameBn: 'ফটোগ্রাফার', nameEn: 'Photographer', icon: Icons.camera_alt_rounded, flow: 'dispatch', kind: 'photographer'),
  _ServiceItem(nameBn: 'সিনেমাটোগ্রাফার', nameEn: 'Cinematographer', icon: Icons.videocam_rounded, flow: 'dispatch', kind: 'cinematographer'),
  _ServiceItem(nameBn: 'মেকআপ আর্টিস্ট', nameEn: 'Makeup Artist', icon: Icons.face_retouching_natural_rounded, flow: 'dispatch', kind: 'makeup_artist'),
  _ServiceItem(nameBn: 'হোম টিউটর', nameEn: 'Home Tutor', icon: Icons.school_rounded, flow: 'matchmaking', kind: 'tutor'),
  _ServiceItem(nameBn: 'পেট কেয়ার', nameEn: 'Pet Care', icon: Icons.pets_rounded, flow: 'matchmaking', kind: 'pet_care'),
  _ServiceItem(nameBn: 'মেস / আবাসন', nameEn: 'Mess & Housing', icon: Icons.home_work_rounded, flow: 'mess', kind: 'mess_finder'),
  _ServiceItem(nameBn: 'স্ক্র্যাপ', nameEn: 'Scrap', icon: Icons.recycling_rounded, flow: 'scrap', kind: 'scrap_collection'),
  _ServiceItem(nameBn: 'স্কিল শেয়ার', nameEn: 'Skill Share', icon: Icons.auto_awesome_rounded, flow: 'skill_share', kind: 'skill_share'),
  _ServiceItem(nameBn: 'মাইক্রো লার্নিং', nameEn: 'Micro Learning', icon: Icons.play_circle_outline_rounded, flow: 'learning', kind: 'micro_learning'),
  _ServiceItem(nameBn: 'গ্রোসারি', nameEn: 'Grocery', icon: Icons.local_grocery_store_rounded, flow: 'grocery', kind: 'grocery'),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();

  List<NearbyProviderModel> _providers = [];
  bool _isLoading = true;

  static const _colorPalette = [
    Color(0xFF2563EB),
    Color(0xFF1565C0),
    Color(0xFFD8125B),
    Color(0xFF2E7D32),
    Color(0xFFE65100),
    Color(0xFF00838F),
    Color(0xFF6A1B9A),
    Color(0xFFC62828),
    Color(0xFF00695C),
    Color(0xFFAD1457),
    Color(0xFF0277BD),
    Color(0xFF558B2F),
    Color(0xFFBF360C),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final providers = await DispatchService.instance.searchProviders();
      if (mounted) {
        setState(() {
          _providers = providers;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _colorForIndex(int index) => _colorPalette[index % _colorPalette.length];

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.deepBlue,
      backgroundColor: AppColors.bgMid,
      child: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(child: _buildSearchBar(context)),
          SliverToBoxAdapter(child: _buildActiveRequest(context)),
          SliverToBoxAdapter(child: _buildSectionTitle(context)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _buildCategoryGrid(),
          ),
          SliverToBoxAdapter(child: _buildProviderSectionTitle(context)),
          SliverToBoxAdapter(
            child: _isLoading
                ? _buildSkeletonProviderRow()
                : _buildFeaturedProviders(),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final strings = AppStrings.of(context);
    return SliverAppBar(
      expandedHeight: 96,
      floating: true,
      snap: true,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        background: Padding(
          padding: const EdgeInsets.fromLTRB(20, 34, 20, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.greeting, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                strings.homeQuestion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 21, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: strings.searchHint,
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
              suffixIcon: Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: AppColors.blueGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  strings.filterLabel,
                  style: const TextStyle(
                    color: AppColors.ivory,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildActiveRequest(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ServiceSelectionScreen()),
        ),
        child: GlassCard(
        padding: const EdgeInsets.all(16),
        glassColor: AppColors.glassBlue,
        borderColor: AppColors.glassBorderBlue,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: AppColors.blueGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: AppColors.deepBlue.withOpacity(0.4), blurRadius: 12),
                ],
              ),
              child: const Icon(Icons.add_circle_rounded, color: AppColors.ivory, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.newRequest,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Post a new service request',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.deepBlue, size: 16),
          ],
        ),
      ),
      ),
    ).animate(delay: 200.ms).fadeIn().slideX(begin: -0.1);
  }

  Widget _buildSectionTitle(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.categories,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Service Categories',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ServiceSelectionScreen()),
            ),
            child: Text(
              strings.viewAll,
              style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSectionTitle(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.topProviders, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                Text('Top Providers', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProviderBrowseScreen(kind: '', label: 'সব প্রোভাইডার')),
            ),
            child: Text(strings.viewAll, style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Category grid ─────────────────────────────────────────────────

  void _onServiceTap(_ServiceItem item) {
    final nav = Navigator.of(context);
    switch (item.flow) {
      case 'dispatch':
        nav.push(MaterialPageRoute(
          builder: (_) => JobRequestScreen(serviceKind: item.kind!, serviceLabel: item.nameBn),
        ));
      case 'lawyer':
        nav.push(MaterialPageRoute(builder: (_) => const LawyerConsultationScreen()));
      case 'matchmaking':
        nav.push(MaterialPageRoute(
          builder: (_) => ProviderBrowseScreen(kind: item.kind!, label: item.nameBn),
        ));
      case 'mess':
        nav.push(MaterialPageRoute(builder: (_) => const MessScreen()));
      case 'scrap':
        nav.push(MaterialPageRoute(builder: (_) => const ScrapScreen()));
      case 'skill_share':
        nav.push(MaterialPageRoute(builder: (_) => const SkillShareScreen()));
      case 'learning':
        nav.push(MaterialPageRoute(builder: (_) => const CoursesScreen()));
      case 'grocery':
        nav.push(MaterialPageRoute(builder: (_) => const GroceryScreen()));
    }
  }

  Widget _buildCategoryGrid() {
    final isBn = context.read<LanguageNotifier>().isBengali;
    // Max-extent keeps tiles a sensible size on any width (fixed column count
    // made cells huge on wide screens, leaving big empty gaps).
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 104,
        childAspectRatio: 0.74,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildCategoryItem(_kServices[index], index, isBn),
        childCount: _kServices.length,
      ),
    );
  }

  Widget _buildCategoryItem(_ServiceItem item, int index, bool isBn) {
    final color = _colorForIndex(index);
    return GestureDetector(
      onTap: () => _onServiceTap(item),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.glassBorder),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, Color.lerp(color, Colors.black, 0.22)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Icon(item.icon, color: Colors.white, size: 23),
            ),
            const SizedBox(height: 8),
            Text(
              isBn ? item.nameBn : item.nameEn,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600, height: 1.15),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 40 * index))
        .fadeIn(duration: 280.ms)
        .scale(begin: const Offset(0.85, 0.85));
  }

  // ── Skeleton loaders ──────────────────────────────────────────────

  Widget _buildSkeletonProviderRow() {
    return SizedBox(
      height: 160,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Container(
            width: 160,
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder, width: 1.5),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(duration: 600.ms),
        ),
      ),
    );
  }

  // ── Featured providers ────────────────────────────────────────────

  Widget _buildFeaturedProviders() {
    if (_providers.isEmpty) return const SizedBox(height: 8);
    return SizedBox(
      height: 160,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _providers.length,
        itemBuilder: (_, i) => _buildProviderCard(_providers[i], i),
      ),
    );
  }

  Widget _buildProviderCard(NearbyProviderModel provider, int index) {
    final badge = _badgeLabel(provider.level);
    final kind = provider.serviceKinds.isNotEmpty ? provider.serviceKinds.first : '';
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(providerId: provider.id, kind: kind),
      )),
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: GlassCard(
          width: 160,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(gradient: AppColors.blueGradient, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        provider.name.isNotEmpty ? provider.name[0].toUpperCase() : '?',
                        style: const TextStyle(color: AppColors.ivory, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(gradient: AppColors.fuchsiaGradient, borderRadius: BorderRadius.circular(8)),
                      child: Text(badge, style: const TextStyle(color: AppColors.ivory, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(provider.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(kind, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (provider.rating != null) ...[
                    const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 14),
                    const SizedBox(width: 4),
                    Text(provider.rating!.toStringAsFixed(1), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                  const Spacer(),
                  if (provider.distanceKm != null)
                    Text('${provider.distanceKm!.toStringAsFixed(1)} km', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ],
          ),
        ).animate(delay: Duration(milliseconds: 100 * index)).fadeIn().slideX(begin: 0.2),
      ),
    );
  }

  String? _badgeLabel(String? level) {
    switch (level?.toUpperCase()) {
      case 'GOLD':
      case 'PLATINUM':
        return 'সেরা';
      case 'SILVER':
        return 'যাচাইকৃত';
      default:
        return null;
    }
  }
}
