/// The fonts an invoice template can be rendered in — one registry shared by
/// the on-screen preview and the PDF renderer so the two never disagree.
///
/// The `pdf` package can't shift a variable font's weight axis: it renders one
/// static instance per file. So every family ships three pre-instanced static
/// TTFs (Regular w400 / Medium w500 / SemiBold w600), and the PDF loads the
/// trio by asset path. The preview, by contrast, uses [flutterFamily] with a
/// `fontWeight` — Flutter resolves the matching declared weight — so preview
/// and PDF land on the same three weights of the same family.
///
/// Pure Dart (no Flutter imports) so it stays trivially unit-testable.
library;

/// One family's Flutter family name plus its three static PDF weight assets.
class InvoiceFont {
  const InvoiceFont({
    required this.flutterFamily,
    required this.pdfRegularAsset,
    required this.pdfMediumAsset,
    required this.pdfSemiBoldAsset,
  });

  /// The `pubspec.yaml` family name the preview binds to (weights resolve from
  /// the declared 400/500/600 faces).
  final String flutterFamily;

  /// Static TTF for value text (w400), loaded via `rootBundle` in the PDF.
  final String pdfRegularAsset;

  /// Static TTF for labels (w500).
  final String pdfMediumAsset;

  /// Static TTF for headings/bold (w600).
  final String pdfSemiBoldAsset;
}

/// The family used when a template's stored value is null or unrecognised —
/// e.g. a legacy row written before the picker existed.
const String defaultInvoiceFontFamily = 'Outfit';

const String _dir = 'assets/fonts';

/// Every selectable family, keyed by its display name (what the picker shows
/// and the template stores). Insertion order is the picker's order — Outfit
/// (the default) first.
const Map<String, InvoiceFont> invoiceFonts = {
  'Outfit': InvoiceFont(
    flutterFamily: 'Outfit',
    pdfRegularAsset: '$_dir/Outfit-Regular.ttf',
    pdfMediumAsset: '$_dir/Outfit-Medium.ttf',
    pdfSemiBoldAsset: '$_dir/Outfit-SemiBold.ttf',
  ),
  'IBM Plex Sans': InvoiceFont(
    flutterFamily: 'IBM Plex Sans',
    pdfRegularAsset: '$_dir/IBMPlexSans-Regular.ttf',
    pdfMediumAsset: '$_dir/IBMPlexSans-Medium.ttf',
    pdfSemiBoldAsset: '$_dir/IBMPlexSans-SemiBold.ttf',
  ),
  'Libre Franklin': InvoiceFont(
    flutterFamily: 'Libre Franklin',
    pdfRegularAsset: '$_dir/LibreFranklin-Regular.ttf',
    pdfMediumAsset: '$_dir/LibreFranklin-Medium.ttf',
    pdfSemiBoldAsset: '$_dir/LibreFranklin-SemiBold.ttf',
  ),
  'Source Serif 4': InvoiceFont(
    flutterFamily: 'Source Serif 4',
    pdfRegularAsset: '$_dir/SourceSerif4-Regular.ttf',
    pdfMediumAsset: '$_dir/SourceSerif4-Medium.ttf',
    pdfSemiBoldAsset: '$_dir/SourceSerif4-SemiBold.ttf',
  ),
  'Spectral': InvoiceFont(
    flutterFamily: 'Spectral',
    pdfRegularAsset: '$_dir/Spectral-Regular.ttf',
    pdfMediumAsset: '$_dir/Spectral-Medium.ttf',
    pdfSemiBoldAsset: '$_dir/Spectral-SemiBold.ttf',
  ),
  'Plus Jakarta Sans': InvoiceFont(
    flutterFamily: 'Plus Jakarta Sans',
    pdfRegularAsset: '$_dir/PlusJakartaSans-Regular.ttf',
    pdfMediumAsset: '$_dir/PlusJakartaSans-Medium.ttf',
    pdfSemiBoldAsset: '$_dir/PlusJakartaSans-SemiBold.ttf',
  ),
};

/// The display names in picker order.
List<String> get invoiceFontFamilies => invoiceFonts.keys.toList();

/// Resolves a stored family name to its [InvoiceFont], falling back to
/// [defaultInvoiceFontFamily] for null or unknown values so a legacy or
/// corrupt row still renders.
InvoiceFont resolveInvoiceFont(String? stored) =>
    invoiceFonts[stored] ?? invoiceFonts[defaultInvoiceFontFamily]!;
