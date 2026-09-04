import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Blank-by-default checkbox + hyperlinked Terms/Privacy/Refund text, meant to sit
/// right above a "place order" / "pay now" button per payment-gateway compliance
/// (the customer must actively check it — never pre-checked).
class PolicyAgreementCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isBn;

  const PolicyAgreementCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.isBn,
  });

  static Future<void> _open(String path) async {
    await launchUrl(Uri.parse('https://kichaai.com/$path'), mode: LaunchMode.externalApplication);
  }

  /// Modal confirm dialog gated by the same checkbox — for payment triggers
  /// (a "Pay" button on a list item, a job/booking detail screen, etc.) that
  /// have no natural checkout page to put the checkbox on inline. Returns
  /// true only if the customer both checked the box and pressed Confirm.
  static Future<bool> confirm(BuildContext context, {required bool isBn}) async {
    final colors = Theme.of(context).colorScheme;
    bool agreed = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(isBn ? 'পেমেন্ট নিশ্চিত করুন' : 'Confirm Payment', style: TextStyle(color: colors.onSurface)),
          content: PolicyAgreementCheckbox(
            value: agreed,
            onChanged: (v) => setDialogState(() => agreed = v),
            isBn: isBn,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isBn ? 'বাতিল' : 'Cancel', style: TextStyle(color: colors.outline)),
            ),
            TextButton(
              onPressed: agreed ? () => Navigator.pop(ctx, true) : null,
              child: Text(isBn ? 'নিশ্চিত করুন' : 'Confirm', style: TextStyle(color: agreed ? colors.primary : colors.outline)),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final linkStyle = TextStyle(
      color: colors.primary,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );
    final baseStyle = TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5, height: 1.4);

    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: colors.primary,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, right: 4),
              child: RichText(
                text: TextSpan(
                  style: baseStyle,
                  children: [
                    TextSpan(text: isBn ? 'আমি ' : 'I have read and agree to the '),
                    TextSpan(
                      text: isBn ? 'ব্যবহারের শর্তাবলী' : 'Terms & Conditions',
                      style: linkStyle,
                      recognizer: TapGestureRecognizer()..onTap = () => _open('terms'),
                    ),
                    TextSpan(text: isBn ? ', ' : ', '),
                    TextSpan(
                      text: isBn ? 'প্রাইভেসি পলিসি' : 'Privacy Policy',
                      style: linkStyle,
                      recognizer: TapGestureRecognizer()..onTap = () => _open('privacy'),
                    ),
                    TextSpan(text: isBn ? ' এবং ' : ', and '),
                    TextSpan(
                      text: isBn ? 'রিফান্ড ও রিটার্ন নীতি' : 'Refund & Return Policy',
                      style: linkStyle,
                      recognizer: TapGestureRecognizer()..onTap = () => _open('refund'),
                    ),
                    TextSpan(text: isBn ? ' পড়েছি এবং সম্মত।' : '.'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
