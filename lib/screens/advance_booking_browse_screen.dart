import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/dispatch_model.dart';
import '../services/dispatch_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/availability_calendar.dart';
import '../widgets/policy_agreement_checkbox.dart';
import 'job_tracking_screen.dart';
import 'payment_waiting_screen.dart';

/// Customer-facing browse-and-confirm flow for advance-booking jobs
/// (photographer / cinematographer / makeup_artist). The customer picks who
/// they want; there is no auto-assignment.
class AdvanceBookingBrowseScreen extends StatefulWidget {
  final String jobId;
  final String serviceKind;
  final DateTime eventDate;
  final DateTime? eventEndDate; // caregiver multi-day booking — range end, null for a single-day job

  const AdvanceBookingBrowseScreen({
    super.key,
    required this.jobId,
    required this.serviceKind,
    required this.eventDate,
    this.eventEndDate,
  });

  @override
  State<AdvanceBookingBrowseScreen> createState() => _AdvanceBookingBrowseScreenState();
}

class _AdvanceBookingBrowseScreenState extends State<AdvanceBookingBrowseScreen> {
  List<AvailableProviderModel> _providers = [];
  bool _loading = true;
  String? _error;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await DispatchService.instance.listAvailableProviders(
        serviceKind: widget.serviceKind,
        eventDate: widget.eventDate,
        eventEndDate: widget.eventEndDate,
      );
      if (!mounted) return;
      setState(() {
        _providers = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.mapError(e).localized(_isBn);
        _loading = false;
      });
    }
  }

  Future<void> _openDetail(AvailableProviderModel provider) async {
    final result = await Navigator.of(context).push<_DetailResult>(
      MaterialPageRoute(
        builder: (_) => _ProviderDetailScreen(
          jobId: widget.jobId,
          provider: provider,
          eventDate: widget.eventDate,
        ),
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case _DetailResult.confirmed:
        // Detail screen already navigated to tracking — nothing more here.
        break;
      case _DetailResult.rejected:
      case _DetailResult.conflict:
        await _fetch(); // refresh so rejected/newly-booked provider drops off
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
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant, width: 1.5),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isBn ? 'উপলব্ধ প্রোভাইডার' : 'Available Providers',
                    style: TextStyle(color: colors.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
                Text(
                  widget.eventEndDate != null
                      ? '${_formatDateOnly(widget.eventDate, _isBn)} → ${_formatDateOnly(widget.eventEndDate!, _isBn)}'
                      : _formatEventDate(widget.eventDate, _isBn),
                  style: TextStyle(color: colors.outline, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final colors = Theme.of(context).colorScheme;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 40),
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              GlassButton(label: _isBn ? 'আবার চেষ্টা করুন' : 'Try again', icon: Icons.refresh_rounded, isOutlined: true, onPressed: _fetch),
            ],
          ),
        ),
      );
    }
    if (_providers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy_rounded, color: colors.outline, size: 48),
              const SizedBox(height: 16),
              Text(_isBn ? 'এই তারিখে কেউ ফ্রি নেই' : 'No one is free on this date',
                  style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                _isBn ? 'অন্য দিন বা সময় বেছে নিয়ে আবার চেষ্টা করুন।' : 'Try a different day or time.',
                style: TextStyle(color: colors.outline, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              GlassButton(label: _isBn ? 'আবার চেষ্টা করুন' : 'Try again', icon: Icons.refresh_rounded, isOutlined: true, onPressed: _fetch),
              const SizedBox(height: 10),
              GlassButton(
                label: _isBn ? 'তারিখ পরিবর্তন করুন' : 'Change date',
                icon: Icons.edit_calendar_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: colors.primary,
      onRefresh: _fetch,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _providers.length,
        itemBuilder: (context, i) => _ProviderCard(
          provider: _providers[i],
          onTap: () => _openDetail(_providers[i]),
        ).animate(delay: Duration(milliseconds: 40 * i)).fadeIn(duration: 250.ms).slideY(begin: 0.08),
      ),
    );
  }
}

// ── Provider list card ────────────────────────────────────────────

class _ProviderCard extends StatelessWidget {
  final AvailableProviderModel provider;
  final VoidCallback onTap;
  const _ProviderCard({required this.provider, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: GlassCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ProfileAvatar(url: provider.profileImageUrl, fallback: provider.name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                provider.name,
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (provider.verified) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.verified_rounded, color: colors.primary, size: 16),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        _RatingRow(rating: provider.rating, level: provider.level),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: colors.outline, size: 22),
                ],
              ),
              if (provider.portfolio.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: provider.portfolio.length.clamp(0, 6),
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        provider.portfolio[i],
                        width: 96,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _thumbFallback(colors),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbFallback(ColorScheme colors) {
    return Container(
        width: 96,
        height: 72,
        color: colors.surface,
        alignment: Alignment.center,
        child: Icon(Icons.image_not_supported_rounded, color: colors.outline, size: 20),
      );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String? url;
  final String fallback;
  const _ProfileAvatar({required this.url, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const size = 48.0;
    if (url != null && url!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(
          url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initial(colors, fallback, size),
        ),
      );
    }
    return _initial(colors, fallback, size);
  }

  Widget _initial(ColorScheme colors, String name, double size) {
    final ch = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(gradient: AppGradients.primary(colors), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        ch,
        style: TextStyle(color: colors.onPrimary, fontSize: 20, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final double? rating;
  final String? level;
  const _RatingRow({required this.rating, required this.level});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 15),
        const SizedBox(width: 3),
        Text(
          rating == null ? '—' : rating!.toStringAsFixed(2),
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        if (level != null && level!.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Text(
              level!,
              style: TextStyle(color: colors.outline, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Detail screen: bigger portfolio + confirm/reject buttons ─────

enum _DetailResult { confirmed, rejected, conflict }

class _ProviderDetailScreen extends StatefulWidget {
  final String jobId;
  final AvailableProviderModel provider;
  final DateTime eventDate;

  const _ProviderDetailScreen({
    required this.jobId,
    required this.provider,
    required this.eventDate,
  });

  @override
  State<_ProviderDetailScreen> createState() => _ProviderDetailScreenState();
}

class _ProviderDetailScreenState extends State<_ProviderDetailScreen> {
  bool _busy = false;
  bool _isBn = true;
  bool _agreedToPolicies = false;

  Future<void> _confirm() async {
    if (!_agreedToPolicies) return;
    setState(() => _busy = true);
    try {
      final job = await DispatchService.instance.confirmProvider(
        widget.jobId,
        widget.provider.providerId,
      );
      if (!mounted) return;
      // Pop the detail screen with `.confirmed` first — the browse list behind it is done
      // with either way, whether or not a deposit still needs paying.
      Navigator.of(context).pop(_DetailResult.confirmed);

      if (!job.depositRequired) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => JobTrackingScreen(jobId: job.id)),
        );
        return;
      }

      // Deposit required — pay it now, right after confirming, rather than leaving the
      // booking half-done. Same initiate → open gateway → poll → verify pattern as course
      // enrollment; the day-of shoot itself is blocked (requestStart) until this clears.
      final transaction = await DispatchService.instance.initiateDepositPayment(job.id);
      final gatewayPageUrl = transaction['gatewayPageUrl'] as String?;
      if (!mounted) return;
      if (gatewayPageUrl == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => JobTrackingScreen(jobId: job.id)),
        );
        _showSnack(_isBn ? 'বুকিং হয়েছে, কিন্তু অগ্রিম পেমেন্ট শুরু করা যায়নি — পরে ট্রাকিং স্ক্রিন থেকে চেষ্টা করুন' : 'Booked, but could not start the deposit payment — try again from the tracking screen');
        return;
      }

      double? confirmedDeposit;
      final navigator = Navigator.of(context);
      await navigator.push(MaterialPageRoute(
        builder: (waitingContext) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: _isBn ? 'বুকিং অগ্রিম' : 'Booking Deposit',
          titleEn: 'Booking Deposit',
          amount: job.depositAmount ?? 0,
          checkStatus: () async {
            try {
              final confirmedJob = await DispatchService.instance.confirmDepositPayment(job.id);
              confirmedDeposit = confirmedJob.depositAmount;
              return PaymentCheckStatus.completed;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: () => Navigator.of(waitingContext).pop(),
          applyCoupon: (code) async {
            final t = await DispatchService.instance.initiateDepositPayment(job.id, couponCode: code);
            return {'gatewayPageUrl': t['gatewayPageUrl'], 'amount': double.tryParse('${t['amount']}') ?? (job.depositAmount ?? 0)};
          },
        ),
      ));

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => JobTrackingScreen(jobId: job.id)),
      );
      if (confirmedDeposit == null) {
        _showSnack(_isBn ? 'অগ্রিম পেমেন্ট এখনো বাকি — ট্রাকিং স্ক্রিন থেকে সম্পন্ন করুন' : 'Deposit payment still pending — complete it from the tracking screen');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 409) {
        _showSnack(_isBn ? 'দুঃখিত, এই সময়ে উনি এইমাত্র বুক হয়ে গেছেন' : 'Sorry, they were just booked for this time');
        Navigator.of(context).pop(_DetailResult.conflict);
        return;
      }
      _showSnack(e.message ?? (_isBn ? 'নিশ্চিত করতে সমস্যা হয়েছে' : 'Could not confirm'));
    } catch (e) {
      if (!mounted) return;
      _showSnack(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await DispatchService.instance.rejectProvider(
        widget.jobId,
        widget.provider.providerId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_DetailResult.rejected);
    } catch (e) {
      if (!mounted) return;
      _showSnack(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String msg) {
    final colors = Theme.of(context).colorScheme;
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
    final p = widget.provider;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _busy ? null : () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.outlineVariant, width: 1.5),
                        ),
                        child: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        p.name,
                        style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            _ProfileAvatar(url: p.profileImageUrl, fallback: p.name),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.name,
                                          style: TextStyle(
                                            color: colors.onSurface,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (p.verified)
                                        Padding(
                                          padding: EdgeInsets.only(left: 6),
                                          child: Icon(Icons.verified_rounded, color: colors.primary, size: 18),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  _RatingRow(rating: p.rating, level: p.level),
                                  if (p.specialties.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: p.specialties
                                          .map((s) => Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: colors.surface,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: colors.outlineVariant),
                                                ),
                                                child: Text(
                                                  s,
                                                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
                                                ),
                                              ))
                                          .toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (p.portfolio.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(_isBn ? 'পোর্টফোলিও' : 'Portfolio',
                              style: TextStyle(color: colors.outline, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: p.portfolio.length,
                          itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              p.portfolio[i],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: colors.surface,
                                alignment: Alignment.center,
                                child: Icon(Icons.image_not_supported_rounded, color: colors.outline),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(_isBn ? 'আসন্ন সময়সূচী' : 'Upcoming Schedule',
                            style: TextStyle(color: colors.outline, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                      AvailabilityCalendar(providerId: p.providerId),
                      const SizedBox(height: 12),
                      PolicyAgreementCheckbox(
                        value: _agreedToPolicies,
                        onChanged: (v) => setState(() => _agreedToPolicies = v),
                        isBn: _isBn,
                      ),
                      const SizedBox(height: 8),
                      GlassButton(
                        label: _isBn ? 'এনাকে বেছে নিন' : 'Choose them',
                        icon: Icons.check_circle_rounded,
                        isLoading: _busy,
                        onPressed: (_busy || !_agreedToPolicies) ? null : _confirm,
                      ),
                      const SizedBox(height: 10),
                      GlassButton(
                        label: _isBn ? 'না, অন্য কাউকে দেখান' : 'No, show someone else',
                        icon: Icons.skip_next_rounded,
                        isOutlined: true,
                        onPressed: _busy ? null : _reject,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Local formatter (date-only libs would be overkill for one line) ──

const _bnMonths = [
  'জানু', 'ফেব', 'মার্চ', 'এপ্রি', 'মে', 'জুন',
  'জুলা', 'আগ', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
];
const _enMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatEventDate(DateTime d, bool isBn) {
  final local = d.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final month = (isBn ? _bnMonths : _enMonths)[local.month - 1];
  return '${local.day} $month ${local.year}, $hh:$mm';
}

// Caregiver multi-day range — a day, not a moment, so no time-of-day in the label.
String _formatDateOnly(DateTime d, bool isBn) {
  final local = d.toLocal();
  final month = (isBn ? _bnMonths : _enMonths)[local.month - 1];
  return '${local.day} $month ${local.year}';
}
