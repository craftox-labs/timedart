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
