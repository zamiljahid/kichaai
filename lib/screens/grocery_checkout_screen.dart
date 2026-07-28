import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import '../core/network/api_client.dart';
import '../models/groceries_model.dart';
import '../services/groceries_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

class GroceryCheckoutScreen extends StatefulWidget {
  final String userId;

  const GroceryCheckoutScreen({super.key, required this.userId});

  @override
  State<GroceryCheckoutScreen> createState() => _GroceryCheckoutScreenState();
}

const _paymentMethods = [
  (code: 'cash_on_delivery', label: 'ক্যাশ অন ডেলিভারি'),
  (code: 'wallet', label: 'ওয়ালেট'),
  (code: 'bkash', label: 'বিকাশ'),
  (code: 'nagad', label: 'নগদ'),
];

class _GroceryCheckoutScreenState extends State<GroceryCheckoutScreen> {
  final _addressController = TextEditingController();
  GroceryCartModel? _cart;
  List<GroceryHubModel> _hubs = [];
  GroceryHubModel? _selectedHub;
  bool _isLoading = true;
  bool _isPlacing = false;
  String _paymentMethod = 'cash_on_delivery';
  // pickup: collect at the hub yourself. delivery: KiChaai delivers, cash on
  // receipt by default — customers want to inspect before paying.
  String _fulfillmentMethod = 'delivery';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      double? lat, lon;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        );
        lat = pos.latitude;
        lon = pos.longitude;
      } catch (_) {
        // No permission/GPS — hub list still loads, just not sorted by distance.
      }
      final results = await Future.wait([
        GroceriesService.instance.getCart(widget.userId),
        GroceriesService.instance.listHubs(lat: lat, lon: lon),
      ]);
      if (mounted) {
        setState(() {
          _cart = results[0] as GroceryCartModel;
          _hubs = results[1] as List<GroceryHubModel>;
          _selectedHub = _hubs.isNotEmpty ? _hubs.first : null; // nearest, if geo worked
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(ApiClient.mapError(e).messageBn);
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: AppColors.ivory)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _placeOrder() async {
    if (_selectedHub == null) {
      _showError('একটি হাব বেছে নিন');
      return;
    }
    final address = _addressController.text.trim();
    if (_fulfillmentMethod == 'delivery' && address.isEmpty) {
      _showError('ডেলিভারি ঠিকানা দিন');
      return;
    }
    if (_cart == null || _cart!.isEmpty) {
      _showError('কার্ট খালি');
      return;
    }
    setState(() => _isPlacing = true);
    try {
      await GroceriesService.instance.checkout(
        userId: widget.userId,
        hubId: _selectedHub!.id,
        fulfillmentMethod: _fulfillmentMethod,
        deliveryAddress: _fulfillmentMethod == 'delivery' ? address : null,
        paymentMethod: _paymentMethod,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _fulfillmentMethod == 'pickup'
              ? 'অর্ডার দেওয়া হয়েছে! হাব থেকে সংগ্রহ করুন।'
              : 'অর্ডার দেওয়া হয়েছে!',
          style: const TextStyle(color: AppColors.ivory, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      _showError(ApiClient.mapError(e).messageBn);
      if (mounted) setState(() => _isPlacing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
                    : (_cart == null || _cart!.isEmpty)
                        ? const Center(child: Text('কার্ট খালি', style: TextStyle(color: AppColors.textMuted)))
                        : _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final cart = _cart!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('অর্ডার সারসংক্ষেপ', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                ...cart.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                                Text('${item.quantity.toStringAsFixed(0)}x ৳${item.unitPrice.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              ],
                            ),
                          ),
                          Text('৳${item.subtotal.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )),
                const Divider(color: AppColors.glassBorder),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('মোট', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('৳${cart.totalAmount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('হাব বেছে নিন', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('আপনার অর্ডার এই হাব থেকেই প্রস্তুত হয়ে সংগ্রহ/ডেলিভারি হবে', style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                const SizedBox(height: 12),
                if (_hubs.isEmpty)
                  const Text('কোনো হাব পাওয়া যায়নি', style: TextStyle(color: AppColors.textMuted, fontSize: 13))
                else
                  ..._hubs.map((h) {
                    final selected = _selectedHub?.id == h.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedHub = h),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.deepBlue.withOpacity(0.1) : AppColors.glassWhite,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: selected ? AppColors.deepBlue : AppColors.glassBorder, width: selected ? 1.5 : 1),
                          ),
                          child: Row(
                            children: [
                              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? AppColors.deepBlue : AppColors.textMuted, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(h.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                                    Text(h.address, style: const TextStyle(color: AppColors.textMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              if (h.distanceKm != null)
                                Text('${h.distanceKm!.toStringAsFixed(1)} কিমি', style: const TextStyle(color: AppColors.deepBlue, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 80.ms),
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('কীভাবে পেতে চান', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _fulfillmentTile('pickup', Icons.storefront_rounded, 'নিজে সংগ্রহ', 'হাব থেকে নিজে নিয়ে যান')),
                  const SizedBox(width: 10),
                  Expanded(child: _fulfillmentTile('delivery', Icons.local_shipping_rounded, 'ডেলিভারি', 'বাসায় পৌঁছে দেওয়া হবে')),
                ]),
                if (_fulfillmentMethod == 'delivery') ...[
                  const SizedBox(height: 14),
                  const Text('ডেলিভারি ঠিকানা', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _addressController,
                    maxLines: 3,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'বাড়ি নম্বর, রাস্তা, এলাকা...',
                      prefixIcon: Icon(Icons.location_on_rounded, color: AppColors.textMuted),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.deepBlue.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                    child: const Text('সাধারণত অর্ডারের পরের দিন হাবে পণ্য পৌঁছে যায় — তখন গিয়ে সংগ্রহ করতে পারবেন।', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4)),
                  ),
                ],
              ],
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 120.ms),
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('পেমেন্ট পদ্ধতি', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _paymentMethods.map((m) {
                    final selected = _paymentMethod == m.code;
                    return GestureDetector(
                      onTap: () => setState(() => _paymentMethod = m.code),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: selected ? AppColors.blueGradient : null,
                          color: selected ? null : AppColors.glassWhite,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: selected ? Colors.transparent : AppColors.glassBorder),
                        ),
                        child: Text(m.label, style: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 160.ms),
          const SizedBox(height: 24),
          GlassButton(
            label: 'অর্ডার দিন — ৳${cart.totalAmount.toStringAsFixed(0)}',
            isLoading: _isPlacing,
            onPressed: _placeOrder,
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
        ],
      ),
    );
  }

  Widget _fulfillmentTile(String value, IconData icon, String label, String sub) {
    final selected = _fulfillmentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _fulfillmentMethod = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.blueGradient : null,
          color: selected ? null : AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Colors.transparent : AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? Colors.white : AppColors.deepBlue, size: 20),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
            Text(sub, style: TextStyle(color: selected ? Colors.white.withOpacity(0.85) : AppColors.textMuted, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder, width: 1.5)),
              child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('চেকআউট', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Checkout', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ],
      ),
    );
  }
}
