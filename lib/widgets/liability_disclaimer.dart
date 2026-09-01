import 'package:flutter/material.dart';

/// Universal liability disclaimer + mandatory "I agree" checkbox — the
/// founder's own framing: "Company just media. Shobar jonnoi mention korba
/// eta" (mention this for everyone). Currently wired into the household-help
/// (helping_hand) onboarding screen only, since that is what is in scope, but
/// deliberately built as a standalone reusable widget (not private to that
/// screen) so any other home-visit service can drop it in later without
/// duplicating the text. Matches the PolicyAgreementCheckbox pattern already
/// used for payment/checkout consent (widgets/policy_agreement_checkbox.dart):
/// a stateless value/onChanged/isBn widget, checkbox unchecked by default.
///
/// Framing: if any loss/damage happens at the customer's home through this
/// provider, the provider is personally responsible for it; if the provider
/// experiences any kind of harassment, the company will help legally but is
/// not itself liable — the company is only a mediator between customer and
/// provider.
Widget liabilityDisclaimerCheckbox({
  required BuildContext context,
  required bool value,
  required ValueChanged<bool> onChanged,
  required bool isBn,
}) {
  // A top-level function widget, so the scheme is read from the passed context
  // rather than an implicit one.
  final colors = Theme.of(context).colorScheme;
  final bodyStyle =
      TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5, height: 1.5);
  final text = isBn
      ? 'এই প্রোভাইডারের মাধ্যমে গ্রাহকের বাসায় কোনো ক্ষতি বা লোকসান হলে, তার জন্য প্রোভাইডার ব্যক্তিগতভাবে দায়ী থাকবেন। '
          'প্রোভাইডার কোনো ধরনের হয়রানির শিকার হলে কোম্পানি আইনি সহায়তা দেবে, তবে কোম্পানি নিজে এর জন্য দায়বদ্ধ নয় — '
          'কোম্পানি কেবল গ্রাহক ও প্রোভাইডারের মধ্যে একটি মাধ্যম মাত্র।'
      : "If any loss or damage occurs at the customer's home through this provider, the provider is personally "
          'responsible for it. If the provider experiences any kind of harassment, the company will provide legal '
          'assistance, but the company itself is not liable for it — the company is only a mediator between the '
          'customer and the provider.';

  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: colors.outlineVariant),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.info_outline_rounded, color: colors.outline, size: 18),
        const SizedBox(width: 8),
        Text(
          isBn ? 'দায়বদ্ধতার শর্তাবলী' : 'Liability disclaimer',
          style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ]),
      const SizedBox(height: 8),
      Text(text, style: bodyStyle),
      const SizedBox(height: 10),
      InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: colors.primary,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                isBn ? 'আমি সম্মত' : 'I agree',
                style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ]),
      ),
    ]),
  );
}
