import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/groceries_model.dart';
import '../services/dispatch_service.dart';
import '../services/groceries_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/policy_agreement_checkbox.dart';
import 'payment_waiting_screen.dart';

class GroceryCheckoutScreen extends StatefulWidget {
  final String userId;

  const GroceryCheckoutScreen({super.key, required this.userId});

  @override
  State<GroceryCheckoutScreen> createState() => _GroceryCheckoutScreenState();
}

const _paymentMethods = [
  (code: 'cash_on_delivery', label: 'ক্যাশ অন ডেলিভারি', labelEn: 'Cash on Delivery'),
  (code: 'wallet', label: 'ওয়ালেট', labelEn: 'Wallet'),
  (code: 'bkash', label: 'বিকাশ', labelEn: 'bKash'),
  (code: 'nagad', label: 'নগদ', labelEn: 'Nagad'),
];

class _GroceryCheckoutScreenState extends State<GroceryCheckoutScreen> {
  final _addressController = TextEditingController();
  GroceryCartModel? _cart;
  List<GroceryHubModel> _hubs = [];
  GroceryHubModel? _selectedHub;
  bool _isLoading = true;
  bool _isPlacing = false;
  bool _isLocating = false;
  double? _deliveryLat;
  double? _deliveryLon;
  String _paymentMethod = 'cash_on_delivery';
  bool _agreedToPolicies = false;
  // pickup: collect at the hub yourself. delivery: KiChaai delivers, cash on
  // receipt by default — customers want to inspect before paying.
  String _fulfillmentMethod = 'delivery';
  bool _isBn = true;

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
        final hubs = results[1] as List<GroceryHubModel>;
        // Already picked on the grocery screen — carry it over so checkout
        // doesn't ask again or silently switch to a different (nearest) hub.
        final remembered = GroceriesService.selectedHub;
        final rememberedStillActive = remembered != null && hubs.any((h) => h.id == remembered.id);
        setState(() {
          _cart = results[0] as GroceryCartModel;
          _hubs = hubs;
          _selectedHub = rememberedStillActive ? remembered : (hubs.isNotEmpty ? hubs.first : null);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(ApiClient.mapError(e).localized(_isBn));
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() => _isLocating = false);
            _showError(_isBn ? 'লোকেশন অনুমতি দেওয়া হয়নি' : 'Location permission not granted');
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _isLocating = false);
          _showError(_isBn ? 'লোকেশন অনুমতি বন্ধ আছে — সেটিংস থেকে চালু করুন' : 'Location permission is off — turn it on in settings');
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final addr = await DispatchService.instance.reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _deliveryLat = pos.latitude;
        _deliveryLon = pos.longitude;
        _isLocating = false;
        if (addr != null && addr.isNotEmpty) _addressController.text = addr;
      });
      if (addr == null) _showError(_isBn ? 'ঠিকানা লেখা যায়নি, তবে লোকেশন সংরক্ষণ হয়েছে — ম্যানুয়ালি লিখুন' : 'Could not write the address, but the location was saved — enter it manually');
    } catch (_) {
      if (mounted) {
        setState(() => _isLocating = false);
        _showError(_isBn ? 'বর্তমান লোকেশন পাওয়া যায়নি' : 'Could not get your current location');
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
    if (!_agreedToPolicies) {
      _showError(_isBn ? 'শর্তাবলীতে সম্মত হন' : 'Please agree to the policies');
      return;
    }
    if (_selectedHub == null) {
      _showError(_isBn ? 'একটি হাব বেছে নিন' : 'Choose a hub');
      return;
    }
    final address = _addressController.text.trim();
    if (_fulfillmentMethod == 'delivery' && address.isEmpty) {
      _showError(_isBn ? 'ডেলিভারি ঠিকানা দিন' : 'Enter a delivery address');
      return;
    }
    if (_cart == null || _cart!.isEmpty) {
      _showError(_isBn ? 'কার্ট খালি' : 'Cart is empty');
      return;
    }
    setState(() => _isPlacing = true);
    try {
      final order = await GroceriesService.instance.checkout(
        userId: widget.userId,
        hubId: _selectedHub!.id,
        fulfillmentMethod: _fulfillmentMethod,
        deliveryAddress: _fulfillmentMethod == 'delivery' ? address : null,
        deliveryLatitude: _fulfillmentMethod == 'delivery' ? _deliveryLat : null,
        deliveryLongitude: _fulfillmentMethod == 'delivery' ? _deliveryLon : null,
        paymentMethod: _paymentMethod,
      );
      if (!mounted) return;

      // bkash/nagad route through SSLCommerz's hosted page — cash_on_delivery/wallet
      // settle outside the app, same as before.
      if (_paymentMethod == 'bkash' || _paymentMethod == 'nagad') {
        final transaction = await GroceriesService.instance.initiatePayment(order.id);
        final gatewayPageUrl = transaction['gatewayPageUrl'] as String?;
        if (!mounted) return;
        if (gatewayPageUrl == null) {
          _showError(_isBn ? 'পেমেন্ট শুরু করা যায়নি — অর্ডার হয়ে গেছে, পরে আবার চেষ্টা করুন' : 'Could not start payment — the order was placed, try paying again later');
          Navigator.of(context).popUntil((r) => r.isFirst);
          return;
        }
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (waitingContext) => PaymentWaitingScreen(
            gatewayPageUrl: gatewayPageUrl,
            title: _isBn ? 'গ্রোসারি পেমেন্ট' : 'Grocery Payment',
            titleEn: 'Grocery Payment',
            amount: order.totalAmount,
            checkStatus: () async {
              try {
                await GroceriesService.instance.confirmPayment(order.id);
                return PaymentCheckStatus.completed;
              } catch (_) {
                return PaymentCheckStatus.pending;
              }
            },
            onConfirmed: () => Navigator.of(waitingContext).pop(),
            applyCoupon: (code) async {
              final t = await GroceriesService.instance.initiatePayment(order.id, couponCode: code);
              return {'gatewayPageUrl': t['gatewayPageUrl'], 'amount': double.tryParse('${t['amount']}') ?? order.totalAmount};
            },
          ),
        ));
        if (!mounted) return;
        Navigator.of(context).popUntil((r) => r.isFirst);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _fulfillmentMethod == 'pickup'
              ? (_isBn ? 'অর্ডার দেওয়া হয়েছে! হাব থেকে সংগ্রহ করুন।' : 'Order placed! Collect it from the hub.')
              : (_isBn ? 'অর্ডার দেওয়া হয়েছে!' : 'Order placed!'),
          style: const TextStyle(color: AppColors.ivory, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
      if (mounted) setState(() => _isPlacing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
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
                        ? Center(child: Text(_isBn ? 'কার্ট খালি' : 'Cart is empty', style: const TextStyle(color: AppColors.textMuted)))
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
                Text(_isBn ? 'অর্ডার সারসংক্ষেপ' : 'Order Summary', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
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
                    Text(_isBn ? 'মোট' : 'Total', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
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
                Text(_isBn ? 'হাব বেছে নিন' : 'Choose a Hub', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_isBn ? 'আপনার অর্ডার এই হাব থেকেই প্রস্তুত হয়ে সংগ্রহ/ডেলিভারি হবে' : 'Your order will be prepared and collected/delivered from this hub', style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                const SizedBox(height: 12),
                if (_hubs.isEmpty)
                  Text(_isBn ? 'কোনো হাব পাওয়া যায়নি' : 'No hub found', style: const TextStyle(color: AppColors.textMuted, fontSize: 13))
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
                                Text(_isBn ? '${h.distanceKm!.toStringAsFixed(1)} কিমি' : '${h.distanceKm!.toStringAsFixed(1)} km', style: const TextStyle(color: AppColors.deepBlue, fontSize: 11, fontWeight: FontWeight.w600)),
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
                Text(_isBn ? 'কীভাবে পেতে চান' : 'How do you want to receive it', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _fulfillmentTile('pickup', Icons.storefront_rounded, _isBn ? 'নিজে সংগ্রহ' : 'Self pickup', _isBn ? 'হাব থেকে নিজে নিয়ে যান' : 'Collect it from the hub yourself')),
                  const SizedBox(width: 10),
                  Expanded(child: _fulfillmentTile('delivery', Icons.local_shipping_rounded, _isBn ? 'ডেলিভারি' : 'Delivery', _isBn ? 'বাসায় পৌঁছে দেওয়া হবে' : 'Delivered to your home')),
                ]),
                if (_fulfillmentMethod == 'delivery') ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_isBn ? 'ডেলিভারি ঠিকানা' : 'Delivery address', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      GestureDetector(
                        onTap: _isLocating ? null : _useCurrentLocation,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isLocating)
                              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))
                            else
                              const Icon(Icons.my_location_rounded, color: AppColors.deepBlue, size: 14),
                            const SizedBox(width: 5),
                            Text(_isBn ? 'বর্তমান লোকেশন' : 'Current location', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _addressController,
                    maxLines: 3,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _isBn ? 'বাড়ি নম্বর, রাস্তা, এলাকা...' : 'House number, street, area...',
                      prefixIcon: const Icon(Icons.location_on_rounded, color: AppColors.textMuted),
                    ),
                    onChanged: (_) {
                      // Manual edit after auto-fill — the typed text and the captured
                      // coordinates could now describe different places, so drop the pin.
                      if (_deliveryLat != null) setState(() { _deliveryLat = null; _deliveryLon = null; });
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.deepBlue.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                    child: Text(_isBn ? 'সাধারণত অর্ডারের পরের দিন হাবে পণ্য পৌঁছে যায় — তখন গিয়ে সংগ্রহ করতে পারবেন।' : 'Products usually arrive at the hub the day after ordering — you can collect them then.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4)),
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
                Text(_isBn ? 'পেমেন্ট পদ্ধতি' : 'Payment Method', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
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
                        child: Text(_isBn ? m.label : m.labelEn, style: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 160.ms),
          const SizedBox(height: 12),
          PolicyAgreementCheckbox(
            value: _agreedToPolicies,
            onChanged: (v) => setState(() => _agreedToPolicies = v),
            isBn: _isBn,
          ).animate().fadeIn(duration: 400.ms, delay: 180.ms),
          const SizedBox(height: 12),
          GlassButton(
            label: _isBn ? 'অর্ডার দিন — ৳${cart.totalAmount.toStringAsFixed(0)}' : 'Place order — ৳${cart.totalAmount.toStringAsFixed(0)}',
            isLoading: _isPlacing,
            onPressed: _agreedToPolicies ? _placeOrder : null,
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
          Text(_isBn ? 'চেকআউট' : 'Checkout', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
