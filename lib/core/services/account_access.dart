enum AccountDestination { phone, completeProfile, home }

AccountDestination accountDestination({
  required bool hasSession,
  required String? phone,
  required bool phoneConfirmed,
  required bool profileComplete,
}) {
  if (!hasSession ||
      !phoneConfirmed ||
      !RegExp(r'^\+?968\d{8}$').hasMatch(phone ?? '')) {
    return AccountDestination.phone;
  }
  return profileComplete
      ? AccountDestination.home
      : AccountDestination.completeProfile;
}

bool validUsername(String value) =>
    RegExp(r'^[a-z][a-z0-9_]{3,31}$').hasMatch(value);

bool validBirthDate(DateTime birth, DateTime today) {
  final date = DateTime.utc(birth.year, birth.month, birth.day);
  final current = DateTime.utc(today.year, today.month, today.day);
  return !date.isAfter(current) &&
      !date.isBefore(DateTime.utc(today.year - 120, today.month, today.day));
}
