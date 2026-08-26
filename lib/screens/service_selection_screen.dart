import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import 'courses_screen.dart';
import 'grocery_screen.dart';
import 'job_request_screen.dart';
import 'laundry_screen.dart';
import 'lawyer_consultation_screen.dart';
import 'match_request_screen.dart';
import 'mess_screen.dart';
import 'provider_browse_screen.dart';
import 'scrap_screen.dart';
import 'service_mode_hub_screen.dart';
import 'skill_share_screen.dart';

// Same override as home_screen.dart's _catalogCodeFor — these two serviceKind
// values don't match the catalog's ServiceType.code 1:1.
const _kCatalogCodeOverrides = {'tutor': 'home_tutor', 'grocery': 'groceries_hub'};
String _catalogCodeFor(String kind) => _kCatalogCodeOverrides[kind] ?? kind;

class _Service {
  final String label;
  final String sublabel;
  final String serviceKind;
  final IconData icon;
  final Color color;
  final String flow;
  final String? imagePath;

  const _Service({
    required this.label,
    required this.sublabel,
    required this.serviceKind,
    required this.icon,
    required this.color,
    required this.flow,
    this.imagePath,
  });
}

const _kServicesImageDir = 'assets/images/services';

const _services = [
  _Service(label: 'ইলেকট্রিশিয়ান', sublabel: 'Technician', serviceKind: 'technician', icon: Icons.electrical_services_rounded, color: Color(0xFF106EBE), flow: 'dispatch', imagePath: '$_kServicesImageDir/technician.png'),
  _Service(label: 'কেয়ারগিভার', sublabel: 'Caregiver', serviceKind: 'caregiver', icon: Icons.health_and_safety_rounded, color: Color(0xFF2E7D32), flow: 'dispatch', imagePath: '$_kServicesImageDir/care.png'),
  _Service(label: 'আইনজীবী', sublabel: 'Lawyer', serviceKind: 'lawyer', icon: Icons.gavel_rounded, color: Color(0xFF6A1B9A), flow: 'lawyer'),
  _Service(label: 'মেকআপ আর্টিস্ট', sublabel: 'Makeup Artist', serviceKind: 'makeup_artist', icon: Icons.face_retouching_natural_rounded, color: Color(0xFFD8125B), flow: 'dispatch', imagePath: '$_kServicesImageDir/makeup.png'),
  _Service(label: 'ফটোগ্রাফার', sublabel: 'Photographer', serviceKind: 'photographer', icon: Icons.camera_alt_rounded, color: Color(0xFF00838F), flow: 'dispatch', imagePath: '$_kServicesImageDir/photographer.png'),
  _Service(label: 'সিনেমাটোগ্রাফার', sublabel: 'Cinematographer', serviceKind: 'cinematographer', icon: Icons.videocam_rounded, color: Color(0xFFE65100), flow: 'dispatch', imagePath: '$_kServicesImageDir/cinematographer.png'),
  _Service(label: 'কাজের লোক', sublabel: 'Task Runner', serviceKind: 'task_runner', icon: Icons.handyman_rounded, color: Color(0xFF0277BD), flow: 'dispatch', imagePath: '$_kServicesImageDir/task.png'),
  _Service(label: 'স্ক্র্যাপ কালেকশন', sublabel: 'Scrap Collection', serviceKind: 'scrap_collection', icon: Icons.recycling_rounded, color: Color(0xFF558B2F), flow: 'scrap', imagePath: '$_kServicesImageDir/scrap.png'),
  _Service(label: 'হোম টিউটর', sublabel: 'Home Tutor', serviceKind: 'tutor', icon: Icons.school_rounded, color: Color(0xFF4527A0), flow: 'matchmaking', imagePath: '$_kServicesImageDir/tutor.png'),
  _Service(label: 'পেট কেয়ার', sublabel: 'Pet Care', serviceKind: 'pet_care', icon: Icons.pets_rounded, color: Color(0xFF00695C), flow: 'matchmaking', imagePath: '$_kServicesImageDir/petcare.png'),
  _Service(label: 'গৃহকর্মী সেবা', sublabel: 'Household Help', serviceKind: 'helping_hand', icon: Icons.cleaning_services_rounded, color: Color(0xFF6D4C41), flow: 'matchmaking'),
  _Service(label: 'মেস / আবাসন', sublabel: 'Mess & Housing', serviceKind: 'mess_finder', icon: Icons.home_work_rounded, color: Color(0xFF37474F), flow: 'mess', imagePath: '$_kServicesImageDir/mess.png'),
  _Service(label: 'স্কিল শেয়ার', sublabel: 'Skill Share', serviceKind: 'skill_share', icon: Icons.auto_awesome_rounded, color: Color(0xFF0277BD), flow: 'skill_share', imagePath: '$_kServicesImageDir/skill_share.png'),
  _Service(label: 'মাইক্রো লার্নিং', sublabel: 'Micro Learning', serviceKind: 'micro_learning', icon: Icons.play_circle_outline_rounded, color: Color(0xFFAD1457), flow: 'learning', imagePath: '$_kServicesImageDir/micro.png'),
  _Service(label: 'গ্রোসারি', sublabel: 'Groceries', serviceKind: 'grocery', icon: Icons.shopping_basket_rounded, color: Color(0xFF4E342E), flow: 'grocery', imagePath: '$_kServicesImageDir/groceries.png'),
  _Service(label: 'লন্ড্রি', sublabel: 'Laundry', serviceKind: 'laundry', icon: Icons.local_laundry_service_rounded, color: Color(0xFF0288D1), flow: 'laundry'),
  _Service(label: 'রান্না অন-ডিমান্ড', sublabel: 'Cook On-Demand', serviceKind: 'cook', icon: Icons.soup_kitchen_rounded, color: Color(0xFFEF6C00), flow: 'cook'),
  _Service(label: 'কমিউট পার্টনার', sublabel: 'Commute Partner', serviceKind: 'commute', icon: Icons.directions_car_filled_rounded, color: Color(0xFF303F9F), flow: 'commute'),
];

class ServiceSelectionScreen extends StatefulWidget {
  const ServiceSelectionScreen({super.key});

  @override
  State<ServiceSelectionScreen> createState() => _ServiceSelectionScreenState();
}

class _ServiceSelectionScreenState extends State<ServiceSelectionScreen> {
  // Admin-disabled codes (catalog-service's ServiceType.isActive kill switch) —
  // empty until loaded, so a slow/failed fetch never hides anything.
  Set<String> _disabledCodes = {};

  @override
  void initState() {
    super.initState();
    _loadDisabledServices();
  }

  Future<void> _loadDisabledServices() async {
    try {
      final types = await CatalogService.instance.getServiceTypes();
      final disabled = {for (final t in types) if (!t.isActive) t.code};
      if (mounted) setState(() => _disabledCodes = disabled);
    } catch (_) {}
  }

  void _navigate(BuildContext context, _Service s) {
    final nav = Navigator.of(context);
    switch (s.flow) {
      case 'dispatch':
        nav.push(MaterialPageRoute(
          builder: (_) => JobRequestScreen(serviceKind: s.serviceKind, serviceLabel: s.label),
        ));
      case 'lawyer':
        nav.push(MaterialPageRoute(builder: (_) => const LawyerConsultationScreen()));
      case 'matchmaking':
        // Home Tutor lands straight on the request form (open broadcast) — browsing existing
        // providers first was the only path in, even when a customer just wants to post what
        // they need. Other matchmaking kinds keep the browse-first flow for now.
        nav.push(MaterialPageRoute(
          builder: (_) => s.serviceKind == 'tutor'
              ? const MatchRequestScreen(kind: 'tutor')
              : ProviderBrowseScreen(kind: s.serviceKind, label: s.label),
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
      // See home_screen.dart's matching case — the hub forks instant vs scheduled/recurring.
      case 'cook':
        nav.push(MaterialPageRoute(builder: (_) => ServiceModeHubScreen.cook()));
      case 'commute':
        nav.push(MaterialPageRoute(builder: (_) => ServiceModeHubScreen.ride()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBn = context.watch<LanguageNotifier>().isBengali;
    final visible = _disabledCodes.isEmpty
        ? _services
        : _services.where((s) => !_disabledCodes.contains(_catalogCodeFor(s.serviceKind))).toList();
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, isBn),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: GridView.builder(
                    itemCount: visible.length,
                    // Max-extent keeps each card a sensible width on any screen
                    // (fixed 2-column made cards huge on wide displays).
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 260,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 74,
                    ),
                    itemBuilder: (context, i) => _buildCard(context, visible[i], i, isBn),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isBn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder, width: 1.5),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isBn ? 'সকল সেবা বিভাগ' : 'All Service Categories', style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
              Text(isBn ? 'All Service Categories' : 'সকল সেবা বিভাগ', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  Widget _buildCard(BuildContext context, _Service s, int index, bool isBn) {
    return GestureDetector(
      onTap: () => _navigate(context, s),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder, width: 1.5),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: s.imagePath == null
                    ? LinearGradient(
                        colors: [s.color, Color.lerp(s.color, Colors.black, 0.22)!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: s.imagePath != null ? AppColors.glassWhite : null,
                borderRadius: BorderRadius.circular(14),
                border: s.imagePath != null ? Border.all(color: AppColors.glassBorder) : null,
                boxShadow: s.imagePath == null
                    ? [BoxShadow(color: s.color.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))]
                    : null,
              ),
              child: s.imagePath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.asset(s.imagePath!, fit: BoxFit.cover),
                    )
                  : Icon(s.icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isBn ? s.label : s.sublabel,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isBn ? s.sublabel : s.label,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: s.color.withValues(alpha: 0.7), size: 13),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 40 * index))
        .fadeIn(duration: 300.ms)
        .slideX(begin: 0.05);
  }
}
