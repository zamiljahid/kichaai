import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/onboarding_service.dart';
import '../services/auth_service.dart';
import '../widgets/availability_calendar.dart';
import '../theme/app_theme.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  List<dynamic> _portfolio = [];
  bool _isLoading = true;
  bool _isUploading = false;
  final _picker = ImagePicker();
  final _captionCtrl = TextEditingController();

  // Which onboarding profile (photography vs cinema) this provider's images
  // attach to — auto-detected from their approved services. Null means
  // neither, so uploading is disabled (nothing to attach the image to).
  String? _serviceType;
  String? _userId;

  // Wall header — name/rating/level, same fields the customer-facing browse
  // card shows, so a provider can see exactly what their public profile looks like.
  String? _name;
  double? _rating;
  String? _level;
  String? _avatarUrl;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadHeader();
    await _load();
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHeader() async {
    try {
      _userId = await ApiClient.getUserId();
      final me = await AuthService.instance.getMeRaw();
      final pp = me['providerProfile'] as Map<String, dynamic>?;
      final services = await OnboardingService.instance.getMyServices();
      final ids = services.map((s) => s['serviceTypeId'] as String? ?? '').toSet();
      if (!mounted) return;
      setState(() {
        _name = (pp?['displayName'] as String?) ?? (me['fullName'] as String?);
        _rating = (pp?['avgRating'] as num?)?.toDouble();
        _level = pp?['level'] as String?;
        _avatarUrl = (pp?['profilePhotoUrl'] as String?) ?? (me['avatarUrl'] as String?);
        _serviceType = ids.contains('st_photographer')
            ? 'photography'
            : ids.contains('st_cinematographer')
                ? 'cinema'
                : null;
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await OnboardingService.instance.listPortfolioImages(serviceType: _serviceType);
      if (mounted) setState(() { _portfolio = list; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addImage() async {
    if (_serviceType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isBn ? 'এই ফিচারটি ফটোগ্রাফার/সিনেমাটোগ্রাফারদের জন্য' : 'This feature is for photographers/cinematographers', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1200);
    if (image == null) return;

    _captionCtrl.clear();
    final caption = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'ছবির বিবরণ' : 'Image Details', style: const TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: _captionCtrl,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: _isBn ? 'ক্যাপশন (ঐচ্ছিক)' : 'Caption (optional)',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.glassWhite,
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(_isBn ? 'বাদ দিন' : 'Skip', style: const TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, _captionCtrl.text), child: Text(_isBn ? 'আপলোড' : 'Upload', style: const TextStyle(color: AppColors.deepBlue))),
        ],
      ),
    );
    if (caption == null) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await File(image.path).readAsBytes();
      final b64 = base64Encode(bytes);
      final fileUrl = await OnboardingService.instance.uploadFile(
        fileBase64: b64,
        fileName: 'portfolio_${DateTime.now().millisecondsSinceEpoch}.jpg',
        mimeType: 'image/jpeg',
      );
      await OnboardingService.instance.uploadPortfolioImage(
        imageUrl: fileUrl,
        serviceType: _serviceType!,
        caption: caption,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isBn ? 'আপলোড ব্যর্থ হয়েছে' : 'Upload failed', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _setCover(String id) async {
    try {
      await OnboardingService.instance.setCoverPortfolioImage(id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isBn ? 'কভার ছবি সেট হয়েছে' : 'Cover image set', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (_) {}
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'ছবি মুছুন?' : 'Delete image?', style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(_isBn ? 'এই ছবিটি মুছে ফেলতে চান?' : 'Do you want to delete this image?', style: const TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'বাতিল' : 'Cancel', style: const TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_isBn ? 'মুছুন' : 'Delete', style: const TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await OnboardingService.instance.deletePortfolioImage(id);
      await _load();
    } catch (_) {}
  }

  void _showImageOptions(Map<String, dynamic> item) {
    final id = item['id'] as String? ?? '';
    final isCover = item['isCover'] as bool? ?? false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: AppColors.bgMid,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                if (!isCover)
                  ListTile(
                    leading: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                    title: Text(_isBn ? 'কভার হিসেবে সেট করুন' : 'Set as cover', style: const TextStyle(color: AppColors.textPrimary)),
                    onTap: () { Navigator.pop(ctx); _setCover(id); },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                  title: Text(_isBn ? 'মুছুন' : 'Delete', style: const TextStyle(color: Color(0xFFEF4444))),
                  onTap: () { Navigator.pop(ctx); _delete(id); },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_isBn ? 'পোর্টফোলিও' : 'Portfolio', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : RefreshIndicator(
              color: AppColors.deepBlue,
              backgroundColor: AppColors.bgMid,
              onRefresh: _init,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 20),
                  Text(_isBn ? 'কাজের নমুনা (পোর্টফোলিও)' : 'Work Samples (Portfolio)',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _buildPortfolioGrid(),
                  if (_userId != null) ...[
                    const SizedBox(height: 24),
                    Text(_isBn ? 'আসন্ন সময়সূচী' : 'Upcoming Schedule',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    AvailabilityCalendar(providerId: _userId!, interactive: true),
                  ],
                ],
              ),
            ),
      floatingActionButton: _isUploading
          ? FloatingActionButton(
              onPressed: null,
              backgroundColor: AppColors.deepBlue,
              child: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            )
          : FloatingActionButton(
              onPressed: _addImage,
              backgroundColor: AppColors.deepBlue,
              child: const Icon(Icons.add_a_photo_rounded, color: Colors.white),
            ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder, width: 1.2),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.deepBlue,
            backgroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty) ? NetworkImage(_avatarUrl!) : null,
            child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                ? Text((_name?.isNotEmpty ?? false) ? _name![0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name ?? '—', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 15),
                    const SizedBox(width: 3),
                    Text(_rating == null ? '—' : _rating!.toStringAsFixed(2),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                    if (_level != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.glassWhite,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(_level!, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioGrid() {
    if (_portfolio.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        alignment: Alignment.center,
        child: Column(children: [
          const Icon(Icons.photo_library_outlined, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 10),
          Text(_isBn ? 'পোর্টফোলিও খালি' : 'Portfolio is empty', style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
          const SizedBox(height: 6),
          TextButton(onPressed: _addImage, child: Text(_isBn ? 'ছবি যোগ করুন' : 'Add Image', style: const TextStyle(color: AppColors.deepBlue))),
        ]),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _portfolio.length,
      itemBuilder: (ctx, i) {
        final item = _portfolio[i] as Map<String, dynamic>;
        final isCover = item['isCover'] as bool? ?? false;
        final imageUrl = item['imageUrl'] as String? ?? '';
        return GestureDetector(
          onTap: () => _showImageOptions(item),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: AppColors.bgMid, child: const Icon(Icons.image_outlined, color: AppColors.textMuted))),
                  if (isCover)
                    Positioned(top: 8, right: 8, child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star_rounded, color: Colors.white, size: 12),
                        const SizedBox(width: 2),
                        Text(_isBn ? 'কভার' : 'Cover', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      ]),
                    )),
                  if (item['caption'] != null && (item['caption'] as String).isNotEmpty)
                    Positioned(bottom: 0, left: 0, right: 0, child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
                      child: Text(item['caption'] as String, style: const TextStyle(color: Colors.white, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    )),
                ],
              ),
            ),
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 50));
      },
    );
  }
}
