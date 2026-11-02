import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Local draft viewer only. Never records implied consent or claims deletion.
class LegalInformationPage extends StatefulWidget {
  const LegalInformationPage({
    super.key,
    required this.arabic,
    this.initialKey,
  });
  final bool arabic;
  final String? initialKey;
  @override
  State<LegalInformationPage> createState() => _LegalInformationPageState();
}

class _LegalInformationPageState extends State<LegalInformationPage> {
  late final Future<String> _catalog = rootBundle.loadString(
    'assets/legal/policies.json',
    cache: false,
  );
  bool get arabic => widget.arabic;
  String? get initialKey => widget.initialKey;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        arabic
            ? 'السياسات والمعلومات القانونية'
            : 'Policies and legal information',
      ),
    ),
    body: Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: FutureBuilder<String>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                arabic ? 'تعذر تحميل السياسات.' : 'Could not load policies.',
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final catalog = jsonDecode(snapshot.data!) as Map<String, dynamic>;
          final rows =
              (catalog['policies'] as List).cast<Map<String, dynamic>>();
          final lang = arabic ? 'ar' : 'en';
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                arabic
                    ? 'مسودات للمراجعة — ليست سياسات نافذة. لا تسجل هذه الشاشة موافقة.'
                    : 'Review drafts — not effective policies. Viewing does not record consent.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('${catalog['version']}'),
              ...rows
                  .where((p) => initialKey == null || p['key'] == initialKey)
                  .map(
                    (p) => ExpansionTile(
                      key: ValueKey(p['key']),
                      initiallyExpanded: initialKey != null,
                      title: Text('${p['title_$lang']}'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            '${p[lang]}',
                            style: const TextStyle(height: 1.7),
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_remove_outlined),
                label: Text(
                  arabic ? 'حذف الحساب نهائيًا' : 'Permanently delete account',
                ),
                onPressed:
                    () => showDialog<void>(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            scrollable: true,
                            title: Text(
                              arabic
                                  ? 'حذف الحساب نهائيًا'
                                  : 'Permanently delete account',
                            ),
                            content: Text(
                              arabic
                                  ? 'لم يُرسل طلب ولم يُحذف الحساب. التنفيذ بانتظار اعتماد سياسة الالتزامات والاحتفاظ والتحقق من الهوية. راجع سياسة حذف الحساب والبيانات أعلاه. لا تُلغى حجوزات أو مستحقات تلقائيًا.'
                                  : 'No request has been submitted and no account has been deleted. Execution awaits approved obligations, retention and identity-verification rules. Review the deletion policy above. Bookings and liabilities are not automatically cancelled.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(arabic ? 'إغلاق' : 'Close'),
                              ),
                            ],
                          ),
                    ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
