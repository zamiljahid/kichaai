import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/catalog_model.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_button.dart';

/// Service bundles — a provider packages several of their services together at a
/// discount. The three endpoints have existed since the catalog was built; nothing in
/// the app ever reached them, so no provider could make or see a bundle.
class BundlesScreen extends StatefulWidget {
  const BundlesScreen({super.key});

  @override
  State<BundlesScreen> createState() => _BundlesScreenState();
}

class _BundlesScreenState extends State<BundlesScreen> {
  bool _isBn = true;
  bool _loading = true;
  String? _error;
  List<BundleModel> _bundles = [];
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await CatalogService.instance.getMyBundles();
      if (mounted) {
        setState(() {
          _bundles = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiClient.mapError(e).localized(_isBn);
          _loading = false;
        });
      }
    }
  }

  Future<void> _delete(BundleModel b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'প্যাকেজ মুছবেন?' : 'Delete this bundle?',
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(b.title,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isBn ? 'বাতিল' : 'Cancel',
                style: const TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isBn ? 'মুছুন' : 'Delete',
                style: const TextStyle(
                    color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _deleting.add(b.id));
    try {
      await CatalogService.instance.deleteBundle(b.id);
      if (mounted) setState(() => _bundles.removeWhere((x) => x.id == b.id));
    } catch (e) {
      _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _deleting.remove(b.id));
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_isBn ? 'আমার প্যাকেজ' : 'My bundles',
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textMuted)),
                      const SizedBox(height: 12),
                      GlassButton(
                          label: _isBn ? 'আবার চেষ্টা' : 'Retry',
                          isOutlined: true,
                          onPressed: _load),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.deepBlue,
                  backgroundColor: AppColors.bgMid,
                  onRefresh: _load,
                  child: _bundles.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 100),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              _isBn
                                  ? 'এখনো কোনো প্যাকেজ নেই।\n\nকয়েকটা সেবা একসাথে ছাড়ে দিলে গ্রাহক একবারেই বেশি কাজ দেন।'
                                  : 'No bundles yet.\n\nOffering a few services together at a discount gets customers to book more in one go.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 13.5, height: 1.6),
                            ),
                          ),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: _bundles.length,
                          itemBuilder: (_, i) => _card(_bundles[i], i),
                        ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        backgroundColor: AppColors.deepBlue,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(_isBn ? 'নতুন প্যাকেজ' : 'New bundle',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _card(BundleModel b, int i) {
    final saving = b.originalPrice != null && b.originalPrice! > b.price
        ? b.originalPrice! - b.price
        : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(b.displayTitle(_isBn ? 'bn' : 'en'),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
            if (_deleting.contains(b.id))
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted))
            else
              GestureDetector(
                onTap: () => _delete(b),
                child: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFEF4444), size: 20),
              ),
          ]),
          if ((b.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(b.description!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Text('৳ ${b.price.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            if (b.originalPrice != null)
              Text('৳ ${b.originalPrice!.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      decoration: TextDecoration.lineThrough)),
            const Spacer(),
            if (saving > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x3310B981),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x6610B981)),
                ),
                child: Text(
                    _isBn
                        ? '৳ ${saving.toStringAsFixed(0)} সাশ্রয়'
                        : 'Saves ৳ ${saving.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          if (b.includedItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: b.includedItems
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.glassWhite,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(s.replaceAll('_', ' '),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                      ))
                  .toList(),
            ),
          ],
        ]),
      ).animate(delay: Duration(milliseconds: 40 * i)).fadeIn(duration: 250.ms).slideY(begin: 0.04),
    );
  }

  // ── Create ──────────────────────────────────────────────────────────

  Future<void> _showCreateSheet() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final servicesCtrl = TextEditingController();
    final originalCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    bool saving = false;

    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          filled: true,
          fillColor: AppColors.glassWhite,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.glassBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.glassBorder),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.bgMid,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: AppColors.glassBorder),
            ),
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_isBn ? 'নতুন প্যাকেজ' : 'New bundle',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 14),
                TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    decoration: deco(_isBn ? 'প্যাকেজের নাম *' : 'Bundle name *')),
                const SizedBox(height: 10),
                TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    decoration: deco(_isBn ? 'কী কী থাকছে, সংক্ষেপে *' : 'What it covers *')),
                const SizedBox(height: 10),
                TextField(
                    controller: servicesCtrl,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    decoration: deco(_isBn
                        ? 'সেবার কোড, কমা দিয়ে (technician_electrical, ...)'
                        : 'Service codes, comma separated')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                        controller: originalCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: deco(_isBn ? 'আলাদা দাম ৳ *' : 'Normal price ৳ *')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: deco(_isBn ? 'প্যাকেজ দাম ৳ *' : 'Bundle price ৳ *')),
                  ),
                ]),
                const SizedBox(height: 16),
                GlassButton(
                  label: _isBn ? 'তৈরি করুন' : 'Create',
                  isLoading: saving,
                  onPressed: saving
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final desc = descCtrl.text.trim();
                          final services = servicesCtrl.text
                              .split(',')
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList();
                          final original = double.tryParse(originalCtrl.text.trim());
                          final price = double.tryParse(priceCtrl.text.trim());
                          if (name.isEmpty || desc.isEmpty || services.isEmpty ||
                              original == null || price == null) {
                            _snack(
                                _isBn
                                    ? 'তারকা দেওয়া ঘরগুলো পূরণ করুন'
                                    : 'Fill in every required field',
                                error: true);
                            return;
                          }
                          if (price >= original) {
                            _snack(
                                _isBn
                                    ? 'প্যাকেজ দাম আলাদা দামের চেয়ে কম হতে হবে'
                                    : 'The bundle price must be lower than the normal price',
                                error: true);
                            return;
                          }
                          setSheet(() => saving = true);
                          try {
                            await CatalogService.instance.createBundle(
                              bundleName: name,
                              description: desc,
                              servicesIncluded: services,
                              originalPrice: original,
                              bundlePrice: price,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack(_isBn ? 'প্যাকেজ তৈরি হয়েছে' : 'Bundle created');
                            await _load();
                          } catch (e) {
                            _snack(ApiClient.mapError(e).localized(_isBn), error: true);
                          } finally {
                            setSheet(() => saving = false);
                          }
                        },
                ),
                const SizedBox(height: 8),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
