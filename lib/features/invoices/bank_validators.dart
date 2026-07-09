// Pure, non-blocking format checks for the region-specific bank identifiers
// (PRD #117, slice #121). Each returns null when the value is acceptable (or
// empty — the fields are optional), else a short hint to show under the input.
// They never block saving; they only warn about an obviously malformed entry.
//
// No Flutter/drift imports, so the rules are unit-testable in isolation with
// real vectors as fixtures — the tests are the guard.

String _digitsOnly(String s) => s.replaceAll(RegExp(r'[\s-]'), '');

/// Australian BSB — 6 digits, conventionally written `XXY-ZZZ`.
String? bsbError(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  return RegExp(r'^\d{6}$').hasMatch(_digitsOnly(v))
      ? null
      : 'BSB should be 6 digits';
}

/// UK sort code — 6 digits, conventionally written `XX-XX-XX`.
String? sortCodeError(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  return RegExp(r'^\d{6}$').hasMatch(_digitsOnly(v))
      ? null
      : 'Sort code should be 6 digits';
}

/// US ABA routing number — 9 digits with a weighted (3-7-1) checksum ≡ 0 mod 10.
String? abaError(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  final digits = _digitsOnly(v);
  if (!RegExp(r'^\d{9}$').hasMatch(digits)) {
    return 'Routing number should be 9 digits';
  }
  const weights = [3, 7, 1, 3, 7, 1, 3, 7, 1];
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += (digits.codeUnitAt(i) - 0x30) * weights[i];
  }
  return sum % 10 == 0 ? null : 'Routing number checksum is invalid';
}

/// IBAN — ISO 13616. 15–34 chars, and the MOD-97-10 checksum must equal 1
/// (move the first four chars to the end, letters → digits A=10…Z=35, mod 97).
String? ibanError(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  final iban = v.replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$').hasMatch(iban)) {
    return 'Not a valid IBAN';
  }
  final rearranged = iban.substring(4) + iban.substring(0, 4);
  final buf = StringBuffer();
  for (final unit in rearranged.codeUnits) {
    if (unit >= 0x41 && unit <= 0x5A) {
      buf.write(unit - 0x41 + 10); // A–Z → 10–35
    } else {
      buf.writeCharCode(unit); // digit
    }
  }
  // Reduce mod 97 in chunks to avoid overflowing on long IBANs.
  final digits = buf.toString();
  var remainder = 0;
  for (var i = 0; i < digits.length; i += 7) {
    final chunk = '$remainder${digits.substring(i, (i + 7).clamp(0, digits.length))}';
    remainder = int.parse(chunk) % 97;
  }
  return remainder == 1 ? null : 'IBAN checksum is invalid';
}
