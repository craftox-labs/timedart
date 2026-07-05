extension DurationFormat on Duration {
  String get hms {
    final h = inHours.toString().padLeft(2, '0');
    final m = (inMinutes % 60).toString().padLeft(2, '0');
    final s = (inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// Invoice number formatting, shared by the on-screen preview and the PDF so
// rounding can't drift between them.
String formatMoney(double amount) => '\$${amount.toStringAsFixed(2)}';
String formatHours(double hours) => hours.toStringAsFixed(2);

// Currency symbol for common codes; empty when unknown (the code is shown
// alongside the number instead). Pure — shared by the invoice preview and PDF.
String currencySymbol(String code) {
  switch (code.toUpperCase()) {
    case 'USD':
    case 'AUD':
    case 'CAD':
    case 'NZD':
    case 'SGD':
    case 'HKD':
      return '\$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'JPY':
    case 'CNY':
      return '¥';
    default:
      return '';
  }
}

/// "\$ 220.14" (symbol + space) for known currencies, else "220.14 AUD".
String formatCurrency(double amount, String code) {
  final sym = currencySymbol(code);
  final n = amount.toStringAsFixed(2);
  return sym.isEmpty ? '$n $code' : '$sym $n';
}
