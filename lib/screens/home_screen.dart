import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../models/dispatch_model.dart';
import '../services/catalog_service.dart';
import '../services/dispatch_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/glass_card.dart';
import '../widgets/service_animation.dart';
import 'courses_screen.dart';
import 'grocery_screen.dart';
import 'job_request_screen.dart';
import 'laundry_screen.dart';
import 'lawyer_consultation_screen.dart';
import 'match_request_screen.dart';
import 'meal_groups_list_screen.dart';
import 'mess_screen.dart';
import 'provider_browse_screen.dart';
import 'provider_profile_screen.dart';
import 'scrap_screen.dart';
import 'service_mode_hub_screen.dart';
import 'service_selection_screen.dart';
import 'skill_share_screen.dart';

class _ServiceItem {
  final String nameBn;
  final String nameEn;
  final IconData icon;
  final String flow;
  final String? kind;
  final String? imagePath;

  const _ServiceItem({
    required this.nameBn,
    required this.nameEn,
    required this.icon,
    required this.flow,
    this.kind,
    this.imagePath,
  });
}

const _kServicesImageDir = 'assets/images/services';

// Matches the backend catalog (GET /catalog/service-types) — the real service
// kinds. Electrician/Plumber/AC/Cleaning are NOT separate kinds; they are task
// categories under `technician`.
const _kServices = [
  _ServiceItem(nameBn: 'টেকনিশিয়ান', nameEn: 'Technician', icon: Icons.build_rounded, flow: 'dispatch', kind: 'technician', imagePath: '$_kServicesImageDir/technician.png'),
  _ServiceItem(nameBn: 'কাজের লোক', nameEn: 'Quick Help', icon: Icons.handyman_rounded, flow: 'dispatch', kind: 'task_runner', imagePath: '$_kServicesImageDir/task.png'),
  _ServiceItem(nameBn: 'কেয়ারগিভার', nameEn: 'Caregiver', icon: Icons.health_and_safety_rounded, flow: 'dispatch', kind: 'caregiver', imagePath: '$_kServicesImageDir/care.png'),
  _ServiceItem(nameBn: 'আইনজীবী', nameEn: 'Lawyer', icon: Icons.gavel_rounded, flow: 'lawyer', kind: 'lawyer'),
  _ServiceItem(nameBn: 'ফটোগ্রাফার', nameEn: 'Photographer', icon: Icons.camera_alt_rounded, flow: 'dispatch', kind: 'photographer', imagePath: '$_kServicesImageDir/photographer.png'),
  _ServiceItem(nameBn: 'সিনেমাটোগ্রাফার', nameEn: 'Cinematographer', icon: Icons.videocam_rounded, flow: 'dispatch', kind: 'cinematographer', imagePath: '$_kServicesImageDir/cinematographer.png'),
  _ServiceItem(nameBn: 'মেকআপ আর্টিস্ট', nameEn: 'Makeup Artist', icon: Icons.face_retouching_natural_rounded, flow: 'dispatch', kind: 'makeup_artist', imagePath: '$_kServicesImageDir/makeup.png'),
  _ServiceItem(nameBn: 'হোম টিউটর', nameEn: 'Home Tutor', icon: Icons.school_rounded, flow: 'matchmaking', kind: 'tutor', imagePath: '$_kServicesImageDir/tutor.png'),
  _ServiceItem(nameBn: 'পেট কেয়ার', nameEn: 'Pet Care', icon: Icons.pets_rounded, flow: 'matchmaking', kind: 'pet_care', imagePath: '$_kServicesImageDir/petcare.png'),
  _ServiceItem(nameBn: 'গৃহকর্মী সেবা', nameEn: 'Household Help', icon: Icons.cleaning_services_rounded, flow: 'matchmaking', kind: 'helping_hand'),
  _ServiceItem(nameBn: 'মেস / আবাসন', nameEn: 'Mess & Housing', icon: Icons.home_work_rounded, flow: 'mess', kind: 'mess_finder', imagePath: '$_kServicesImageDir/mess.png'),
  _ServiceItem(nameBn: 'স্ক্র্যাপ', nameEn: 'Scrap', icon: Icons.recycling_rounded, flow: 'scrap', kind: 'scrap_collection', imagePath: '$_kServicesImageDir/scrap.png'),
  _ServiceItem(nameBn: 'স্কিল শেয়ার', nameEn: 'Skill Share', icon: Icons.auto_awesome_rounded, flow: 'skill_share', kind: 'skill_share', imagePath: '$_kServicesImageDir/skill_share.png'),
  _ServiceItem(nameBn: 'মাইক্রো লার্নিং', nameEn: 'Micro Learning', icon: Icons.play_circle_outline_rounded, flow: 'learning', kind: 'micro_learning', imagePath: '$_kServicesImageDir/micro.png'),
  _ServiceItem(nameBn: 'গ্রোসারি', nameEn: 'Grocery', icon: Icons.local_grocery_store_rounded, flow: 'grocery', kind: 'grocery', imagePath: '$_kServicesImageDir/groceries.png'),
  _ServiceItem(nameBn: 'লন্ড্রি', nameEn: 'Laundry', icon: Icons.local_laundry_service_rounded, flow: 'laundry', kind: 'laundry'),
  _ServiceItem(nameBn: 'রান্না অন-ডিমান্ড', nameEn: 'Cook On-Demand', icon: Icons.soup_kitchen_rounded, flow: 'cook', kind: 'cook'),
  _ServiceItem(nameBn: 'কমিউট পার্টনার', nameEn: 'Commute Partner', icon: Icons.directions_car_filled_rounded, flow: 'commute', kind: 'commute'),
];

// Most `_ServiceItem.kind` values are already the catalog's `ServiceType.code`
// (technician, lawyer, photographer, …) — these two aren't, so the admin
// kill switch (GET /catalog/service-types → isActive) needs the real code to
// match against.
const _kCatalogCodeOverrides = {'tutor': 'home_tutor', 'grocery': 'groceries_hub'};
String _catalogCodeFor(String kind) => _kCatalogCodeOverrides[kind] ?? kind;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();

  List<NearbyProviderModel> _providers = [];
  bool _isLoading = true;

  // Codes admin has switched off (see catalog-service's ServiceType.isActive
  // kill switch) — empty until loaded, so a slow/failed fetch never hides
  // anything (fail-open, not fail-closed).
  Set<String> _disabledCodes = {};

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
    _loadDisabledServices();
  }

  /// Independent of the providers load above — a catalog hiccup shouldn't
  /// block the rest of the home screen, and vice versa.
  Future<void> _loadDisabledServices() async {
    try {
      final types = await CatalogService.instance.getServiceTypes();
      final disabled = {for (final t in types) if (!t.isActive) t.code};
      if (mounted) setState(() => _disabledCodes = disabled);
    } catch (_) {
      // Fail-open — see _disabledCodes' doc comment.
    }
  }

  Color _colorForIndex(int index) => _colorPalette[index % _colorPalette.length];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _loadData,
      color: colors.primary,
      backgroundColor: colors.surface,
      child: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(child: _buildSearchBar(context)),
          SliverToBoxAdapter(child: _buildActiveRequest(context)),
          SliverToBoxAdapter(child: _buildMealGroupBanner(context)),
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
    final colors = Theme.of(context).colorScheme;
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
              Text(strings.greeting, style: TextStyle(color: colors.outline, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                strings.homeQuestion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurface, fontSize: 21, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: colors.onSurface),
            decoration: InputDecoration(
              hintText: strings.searchHint,
              prefixIcon: Icon(Icons.search_rounded, color: colors.outline),
              suffixIcon: Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: AppGradients.primary(colors),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  strings.filterLabel,
                  style: TextStyle(
                    color: colors.onPrimary,
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
    final colors = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ServiceSelectionScreen()),
        ),
        child: GlassCard(
        padding: const EdgeInsets.all(16),
        glassColor: colors.primary.withValues(alpha: 0.08),
        borderColor: colors.primary.withValues(alpha: 0.20),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: AppGradients.primary(colors),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: colors.primary.withOpacity(0.4), blurRadius: 12),
                ],
              ),
              child: Icon(Icons.add_circle_rounded, color: colors.onPrimary, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.newRequest,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Post a new service request',
                    style: TextStyle(color: colors.outline, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: colors.primary, size: 16),
          ],
        ),
      ),
      ),
    ).animate(delay: 200.ms).fadeIn().slideX(begin: -0.1);
  }

  // Deliberately styled distinctly from every other home-screen card (warm marigold
  // gradient + a subtle shimmer sweep) — this is the daily-open retention feature, so
  // it needs to catch the eye every single time, not blend into the category grid.
  Widget _buildMealGroupBanner(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MealGroupsListScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppGradients.accent(colors),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: colors.secondary.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              const Text('🍛', style: TextStyle(fontSize: 34))
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(end: 1.15, duration: 900.ms, curve: Curves.easeInOut),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'মিল গ্রুপ — বাসার মিল হিসাব',
                      style: TextStyle(color: colors.onPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'প্রতিদিন লাঞ্চ-ডিনার টিক দিন, বাজার খরচ ভাগ করুন — ফ্রি',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: colors.onPrimary, size: 16),
            ],
          ),
        ),
      ),
    )
        .animate(delay: 250.ms)
        .fadeIn(duration: 400.ms)
        .slideX(begin: -0.08)
        .shimmer(duration: 1800.ms, delay: 1200.ms, color: Colors.white.withOpacity(0.35));
  }

  Widget _buildSectionTitle(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Service Categories',
                  style: TextStyle(color: colors.outline, fontSize: 11),
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
              style: TextStyle(color: colors.primary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSectionTitle(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.topProviders, style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
                Text('Top Providers', style: TextStyle(color: colors.outline, fontSize: 11)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProviderBrowseScreen(kind: '', label: 'সব প্রোভাইডার')),
            ),
            child: Text(strings.viewAll, style: TextStyle(color: colors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
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
        // Home Tutor lands straight on the request form (open broadcast) — see
        // service_selection_screen.dart's matching case for the full rationale.
        nav.push(MaterialPageRoute(
          builder: (_) => item.kind == 'tutor'
              ? const MatchRequestScreen(kind: 'tutor')
              : ProviderBrowseScreen(kind: item.kind!, label: item.nameBn),
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
      case 'laundry':
        nav.push(MaterialPageRoute(builder: (_) => const LaundryScreen()));
      // Both kept two halves when they moved onto dispatch — the hub is the fork between
      // "need one now" (broadcast) and the original scheduled/recurring flow.
      case 'cook':
        nav.push(MaterialPageRoute(builder: (_) => ServiceModeHubScreen.cook()));
      case 'commute':
        nav.push(MaterialPageRoute(builder: (_) => ServiceModeHubScreen.ride()));
    }
  }

  Widget _buildCategoryGrid() {
    final isBn = context.read<LanguageNotifier>().isBengali;
    final visible = _disabledCodes.isEmpty
        ? _kServices
        : _kServices.where((s) => !_disabledCodes.contains(_catalogCodeFor(s.kind ?? ''))).toList();
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
        (context, index) => _buildCategoryItem(visible[index], index, isBn),
        childCount: visible.length,
      ),
    );
  }

  Widget _buildCategoryItem(_ServiceItem item, int index, bool isBn) {
    final colors = Theme.of(context).colorScheme;
    final color = _colorForIndex(index);
    return GestureDetector(
      onTap: () => _onServiceTap(item),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ki_chai's animated service artwork where the kind has one; the
            // previous image/gradient-icon tile is the fallback for the four
            // kinds that don't (helping_hand, laundry, cook, commute).
            ServiceAnimation(
              kind: item.kind,
              size: 46,
              fallback: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: item.imagePath == null
                      ? LinearGradient(
                          colors: [color, Color.lerp(color, Colors.black, 0.22)!],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: item.imagePath != null ? colors.surface : null,
                  borderRadius: BorderRadius.circular(14),
                  border: item.imagePath != null ? Border.all(color: colors.outlineVariant) : null,
                  boxShadow: item.imagePath == null
                      ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))]
                      : null,
                ),
                child: item.imagePath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Image.asset(item.imagePath!, fit: BoxFit.cover),
                      )
                    : Icon(item.icon, color: Colors.white, size: 23),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isBn ? item.nameBn : item.nameEn,
              style: TextStyle(color: colors.onSurface, fontSize: 11, fontWeight: FontWeight.w600, height: 1.15),
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
    final colors = Theme.of(context).colorScheme;
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
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.outlineVariant, width: 1.5),
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
    final colors = Theme.of(context).colorScheme;
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
                    decoration: BoxDecoration(gradient: AppGradients.primary(colors), shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        provider.name.isNotEmpty ? provider.name[0].toUpperCase() : '?',
                        style: TextStyle(color: colors.onPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(gradient: AppGradients.accent(colors), borderRadius: BorderRadius.circular(8)),
                      child: Text(badge, style: TextStyle(color: colors.onPrimary, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(provider.name, style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(kind, style: TextStyle(color: colors.outline, fontSize: 11)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (provider.rating != null) ...[
                    const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 14),
                    const SizedBox(width: 4),
                    Text(provider.rating!.toStringAsFixed(1), style: TextStyle(color: colors.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                  const Spacer(),
                  if (provider.distanceKm != null)
                    Text('${provider.distanceKm!.toStringAsFixed(1)} km', style: TextStyle(color: colors.outline, fontSize: 11)),
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
