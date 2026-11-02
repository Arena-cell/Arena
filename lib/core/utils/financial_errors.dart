String financialError(String code, {required bool arabic}) {
  const messages = <String, (String, String)>{
    'INDIVIDUAL_MATCH_REQUIRES_24_HOURS': (
      'Create a pay-per-seat match more than 24 hours before its start, or choose host pays all.',
      'أنشئ مباراة دفع المقاعد قبل البداية بأكثر من 24 ساعة، أو اختر دفع المنشئ للجميع.',
    ),
    'INDIVIDUAL_MATCH_CREATION_DEADLINE_PASSED': (
      'The match creation deadline passed. Any captured amount requires a verified refund.',
      'انتهت مهلة إنشاء المباراة. أي مبلغ محصل يحتاج استردادًا مؤكدًا من المزود.',
    ),
    'INVALID_SEAT_QUANTITY': (
      'Choose 1–3 available seats.',
      'اختر من مقعد إلى 3 مقاعد متاحة.',
    ),
    'SEAT_QUANTITY_ALREADY_RESERVED': (
      'A payment request already reserves a different quantity. Review it before retrying.',
      'يوجد طلب دفع بعدد مقاعد مختلف. راجعه قبل إعادة المحاولة.',
    ),
    'MATCH_FULL': (
      'The selected seats are no longer available. Refresh the match.',
      'لم تعد المقاعد المختارة متاحة. حدّث المباراة.',
    ),
    'CASH_TEMPORARILY_DISABLED': (
      'Cash payment is currently disabled.',
      'الدفع النقدي معطل حاليًا.',
    ),
    'PROMOTION_NOT_AVAILABLE': (
      'This discount code is unavailable or expired.',
      'كود الخصم غير متاح أو انتهت صلاحيته.',
    ),
    'PROMOTION_USAGE_LIMIT': (
      'This discount code has reached its usage limit.',
      'وصل كود الخصم إلى الحد المسموح للاستخدام.',
    ),
    'DISCOUNT_FUNDING_REQUIRED': (
      'This discount is awaiting funding approval.',
      'هذا الخصم بانتظار اعتماد جهة تمويله.',
    ),
    'DISCOUNT_EXCEEDS_ARENA_SHARE': (
      'This offer exceeds its approved Arena funding. Choose another offer.',
      'تجاوز العرض حصة تمويل Arena المعتمدة. اختر عرضًا آخر.',
    ),
    'DISCOUNT_EXCEEDS_OWNER_SHARE': (
      'This offer exceeds its approved venue funding. Choose another offer.',
      'تجاوز العرض حصة تمويل المالك المعتمدة. اختر عرضًا آخر.',
    ),
    'MULTIPLE_DISCOUNTS_NOT_ALLOWED': (
      'Use one discount at a time.',
      'استخدم خصمًا واحدًا فقط في الطلب.',
    ),
    'PRICE_CHANGED': (
      'The price changed. Refresh the summary before continuing.',
      'تغير السعر. حدّث ملخص الحجز قبل المتابعة.',
    ),
  };
  final message = messages[code];
  return message == null
      ? (arabic
          ? 'تعذر إكمال الطلب. تحقق من الاختيار وأعد المحاولة.'
          : 'Could not complete the request. Check your selection and retry.')
      : (arabic ? message.$2 : message.$1);
}
