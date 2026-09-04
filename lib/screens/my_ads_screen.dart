import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/property_model.dart';
import 'post_mess_screen.dart';
import '../widgets/animated_background.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// "আমার বিজ্ঞাপন" — every mess/house listing the logged-in user has posted.
/// Edit, delete, or temporarily hide (isActive=false, the "seats full" case).
class MyAdsScreen extends StatefulWidget {
  const MyAdsScreen({super.key});

  @override
  State<MyAdsScreen> createState() => _MyAdsScreenState();
}

class _MyAdsScreenState extends State<MyAdsScreen> {
  final _dio = ApiClient.instance.dio;
  List<PropertyListing> _ads = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _busy = {}; // rows with an in-flight toggle/delete
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final res = await _dio.get('/auth/properties/me', queryParameters: {'limit': 100});
      final data = res.data;
      final raw = data is List ? data : (data['items'] ?? data['data'] ?? data['results'] ?? []);
      final list = (raw as List)
          .map((e) => PropertyListing.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() { _ads = list; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = ApiClient.mapError(e).messageBn; _isLoading = false; });
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _openPost({PropertyListing? existing}) async {
    final changed = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => PostPropertyScreen(existing: existing)));
    if (changed == true) _fetch();
  }

  /// সাময়িকভাবে বন্ধ — hides from search WITHOUT deleting (seats full).
  Future<void> _toggleActive(PropertyListing ad) async {
    setState(() => _busy.add(ad.id));
    try {
      await _dio.patch('/auth/properties/${ad.id}', data: {'isActive': !ad.isActive});
      await _fetch();
      _snack(ad.isActive
          ? (_isBn ? 'বিজ্ঞাপনটি সাময়িকভাবে বন্ধ হয়েছে' : 'Listing temporarily hidden')
          : (_isBn ? 'বিজ্ঞাপনটি আবার চালু হয়েছে' : 'Listing is live again'));
    } catch (e) {
      _snack(ApiClient.mapError(e).messageBn, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(ad.id));
    }
  }

  Future<void> _delete(PropertyListing ad) async {
    final colors = Theme.of(context).colorScheme;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_isBn ? 'বিজ্ঞাপন মুছবেন?' : 'Delete listing?',
            style: TextStyle(color: colors.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
            _isBn
                ? '"${ad.messName}" মুছে ফেলা হবে। সিট ভরে গেলে মুছে না ফেলে "সাময়িকভাবে বন্ধ" করাই ভালো।'
                : '"${ad.messName}" will be removed. If it is just full, "temporarily hide" is better than deleting.',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isBn ? 'বাতিল' : 'Cancel', style: TextStyle(color: colors.outline)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isBn ? 'মুছে ফেলুন' : 'Delete',
                style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (sure != true) return;
    setState(() => _busy.add(ad.id));
    try {
      await _dio.delete('/auth/properties/${ad.id}');
      if (mounted) setState(() => _ads.removeWhere((a) => a.id == ad.id));
      _snack(_isBn ? 'বিজ্ঞাপন মুছে ফেলা হয়েছে' : 'Listing deleted');
    } catch (e) {
      _snack(ApiClient.mapError(e).messageBn, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(ad.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return AnimatedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(_isBn ? 'আমার বিজ্ঞাপন' : 'My listings',
              style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _body(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openPost(),
          backgroundColor: colors.primary,
          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
          label: Text(_isBn ? 'নতুন বিজ্ঞাপন' : 'New listing',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
        ),
      ),
    );
  }

  Widget _body() {
    final colors = Theme.of(context).colorScheme;
    if (_isLoading) return Center(child: CircularProgressIndicator(color: colors.primary));
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, color: colors.outline, size: 48),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: colors.outline)),
          const SizedBox(height: 16),
          GestureDetector(onTap: _fetch, child: Text(_isBn ? 'আবার চেষ্টা করুন' : 'Try again',
              style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700))),
        ]),
      ));
    }
    if (_ads.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.home_work_outlined, color: colors.outline, size: 56),
          const SizedBox(height: 14),
          Text(_isBn ? 'এখনো কোনো বিজ্ঞাপন নেই' : 'No listings yet',
              style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
              _isBn
                  ? 'আপনার মেস বা বাসা ভাড়ার বিজ্ঞাপন দিন — হাজারো মানুষ খুঁজছে।'
                  : 'Post your mess or house for rent — thousands are searching.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.outline, fontSize: 13.5, height: 1.5)),
        ]),
      ));
    }
    return RefreshIndicator(
      color: colors.primary,
      backgroundColor: colors.surface,
      onRefresh: _fetch,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: _ads.length,
        itemBuilder: (_, i) => _adCard(_ads[i])
            .animate(delay: (40 * i).ms)
            .fadeIn(duration: 280.ms)
            .slideY(begin: 0.12, curve: Curves.easeOutCubic),
      ),
    );
  }

  Widget _adCard(PropertyListing ad) {
    final colors = Theme.of(context).colorScheme;
    final busy = _busy.contains(ad.id);
    final rentUnit = ad.isMess
        ? (_isBn ? '/সিট' : '/seat')
        : ad.isGarage
            ? (_isBn ? '/দিন' : '/day')
            : (_isBn ? '/মাস' : '/mo');
    final info = ad.isMess
        ? (ad.totalSeats != null ? (_isBn ? '${ad.totalSeats} সিট' : '${ad.totalSeats} seats') : '')
        : ad.isGarage
            ? [
                if (ad.carCapacity != null) _isBn ? '${ad.carCapacity} গাড়ি' : '${ad.carCapacity} cars',
                if (ad.isCovered != null) (ad.isCovered! ? (_isBn ? 'ছাদযুক্ত' : 'covered') : (_isBn ? 'খোলা' : 'open')),
              ].join(' · ')
            : [
                if (ad.bedrooms != null) _isBn ? '${ad.bedrooms} বেড' : '${ad.bedrooms} bed',
                if (ad.bathrooms != null) _isBn ? '${ad.bathrooms} বাথ' : '${ad.bathrooms} bath',
                if (ad.sizeSqft != null) '${ad.sizeSqft} sqft',
              ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72, height: 72,
                child: ad.photosUrls.isNotEmpty
                    ? Image.network(ad.photosUrls.first, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => ColoredBox(
                            color: colors.surfaceContainerHighest,
                            child: Icon(Icons.home_work_rounded, color: colors.outline)))
                    : ColoredBox(
                        color: colors.surfaceContainerHighest,
                        child: Icon(Icons.home_work_rounded, color: colors.outline)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: (ad.isMess ? colors.primary : ad.isGarage ? const Color(0xFF6B7280) : const Color(0xFFB45309)).withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                        ad.isMess ? (_isBn ? 'মেস' : 'Mess') : ad.isGarage ? (_isBn ? 'গ্যারেজ' : 'Garage') : (_isBn ? 'বাসা ভাড়া' : 'House'),
                        style: TextStyle(
                            color: ad.isMess ? colors.primary : ad.isGarage ? const Color(0xFF6B7280) : const Color(0xFFB45309),
                            fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ),
                  if (!ad.isActive) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: colors.outline.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_isBn ? 'বন্ধ আছে' : 'Hidden',
                          style: TextStyle(color: colors.outline, fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ]),
                const SizedBox(height: 5),
                Text(ad.messName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(ad.address, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.outline, fontSize: 12.5)),
                const SizedBox(height: 4),
                Row(children: [
                  if (ad.rent != null)
                    Text('${takaFmt(ad.rent!)}$rentUnit',
                        style: TextStyle(color: colors.onSurface, fontSize: 13.5, fontWeight: FontWeight.w800)),
                  if (ad.rent != null && info.isNotEmpty)
                    Text('  ·  ', style: TextStyle(color: colors.outline, fontSize: 12.5)),
                  Expanded(
                    child: Text(info, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5)),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
        Divider(color: colors.outlineVariant, height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(children: [
            _actionBtn(Icons.edit_outlined, _isBn ? 'সম্পাদনা' : 'Edit',
                busy ? null : () => _openPost(existing: ad)),
            _actionBtn(Icons.delete_outline_rounded, _isBn ? 'মুছে ফেলুন' : 'Delete',
                busy ? null : () => _delete(ad), color: const Color(0xFFEF4444)),
            const Spacer(),
            Text(_isBn ? 'সাময়িকভাবে বন্ধ' : 'Hide temporarily',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
            SizedBox(
              height: 34,
              child: busy
                  ? Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary)))
                  : Switch(
                      value: !ad.isActive,
                      activeColor: const Color(0xFFB45309),
                      onChanged: (_) => _toggleActive(ad),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback? onTap, {Color? color}) {
    final colors = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color ?? colors.onSurfaceVariant),
      label: Text(label, style: TextStyle(
          color: color ?? colors.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }
}
