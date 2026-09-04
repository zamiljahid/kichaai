import 'package:flutter/material.dart';
import '../services/dispatch_service.dart';

/// "Booked vs blocked vs free" calendar for a photographer/cinematographer/
/// makeup_artist — used both on the provider's own wall (interactive: true —
/// tap a free day to mark it off, tap a self-blocked day to undo) and the
/// customer's browse-and-pick detail screen (interactive: false, read-only).
/// Booked days come from real DispatchJob rows and can never be tapped away —
/// only the provider's own unbooked "day off" marks are editable here.
class AvailabilityCalendar extends StatefulWidget {
  final String providerId;
  final bool interactive;
  const AvailabilityCalendar({super.key, required this.providerId, this.interactive = false});

  @override
  State<AvailabilityCalendar> createState() => _AvailabilityCalendarState();
}

class _AvailabilityCalendarState extends State<AvailabilityCalendar> {
  bool _loading = true;
  String? _error;
  final Set<DateTime> _bookedDays = {};
  final Set<DateTime> _blockedDays = {};
  DateTime? _busyDay;

  static const _bnWeekdays = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি', 'রবি'];
  static const _bnMonths = [
    'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
    'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final from = DateTime.now();
      final to = DateTime(from.year, from.month + 2, 0); // through end of next month
      final avail = await DispatchService.instance.getProviderAvailability(
        widget.providerId,
        from: from,
        to: to,
      );
      final booked = <DateTime>{};
      for (final s in (avail['bookedSlots'] as List<dynamic>? ?? [])) {
        final raw = (s as Map)['eventDate'] as String?;
        if (raw == null) continue;
        final d = DateTime.tryParse(raw)?.toLocal();
        if (d != null) booked.add(DateTime(d.year, d.month, d.day));
      }
      final blocked = <DateTime>{};
      for (final raw in (avail['blockedDates'] as List<dynamic>? ?? [])) {
        final d = DateTime.tryParse(raw as String)?.toLocal();
        if (d != null) blocked.add(DateTime(d.year, d.month, d.day));
      }
      if (!mounted) return;
      setState(() {
        _bookedDays..clear()..addAll(booked);
        _blockedDays..clear()..addAll(blocked);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _onDayTap(DateTime date) async {
    final colors = Theme.of(context).colorScheme;
    if (!widget.interactive) return;
    if (_bookedDays.contains(date)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('এই দিন আসল বুকিং আছে — এখান থেকে সরানো যাবে না', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFFEF4444), behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final isBlocked = _blockedDays.contains(date);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(isBlocked ? 'দিনটি খালি করবেন?' : 'দিনটি বন্ধ রাখবেন?', style: TextStyle(color: colors.onSurface)),
        content: Text(
          isBlocked
              ? 'এই দিন আবার বুকিং-এর জন্য খোলা হবে।'
              : 'এই দিন কোনো কাস্টমার আপনাকে বুক করতে পারবে না — যেমন ছুটির দিন।',
          style: TextStyle(color: colors.outline),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('বাতিল', style: TextStyle(color: colors.outline))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isBlocked ? 'খালি করুন' : 'বন্ধ রাখুন', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busyDay = date);
    try {
      if (isBlocked) {
        await DispatchService.instance.unblockDate(date);
      } else {
        await DispatchService.instance.blockDate(date);
      }
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('আপডেট করা যায়নি — আবার চেষ্টা করুন', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFFEF4444), behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _busyDay = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_loading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: colors.primary)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text('সময়সূচী লোড করা যায়নি', style: TextStyle(color: colors.outline, fontSize: 12)),
            TextButton(onPressed: _load, child: Text('আবার চেষ্টা করুন', style: TextStyle(color: colors.primary))),
          ],
        ),
      );
    }
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _legend(),
        if (widget.interactive) ...[
          const SizedBox(height: 6),
          Text('খালি দিনে ট্যাপ করে ছুটি মার্ক করুন', style: TextStyle(color: colors.outline, fontSize: 11)),
        ],
        const SizedBox(height: 10),
        _monthGrid(now.year, now.month),
        const SizedBox(height: 16),
        _monthGrid(now.month == 12 ? now.year + 1 : now.year, now.month == 12 ? 1 : now.month + 1),
      ],
    );
  }

  Widget _legend() {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _legendDot(const Color(0xFFEF4444), 'বুক করা'),
        _legendDot(const Color(0xFF9CA3AF), 'বন্ধ (ছুটি)'),
        _legendDot(colors.surface, 'খালি', border: true),
      ],
    );
  }

  Widget _legendDot(Color color, String label, {bool border = false}) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: border ? Border.all(color: colors.outlineVariant) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: colors.outline, fontSize: 12)),
      ],
    );
  }

  Widget _monthGrid(int year, int month) {
    final colors = Theme.of(context).colorScheme;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Monday-first offset (weekday: Mon=1..Sun=7)
    final leadingBlanks = firstDay.weekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_bnMonths[month - 1]} $year',
              style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: _bnWeekdays
                .map((w) => Expanded(
                      child: Center(
                        child: Text(w, style: TextStyle(color: colors.outline, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          for (int r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: List.generate(7, (c) {
                  final cellIndex = r * 7 + c;
                  final dayNum = cellIndex - leadingBlanks + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 30));
                  }
                  final date = DateTime(year, month, dayNum);
                  final isBooked = _bookedDays.contains(date);
                  final isBlocked = _blockedDays.contains(date);
                  final isPast = date.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));
                  final isBusy = _busyDay == date;
                  final bgColor = isBooked
                      ? const Color(0xFFEF4444)
                      : isBlocked
                          ? const Color(0xFF9CA3AF)
                          : Colors.transparent;
                  return Expanded(
                    child: GestureDetector(
                      onTap: (widget.interactive && !isPast && _busyDay == null) ? () => _onDayTap(date) : null,
                      child: Container(
                        height: 30,
                        margin: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(8),
                          border: (widget.interactive && !isPast && !isBooked && !isBlocked)
                              ? Border.all(color: colors.primary.withOpacity(0.25), width: 1)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: isBusy
                            ? SizedBox(
                                width: 12, height: 12,
                                child: CircularProgressIndicator(strokeWidth: 1.6, color: colors.outline),
                              )
                            : Text(
                                '$dayNum',
                                style: TextStyle(
                                  color: (isBooked || isBlocked)
                                      ? Colors.white
                                      : isPast
                                          ? colors.outline.withOpacity(0.4)
                                          : colors.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: (isBooked || isBlocked) ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
