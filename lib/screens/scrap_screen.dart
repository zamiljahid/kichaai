import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/dispatch_service.dart';
import '../services/scrap_service.dart';
import '../widgets/glass_button.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ScrapScreen extends StatefulWidget {
  const ScrapScreen({super.key});

  @override
  State<ScrapScreen> createState() => _ScrapScreenState();
}

const _kMinWeightKg = 10.0; // server-enforced minimum — matches the backend's 500 rejection

class _ScrapScreenState extends State<ScrapScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Form state
  final _formKey = GlobalKey<FormState>();
  final _weightCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  List<ScrapRateModel> _rates = [];
  ScrapRateModel? _selectedType;
  DateTime? _preferredDate;
  bool _ratesLoading = true;

  // My requests state
  List<ScrapRequestModel> _myRequests = [];
  bool _requestsLoading = true;

  bool _isSubmitting = false;
  bool _isLocating = false;
  String? _userId;
  bool _isBn = true;

  double get _estimatedPrice {
    final weight = double.tryParse(_weightCtrl.text.trim()) ?? 0.0;
    final rate = _selectedType?.ratePerKg ?? 0.0;
    return weight * rate;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _weightCtrl.addListener(() => setState(() {}));
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _weightCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _userId = await ApiClient.getUserId();
    await Future.wait([_loadRates(), _loadMyRequests()]);
  }

  Future<void> _loadRates() async {
    setState(() => _ratesLoading = true);
    try {
      final rates = await ScrapService.instance.getRatesToday();
      if (mounted) setState(() { _rates = rates; _ratesLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _ratesLoading = false);
    }
  }

  Future<void> _loadMyRequests() async {
    if (_userId == null) {
      if (mounted) setState(() => _requestsLoading = false);
      return;
    }
    setState(() => _requestsLoading = true);
    try {
      final requests = await ScrapService.instance.getMyRequests();
      if (mounted) setState(() { _myRequests = requests; _requestsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _requestsLoading = false);
    }
  }

  Future<void> _pickPreferredDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _preferredDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) setState(() => _preferredDate = picked);
  }

  Future<void> _detectLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError(_isBn ? 'লোকেশন সার্ভিস চালু নেই — সেটিংস থেকে চালু করুন।' : 'Location service is off — turn it on in settings.');
        setState(() => _isLocating = false);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) { setState(() => _isLocating = false); return; }
      }
      if (permission == LocationPermission.deniedForever) {
        _showError(_isBn ? 'লোকেশন অনুমতি বন্ধ আছে — অ্যাপ সেটিংস থেকে চালু করুন।' : 'Location permission is off — turn it on in app settings.');
        setState(() => _isLocating = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final addr = await DispatchService.instance.reverseGeocode(position.latitude, position.longitude);
      if (!mounted) return;
      if (addr != null) {
        _addressCtrl.text = addr;
      } else {
        _showError(_isBn ? 'ঠিকানা খুঁজে পাওয়া যায়নি — ম্যাপে সরাসরি দেখিয়ে দিন।' : 'Could not find the address — pick it directly on the map.');
      }
      setState(() => _isLocating = false);
    } catch (_) {
      if (mounted) {
        _showError(_isBn ? 'বর্তমান অবস্থান পাওয়া যায়নি।' : 'Could not get your current location.');
        setState(() => _isLocating = false);
      }
    }
  }

  Future<void> _pickOnMap() async {
    final pin = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => const _ScrapPinPickerScreen()),
    );
    if (pin == null || !mounted) return;
    setState(() => _isLocating = true);
    final addr = await DispatchService.instance.reverseGeocode(pin.latitude, pin.longitude);
    if (!mounted) return;
    if (addr != null) {
      _addressCtrl.text = addr;
    } else {
      // Reverse-geocode failed but the user DID pick a precise point — fall back to
      // raw coordinates rather than silently discarding their choice.
      _addressCtrl.text = '${pin.latitude.toStringAsFixed(6)}, ${pin.longitude.toStringAsFixed(6)}';
    }
    setState(() => _isLocating = false);
  }

  Future<void> _submitRequest() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedType == null) {
      _showError(_isBn ? 'অনুগ্রহ করে একটি ক্যাটাগরি বেছে নিন।' : 'Please choose a category.');
      return;
    }
    if (_preferredDate == null) {
      _showError(_isBn ? 'পছন্দের তারিখ বেছে নিন।' : 'Choose a preferred date.');
      return;
    }
    if (_userId == null) {
      _showError(_isBn ? 'লগইন তথ্য পাওয়া যায়নি।' : 'Login information not found.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ScrapService.instance.createRequest(
        userId: _userId!,
        scrapTypes: [_selectedType!.scrapType],
        estimatedWeightKg: double.parse(_weightCtrl.text.trim()),
        pickupAddress: _addressCtrl.text.trim(),
        preferredDate: _preferredDate!,
      );

      if (!mounted) return;

      _formKey.currentState?.reset();
      _weightCtrl.clear();
      _addressCtrl.clear();
      setState(() {
        _selectedType = null;
        _preferredDate = null;
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isBn ? 'আপনার অনুরোধ সফলভাবে পাঠানো হয়েছে।' : 'Your request was sent successfully.', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          margin: const EdgeInsets.all(16),
        ),
      );

      _tabController.animateTo(1);
      await _loadMyRequests();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      final ex = ApiClient.mapError(e);
      _showError(ex.localized(_isBn));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: colors.surfaceContainerHighest,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_isBn ? 'স্ক্র্যাপ সংগ্রহ' : 'Scrap Collection', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colors.primary,
          unselectedLabelColor: colors.outline,
          indicatorColor: colors.primary,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
          tabs: [Tab(text: _isBn ? 'নতুন অনুরোধ' : 'New Request'), Tab(text: _isBn ? 'আমার অনুরোধ' : 'My Requests')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildNewRequestTab(), _buildMyRequestsTab()],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 0 — New Request
  // ---------------------------------------------------------------------------

  Widget _buildNewRequestTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel(_isBn ? 'ক্যাটাগরি' : 'Category', Icons.category_outlined),
            const SizedBox(height: 8),
            _buildCategoryDropdown(),
            if (_selectedType != null) ...[
              const SizedBox(height: 8),
              _buildPriceHint(),
            ],
            const SizedBox(height: 20),
            _buildSectionLabel(_isBn ? 'আনুমানিক ওজন (কেজি, ন্যূনতম ১০)' : 'Estimated weight (kg, min 10)', Icons.scale_outlined),
            const SizedBox(height: 8),
            _buildWeightField(),
            const SizedBox(height: 20),
            _buildSectionLabel(_isBn ? 'ঠিকানা' : 'Address', Icons.location_on_outlined),
            const SizedBox(height: 8),
            _buildAddressField(),
            const SizedBox(height: 20),
            _buildSectionLabel(_isBn ? 'পছন্দের তারিখ' : 'Preferred date', Icons.calendar_today_outlined),
            const SizedBox(height: 8),
            _buildDatePicker(),
            const SizedBox(height: 32),
            GlassButton(
              label: _isSubmitting ? (_isBn ? 'পাঠানো হচ্ছে...' : 'Sending...') : (_isBn ? 'অনুরোধ পাঠান' : 'Send request'),
              onPressed: _isSubmitting ? null : _submitRequest,
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms);
  }

  Widget _buildSectionLabel(String label, IconData icon) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colors.primary, size: 16),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  InputDecoration _fieldDeco({String? hint, String? suffixText}) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.outline, fontSize: 14),
        suffixText: suffixText,
        suffixStyle: TextStyle(color: colors.outline, fontSize: 13, fontWeight: FontWeight.w500),
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.outlineVariant, width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.outlineVariant, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5)),
        errorStyle: const TextStyle(color: Color(0xFFEF4444), fontSize: 11),
      );
  }

  Widget _buildCategoryDropdown() {
    final colors = Theme.of(context).colorScheme;
    if (_ratesLoading) {
      return Container(
        height: 56,
        decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.outlineVariant)),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary))),
      );
    }

    if (_rates.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.outlineVariant)),
        child: Text(_isBn ? 'কোনো ক্যাটাগরি পাওয়া যায়নি' : 'No category found', style: TextStyle(color: colors.outline, fontSize: 14)),
      );
    }

    return DropdownButtonFormField<ScrapRateModel>(
      value: _selectedType,
      decoration: _fieldDeco(hint: _isBn ? 'একটি ক্যাটাগরি বেছে নিন' : 'Choose a category'),
      dropdownColor: colors.surface,
      iconEnabledColor: colors.outline,
      style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w500),
      items: _rates.map((r) => DropdownMenuItem(value: r, child: Text(r.labelBn, style: TextStyle(color: colors.onSurface, fontSize: 14)))).toList(),
      onChanged: (val) => setState(() => _selectedType = val),
      validator: (val) => val == null ? (_isBn ? 'একটি ক্যাটাগরি বেছে নিন' : 'Choose a category') : null,
    );
  }

  Widget _buildPriceHint() {
    final colors = Theme.of(context).colorScheme;
    final price = _estimatedPrice;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: colors.primary, size: 16),
          const SizedBox(width: 8),
          Text(_isBn ? 'আনুমানিক মূল্য: ৳${price.toStringAsFixed(0)}' : 'Estimated price: ৳${price.toStringAsFixed(0)}', style: TextStyle(color: colors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text(_isBn ? '(৳${_selectedType!.ratePerKg.toStringAsFixed(0)}/কেজি)' : '(৳${_selectedType!.ratePerKg.toStringAsFixed(0)}/kg)', style: TextStyle(color: colors.outline, fontSize: 11)),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).scale(begin: const Offset(0.97, 0.97));
  }

  Widget _buildWeightField() {
    final colors = Theme.of(context).colorScheme;
    return TextFormField(
      controller: _weightCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: colors.onSurface, fontSize: 14),
      decoration: _fieldDeco(hint: _isBn ? 'যেমন: ১৫' : 'e.g. 15', suffixText: _isBn ? 'কেজি' : 'kg'),
      validator: (val) {
        if (val == null || val.trim().isEmpty) return _isBn ? 'ওজন লিখুন' : 'Enter the weight';
        final parsed = double.tryParse(val.trim());
        if (parsed == null || parsed <= 0) return _isBn ? 'সঠিক ওজন লিখুন' : 'Enter a valid weight';
        if (parsed < _kMinWeightKg) return _isBn ? 'ন্যূনতম $_kMinWeightKg কেজি লাগবে' : 'Minimum $_kMinWeightKg kg required';
        return null;
      },
    );
  }

  Widget _buildAddressField() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _addressCtrl,
          style: TextStyle(color: colors.onSurface, fontSize: 14),
          decoration: _fieldDeco(hint: _isBn ? 'সম্পূর্ণ ঠিকানা লিখুন' : 'Enter the full address'),
          validator: (val) => (val == null || val.trim().isEmpty) ? (_isBn ? 'ঠিকানা লিখুন' : 'Enter an address') : null,
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isLocating ? null : _detectLocation,
              icon: _isLocating
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary))
                  : Icon(Icons.my_location_rounded, size: 16, color: colors.primary),
              label: Text(_isBn ? 'বর্তমান অবস্থান' : 'Current location', style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.outlineVariant),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isLocating ? null : _pickOnMap,
              icon: Icon(Icons.map_outlined, size: 16, color: colors.primary),
              label: Text(_isBn ? 'ম্যাপে দেখান' : 'Show on map', style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.outlineVariant),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildDatePicker() {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _pickPreferredDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: colors.outline, size: 16),
            const SizedBox(width: 10),
            Text(
              _preferredDate == null ? (_isBn ? 'তারিখ বেছে নিন' : 'Choose a date') : _formatDate(_preferredDate!),
              style: TextStyle(
                color: _preferredDate == null ? colors.outline : colors.onSurface,
                fontSize: 14,
                fontWeight: _preferredDate == null ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1 — My Requests
  // ---------------------------------------------------------------------------

  Widget _buildMyRequestsTab() {
    final colors = Theme.of(context).colorScheme;
    if (_requestsLoading) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_myRequests.isEmpty) {
      return _buildEmptyState();
    }
    return RefreshIndicator(
      onRefresh: _loadMyRequests,
      color: colors.primary,
      backgroundColor: colors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: _myRequests.length,
        itemBuilder: (ctx, i) => _buildRequestCard(_myRequests[i], i),
      ),
    ).animate().fadeIn(duration: 350.ms);
  }

  Widget _buildEmptyState() {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle, border: Border.all(color: colors.outlineVariant)),
            child: Icon(Icons.recycling_rounded, color: colors.outline, size: 36),
          ),
          const SizedBox(height: 16),
          Text(_isBn ? 'কোনো অনুরোধ নেই' : 'No requests yet', style: TextStyle(color: colors.outline, fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(_isBn ? 'নতুন অনুরোধ ট্যাবে যান এবং স্ক্র্যাপ সংগ্রহের জন্য অনুরোধ করুন।' : 'Go to the New Request tab and request a scrap pickup.', textAlign: TextAlign.center, style: TextStyle(color: colors.outline, fontSize: 12)),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildRequestCard(ScrapRequestModel req, int index) {
    final colors = Theme.of(context).colorScheme;
    final statusConfig = _statusConfig(req.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.outlineVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: colors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.recycling_rounded, color: colors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(req.scrapTypesLabelBn, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(_isBn ? '${req.estimatedWeightKg.toStringAsFixed(1)} কেজি' : '${req.estimatedWeightKg.toStringAsFixed(1)} kg', style: TextStyle(color: colors.outline, fontSize: 12)),
                  ],
                ),
              ),
              _buildStatusBadge(statusConfig),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.location_on_outlined, req.pickupAddress),
          const SizedBox(height: 6),
          _buildInfoRow(Icons.event_outlined, _isBn ? 'পছন্দের তারিখ: ${_formatDate(req.preferredDate)}' : 'Preferred date: ${_formatDate(req.preferredDate)}'),
          if (req.adminNote != null && req.adminNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildInfoRow(Icons.notes_outlined, req.adminNote!),
          ],
          if (req.status == 'COLLECTED' && req.amountPaidToUser != null) ...[
            const SizedBox(height: 6),
            _buildInfoRow(Icons.payments_outlined, _isBn ? 'প্রদান করা হয়েছে: ৳${req.amountPaidToUser!.toStringAsFixed(0)}' : 'Paid: ৳${req.amountPaidToUser!.toStringAsFixed(0)}'),
          ],
        ],
      ),
    ).animate(delay: Duration(milliseconds: 50 * index)).fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildStatusBadge(({String label, Color color}) config) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: config.color.withOpacity(0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: config.color.withOpacity(0.4))),
      child: Text(config.label, style: TextStyle(color: config.color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colors.outline, size: 13),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: colors.outline, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  ({String label, Color color}) _statusConfig(String status) {
    final colors = Theme.of(context).colorScheme;
    if (_isBn) {
      switch (status) {
        case 'COLLECTED':
          return (label: 'সংগৃহীত', color: const Color(0xFF10B981));
        case 'CANCELLED':
          return (label: 'বাতিল', color: const Color(0xFFEF4444));
        case 'SCHEDULED':
          return (label: 'সময়সূচি নির্ধারিত', color: colors.primary);
        default:
          return (label: 'অপেক্ষমাণ', color: const Color(0xFFF59E0B));
      }
    }
    switch (status) {
      case 'COLLECTED':
        return (label: 'Collected', color: const Color(0xFF10B981));
      case 'CANCELLED':
        return (label: 'Cancelled', color: const Color(0xFFEF4444));
      case 'SCHEDULED':
        return (label: 'Scheduled', color: colors.primary);
      default:
        return (label: 'Pending', color: const Color(0xFFF59E0B));
    }
  }
}

// ── Manual pin picker — tap the map to mark exactly where to collect from,
// then reverse-geocoded back into the address field (mirrors post_mess_screen's
// picker, kept local here since the two forms have unrelated submit flows).
class _ScrapPinPickerScreen extends StatefulWidget {
  const _ScrapPinPickerScreen();

  @override
  State<_ScrapPinPickerScreen> createState() => _ScrapPinPickerScreenState();
}

class _ScrapPinPickerScreenState extends State<_ScrapPinPickerScreen> {
  static const _dhaka = LatLng(23.8103, 90.4125);
  LatLng? _pin;
  bool _isBn = true;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: colors.surfaceContainerHighest,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text(_isBn ? 'ম্যাপে দেখান' : 'Show on Map', style: TextStyle(color: colors.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(target: _dhaka, zoom: 12),
          onTap: (p) => setState(() => _pin = p),
          markers: {
            if (_pin != null) Marker(markerId: const MarkerId('pin'), position: _pin!),
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
        Positioned(
          left: 16, right: 16, bottom: 24,
          child: GestureDetector(
            onTap: _pin == null ? null : () => Navigator.pop(context, _pin),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: _pin == null ? colors.outline : colors.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  _pin == null
                      ? (_isBn ? 'ম্যাপে ট্যাপ করে জায়গাটি দেখান' : 'Tap the map to mark the place')
                      : (_isBn ? 'এই জায়গাটিই ঠিক আছে' : 'Confirm this location'),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
