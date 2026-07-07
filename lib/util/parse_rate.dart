/// Parse the optional rate field shared by the project and client forms.
///
/// Empty is valid — it means "no rate", returning `(value: null, error: null)`.
/// A non-empty value that isn't a number returns an error so "5o" can't be
/// silently dropped to null.
({double? value, String? error}) parseRate(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return (value: null, error: null);
  final n = double.tryParse(trimmed);
  if (n == null) return (value: null, error: 'Enter a number, or leave blank');
  return (value: n, error: null);
}
