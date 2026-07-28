import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/network/api_client.dart';
import '../models/groceries_model.dart';
import '../services/groceries_service.dart';
import '../theme/app_theme.dart';
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
  GroceryCartModel? _cart;
  String? _selectedCategoryId;
  bool _isLoading = true;
  String? _userId;

  // Product ids with an in-flight cart request — disables their buttons so a
  // fast double-tap can't fire two overlapping increments.
  final Set<String> _busyProductIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final userId = await ApiClient.getUserId();
      final results = await Future.wait([
        GroceriesService.instance.getCategories(),
        GroceriesService.instance.listProducts(
          categoryId: _selectedCategoryId,
          limit: 50,
        ),
        if (userId != null && userId.isNotEmpty)
          GroceriesService.instance.getCart(userId)
        else
          Future.value(null),
      ]);
      if (mounted) {
        setState(() {
          _categories = results[0] as List<GroceryCategoryModel>;
          _products = results[1] as List<GroceryProductModel>;
          _cart = results[2] as GroceryCartModel?;
          _userId = userId;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectCategory(String? categoryId) async {
    setState(() => _selectedCategoryId = categoryId);
    try {
      final products = await GroceriesService.instance.listProducts(
        categoryId: categoryId,
        limit: 50,
      );
      if (mounted) setState(() => _products = products);
    } catch (_) {}
  }

  int _qtyOf(String productId) {
    final item = _cart?.items.where((i) => i.productId == productId).firstOrNull;
    return item?.quantity.round() ?? 0;
  }

  Future<void> _addToCart(String productId) async {
    if (_userId == null) {
      _showError('লগইন তথ্য পাওয়া যায়নি');
      return;
    }
    setState(() => _busyProductIds.add(productId));
    try {
      final cart = await GroceriesService.instance
          .addToCart(userId: _userId!, productId: productId, quantity: 1);
      if (mounted) setState(() => _cart = cart);
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).messageBn);
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
      if (mounted) _showError(ApiClient.mapError(e).messageBn);
    } finally {
      if (mounted) setState(() => _busyProductIds.remove(productId));
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

  @override
  Widget build(BuildContext context) {
    final itemCount = _cart?.itemCount ?? 0;
    final total = _cart?.totalAmount ?? 0;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, itemCount),
              if (_categories.isNotEmpty) _buildCategoryChips(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
                    : _products.isEmpty
                        ? _buildEmpty()
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: AppColors.deepBlue,
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
                label: 'চেকআউট ($itemCount পণ্য) — ৳ ${total.toStringAsFixed(0)}',
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder, width: 1.5)),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('গ্রোসারি', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Fresh Groceries', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.shopping_basket_rounded, color: AppColors.deepBlue, size: 28),
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
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _categoryChip(null, 'সব'),
          ..._categories.map((c) => _categoryChip(c.id, c.name)),
        ],
      ),
    );
  }

  Widget _categoryChip(String? id, String label) {
    final selected = _selectedCategoryId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: GestureDetector(
        onTap: () => _selectCategory(id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.blueGradient : null,
            color: selected ? null : AppColors.glassWhite,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: selected ? Colors.transparent : AppColors.glassBorder),
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _buildProductCard(GroceryProductModel p, int index) {
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
                gradient: LinearGradient(colors: [AppColors.deepBlue.withOpacity(0.2), AppColors.deepBlue.withOpacity(0.05)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: p.imageUrl?.isNotEmpty ?? false
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(p.imageUrl!, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image_rounded, color: AppColors.textMuted, size: 36))),
                    )
                  : const Center(child: Icon(Icons.shopping_basket_outlined, color: AppColors.textMuted, size: 36)),
            ),
          ),
          const SizedBox(height: 8),
          Text(p.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text('৳ ${p.price.toStringAsFixed(0)}/${p.unit}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w700)),
          if (!p.inStock) ...[
            const SizedBox(height: 4),
            const Text('স্টক নেই', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          if (!p.inStock)
            const SizedBox(height: 32)
          else if (qty == 0)
            GestureDetector(
              onTap: busy ? null : () => _addToCart(p.id),
              child: Container(
                height: 32,
                decoration: BoxDecoration(gradient: AppColors.blueGradient, borderRadius: BorderRadius.circular(8)),
                child: Center(
                  child: busy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ivory))
                      : const Icon(Icons.add_rounded, color: AppColors.ivory, size: 20),
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
                    decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.glassBorder)),
                    child: const Icon(Icons.remove_rounded, color: AppColors.textPrimary, size: 16),
                  ),
                ),
                Expanded(child: Center(child: Text('$qty', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)))),
                GestureDetector(
                  onTap: busy ? null : () => _addToCart(p.id),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(gradient: AppColors.blueGradient, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.add_rounded, color: AppColors.ivory, size: 16),
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

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.shopping_basket_outlined, color: AppColors.textMuted, size: 56),
      const SizedBox(height: 12),
      const Text('কোনো পণ্য পাওয়া যায়নি', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
    ]),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
