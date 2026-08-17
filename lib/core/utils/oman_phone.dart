String? normalizeOmanPhone(String input) {
  var value = input.replaceAll(RegExp(r'[\s\-()]'), '');
  if (value.startsWith('00')) value = '+${value.substring(2)}';
  if (value.startsWith('968') && !value.startsWith('+')) value = '+$value';
  if (RegExp(r'^\d{8}$').hasMatch(value)) value = '+968$value';
  return RegExp(r'^\+968\d{8}$').hasMatch(value) ? value : null;
}
