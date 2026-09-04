import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/groceries_model.dart';
import '../services/groceries_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'grocery_checkout_screen.dart';

class GroceryScreen extends StatefulWidget {
  const GroceryScreen({super.key});

  @override
  State<GroceryScreen> createState() => _GroceryScreenState();
}

class _GroceryScreenState extends State<GroceryScreen> {
  List<GroceryCategoryModel> _categories = [];
  List<GroceryProductModel> _products = [];
  List<GroceryHubModel> _hubs = [];
  GroceryHubModel? _selectedHub;
  GroceryCartModel? _cart;
  String? _selectedCategoryId;
  bool _isLoading = true;
  bool _isLoadingHubs = true;
  String? _userId;
  bool _isBn = true;

  // Product ids with an in-flight cart request — disables their buttons so a
  // fast double-tap can't fire two overlapping increments.
  final Set<String> _busyProductIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _isLoadingHubs = true;
    });
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
      final userId = await ApiClient.getUserId();
      final results = await Future.wait([
        GroceriesService.instance.getCategories(),
        GroceriesService.instance.listHubs(lat: lat, lon: lon),
        if (userId != null && userId.isNotEmpty)
          GroceriesService.instance.getCart(userId)
        else
          Future.value(null),
      ]);
      if (!mounted) return;
      final hubs = results[1] as List<GroceryHubModel>;
      // Carry over the customer's previous pick for this app session, if it's
      // still an active hub — otherwise fall back to nearest (list is already
      // distance-sorted when geo worked).
      final remembered = GroceriesService.selectedHub;
      final stillValid = remembered != null && hubs.any((h) => h.id == remembered.id);
      final hub = stillValid ? remembered : null;
      setState(() {
        _categories = results[0] as List<GroceryCategoryModel>;
        _hubs = hubs;
        _selectedHub = hub;
        _cart = results[2] as GroceryCartModel?;
        _userId = userId;
        _isLoadingHubs = false;
        _isLoading = hub == null; // no hub yet → nothing to load, show picker instead
      });
      if (hub != null) await _loadProducts();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingHubs = false;
        });
      }
    }
  }

  Future<void> _loadProducts() async {
    if (_selectedHub == null) return;
    setState(() => _isLoading = true);
    try {
      final products = await GroceriesService.instance.listProducts(
        categoryId: _selectedCategoryId,
        hubId: _selectedHub!.id,
        limit: 50,
      );
      if (mounted) setState(() { _products = products; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _pickHub(GroceryHubModel hub) {
    GroceriesService.selectedHub = hub;
    setState(() => _selectedHub = hub);
    _loadProducts();
  }

  void _changeHub() {
    setState(() {
      _selectedHub = null;
      GroceriesService.selectedHub = null;
      _products = [];
    });
  }

  Future<void> _selectCategory(String? categoryId) async {
    setState(() => _selectedCategoryId = categoryId);
    await _loadProducts();
  }

  int _qtyOf(String productId) {
    final item = _cart?.items.where((i) => i.productId == productId).firstOrNull;
    return item?.quantity.round() ?? 0;
  }

  Future<void> _addToCart(String productId) async {
    if (_userId == null) {
      _showError(_isBn ? 'লগইন তথ্য পাওয়া যায়নি' : 'Login information not found');
      return;
    }
    setState(() => _busyProductIds.add(productId));
    try {
      final cart = await GroceriesService.instance
          .addToCart(userId: _userId!, productId: productId, quantity: 1);
      if (mounted) setState(() => _cart = cart);
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _busyProductIds.remove(productId));
    }
  }

  Future<void> _decrement(String productId) async {
    if (_userId == null) return;
    final newQty = _qtyOf(productId) - 1;
    setState(() => _busyProductIds.add(productId));
    try {
      final cart = await GroceriesService.instance.setCartItemQuantity(
        userId: _userId!,
        productId: productId,
        quantity: newQty < 0 ? 0 : newQty,
      );
      if (mounted) setState(() => _cart = cart);
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _busyProductIds.remove(productId));
    }
  }

  void _showError(String msg) {
    final colors = Theme.of(context).colorScheme;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: colors.onPrimary)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    final itemCount = _cart?.itemCount ?? 0;
    final total = _cart?.totalAmount ?? 0;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, itemCount),
              if (_selectedHub != null) ...[
                _buildHubBar(),
                if (_categories.isNotEmpty) _buildCategoryChips(),
              ],
              Expanded(
                child: _isLoadingHubs
                    ? Center(child: CircularProgressIndicator(color: colors.primary))
                    : _selectedHub == null
                        ? _buildHubPicker()
                        : _isLoading
                            ? Center(child: CircularProgressIndicator(color: colors.primary))
                            : _products.isEmpty
                                ? _buildEmpty()
                                : RefreshIndicator(
                                    onRefresh: _loadProducts,
                                    color: colors.primary,
                                    child: GridView.builder(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                                      itemCount: _products.length,
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.72,
                                      ),
                                      itemBuilder: (_, i) => _buildProductCard(_products[i], i),
                                    ),
                                  ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: itemCount > 0
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GlassButton(
                label: _isBn ? 'চেকআউট ($itemCount পণ্য) — ৳ ${total.toStringAsFixed(0)}' : 'Checkout ($itemCount items) — ৳ ${total.toStringAsFixed(0)}',
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(
                      builder: (_) => GroceryCheckoutScreen(userId: _userId!),
                    ))
                    .then((_) => _load()),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildHeader(BuildContext context, int itemCount) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.outlineVariant, width: 1.5)),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          Text(_isBn ? 'গ্রোসারি' : 'Groceries', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.shopping_basket_rounded, color: colors.primary, size: 28),
              if (itemCount > 0)
                Positioned(
                  top: -6, right: -6,
                  child: Container(
                    width: 18, height: 18,
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFD8125B), Color(0xFF9B1B4B)]), shape: BoxShape.circle),
                    child: Center(child: Text('$itemCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                  ),
                ),
            ],
          ),
          if (itemCount > 0) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _confirmClearCart,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: const Icon(Icons.delete_sweep_rounded,
                    color: Color(0xFFEF4444), size: 19),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  /// Empty the whole cart. Without this the only way out of a wrong cart was to
  /// decrement every line to zero one at a time.
  Future<void> _confirmClearCart() async {
    final colors = Theme.of(context).colorScheme;
    if (_userId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(_isBn ? 'কার্ট খালি করবেন?' : 'Clear the cart?',
            style: TextStyle(
                color: colors.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          _isBn ? 'কার্টের সব পণ্য সরিয়ে ফেলা হবে।' : 'Every item will be removed.',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isBn ? 'বাতিল' : 'Cancel',
                style: TextStyle(color: colors.outline)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isBn ? 'খালি করুন' : 'Clear',
                style: const TextStyle(
                    color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await GroceriesService.instance.clearCart(_userId!);
      final cart = await GroceriesService.instance.getCart(_userId!);
      if (mounted) setState(() => _cart = cart);
    } catch (_) {
      // Nothing destructive happened locally — the cart just stays as it was.
    }
  }

  Widget _buildHubBar() {
    final colors = Theme.of(context).colorScheme;
    final hub = _selectedHub!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GestureDetector(
        onTap: _changeHub,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.storefront_rounded, color: colors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hub.name, style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w700)),
                    Text(_isBn ? 'এই হাব থেকে পণ্য দেখানো হচ্ছে' : 'Showing products from this hub', style: TextStyle(color: colors.outline, fontSize: 10.5)),
                  ],
                ),
              ),
              Text(_isBn ? 'পরিবর্তন' : 'Change', style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, color: colors.primary, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHubPicker() {
    final colors = Theme.of(context).colorScheme;
    if (_hubs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_isBn ? 'কোনো হাব পাওয়া যায়নি' : 'No hub found', style: TextStyle(color: colors.outline, fontSize: 14)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        Text(_isBn ? 'আপনার হাব বেছে নিন' : 'Choose your hub', style: TextStyle(color: colors.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(_isBn ? 'যে হাব থেকে পণ্য সংগ্রহ/ডেলিভারি হবে, সেটা আগে বেছে নিন' : 'Choose which hub your order will be fulfilled/delivered from', style: TextStyle(color: colors.outline, fontSize: 12.5)),
        const SizedBox(height: 16),
        ..._hubs.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => _pickHub(h),
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.storefront_rounded, color: colors.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.name, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w700)),
                            Text(h.address, style: TextStyle(color: colors.outline, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      if (h.distanceKm != null)
                        Text(_isBn ? '${h.distanceKm!.toStringAsFixed(1)} কিমি' : '${h.distanceKm!.toStringAsFixed(1)} km', style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.w700))
                      else
                        Icon(Icons.chevron_right_rounded, color: colors.outline, size: 18),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _categoryChip(null, _isBn ? 'সব' : 'All'),
          ..._categories.map((c) => _categoryChip(c.id, c.name)),
        ],
      ),
    );
  }

  Widget _categoryChip(String? id, String label) {
    final colors = Theme.of(context).colorScheme;
    final selected = _selectedCategoryId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: GestureDetector(
        onTap: () => _selectCategory(id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected ? AppGradients.primary(colors) : null,
            color: selected ? null : colors.surface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: selected ? Colors.transparent : colors.outlineVariant),
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.white : colors.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _buildProductCard(GroceryProductModel p, int index) {
    final colors = Theme.of(context).colorScheme;
    final qty = _qtyOf(p.id);
    final busy = _busyProductIds.contains(p.id);

    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [colors.primary.withOpacity(0.2), colors.primary.withOpacity(0.05)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: p.imageUrl?.isNotEmpty ?? false
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(p.imageUrl!, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_, __, ___) => Center(child: Icon(Icons.image_rounded, color: colors.outline, size: 36))),
                    )
                  : Center(child: Icon(Icons.shopping_basket_outlined, color: colors.outline, size: 36)),
            ),
          ),
          const SizedBox(height: 8),
          Text(p.name, style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text('৳ ${p.price.toStringAsFixed(0)}/${p.unit}', style: TextStyle(color: colors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
          if (p.hubName?.isNotEmpty ?? false)
            Text(p.hubName!, style: TextStyle(color: colors.outline, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (!p.inStock) ...[
            const SizedBox(height: 4),
            Text(_isBn ? 'স্টক নেই' : 'Out of stock', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          if (!p.inStock)
            const SizedBox(height: 32)
          else if (qty == 0)
            GestureDetector(
              onTap: busy ? null : () => _addToCart(p.id),
              child: Container(
                height: 32,
                decoration: BoxDecoration(gradient: AppGradients.primary(colors), borderRadius: BorderRadius.circular(8)),
                child: Center(
                  child: busy
                      ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary))
                      : Icon(Icons.add_rounded, color: colors.onPrimary, size: 20),
                ),
              ),
            )
          else
            Row(
              children: [
                GestureDetector(
                  onTap: busy ? null : () => _decrement(p.id),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: colors.outlineVariant)),
                    child: Icon(Icons.remove_rounded, color: colors.onSurface, size: 16),
                  ),
                ),
                Expanded(child: Center(child: Text('$qty', style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w700)))),
                GestureDetector(
                  onTap: busy ? null : () => _addToCart(p.id),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(gradient: AppGradients.primary(colors), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.add_rounded, color: colors.onPrimary, size: 16),
                  ),
                ),
              ],
            ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 40 * index))
        .fadeIn(duration: 300.ms)
        .scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildEmpty() {
    final colors = Theme.of(context).colorScheme;
    return Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.shopping_basket_outlined, color: colors.outline, size: 56),
      const SizedBox(height: 12),
      Text(_isBn ? 'কোনো পণ্য পাওয়া যায়নি' : 'No products found', style: TextStyle(color: colors.outline, fontSize: 14)),
    ]),
  );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
