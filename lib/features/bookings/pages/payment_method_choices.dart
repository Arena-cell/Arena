import 'package:flutter/material.dart';

/// Availability is explicit: a wallet is never presented as operational merely
/// because its brand is shown. The server independently rejects new Cash orders.
class PaymentMethodChoices extends StatelessWidget {
  const PaymentMethodChoices({
    super.key,
    this.busy = false,
    this.showCash = true,
  });
  final bool busy;
  final bool showCash;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    void unavailable(String text) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ar ? 'طريقة الدفع' : 'Payment method'),
        ListTile(
          leading: const Icon(Icons.credit_card),
          title: Text(ar ? 'بطاقة / فيزا' : 'Card / Visa'),
          trailing: const Icon(Icons.check_circle_outline),
        ),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Apple Pay'),
          subtitle: Text(
            ar
                ? 'بانتظار تفعيل بوابة الدفع'
                : 'Awaiting payment gateway activation',
          ),
          onTap:
              busy
                  ? null
                  : () => unavailable(
                    ar
                        ? 'Apple Pay غير مفعلة حاليًا. يلزم تفعيلها والتحقق منها لدى بوابة الدفع.'
                        : 'Apple Pay is not currently enabled. Gateway activation and verification are required.',
                  ),
        ),
        if (showCash)
          ListTile(
            leading: const Icon(Icons.money_off),
            title: Text(
              ar ? 'نقدًا — معطل حاليًا' : 'Cash — currently disabled',
            ),
            onTap:
                busy
                    ? null
                    : () => unavailable(
                      ar
                          ? 'الدفع النقدي معطل حاليًا.'
                          : 'Cash payment is currently disabled.',
                    ),
          ),
      ],
    );
  }
}
