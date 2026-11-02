import 'package:flutter/material.dart';

/// Prepared explicit consent control, not wired to existing accounts or drafts.
/// Caller must fetch current published version and persist server receipt.
class PolicyConsent extends StatelessWidget {
  const PolicyConsent({
    super.key,
    required this.arabic,
    required this.version,
    required this.published,
    required this.termsAccepted,
    required this.privacyAccepted,
    required this.onTerms,
    required this.onPrivacy,
    required this.openTerms,
    required this.openPrivacy,
  });
  final bool arabic, published, termsAccepted, privacyAccepted;
  final String version;
  final ValueChanged<bool> onTerms, onPrivacy;
  final VoidCallback openTerms, openPrivacy;
  bool get ready =>
      published && termsAccepted && privacyAccepted && version.isNotEmpty;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(arabic ? 'الإصدار: $version' : 'Version: $version'),
      if (!published)
        Text(
          arabic
              ? 'مسودة: الموافقة غير متاحة قبل اعتماد السياسة.'
              : 'Draft: consent is unavailable until publication.',
        ),
      TextButton(
        onPressed: openTerms,
        child: Text(
          arabic ? 'قراءة الشروط والأحكام' : 'Read terms and conditions',
        ),
      ),
      CheckboxListTile(
        value: termsAccepted,
        onChanged: published ? (v) => onTerms(v ?? false) : null,
        title: Text(
          arabic
              ? 'أوافق على الشروط والأحكام'
              : 'I agree to the terms and conditions',
        ),
      ),
      TextButton(
        onPressed: openPrivacy,
        child: Text(arabic ? 'قراءة سياسة الخصوصية' : 'Read privacy policy'),
      ),
      CheckboxListTile(
        value: privacyAccepted,
        onChanged: published ? (v) => onPrivacy(v ?? false) : null,
        title: Text(
          arabic
              ? 'اطلعت على سياسة الخصوصية وأوافق على المعالجة المحددة فيها حيث تتطلب موافقتي'
              : 'I have read the privacy policy and consent to specified processing where my consent is required',
        ),
      ),
    ],
  );
}
