import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:time_tracker/data/database.dart';

String _money(double v) => '\$${v.toStringAsFixed(2)}';
String _hours(int seconds) => (seconds / 3600).toStringAsFixed(2);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Build an invoice PDF for [client] over [from]..[to] from aggregated [lines].
/// Pure: takes data in, returns bytes — no DB or UI dependency.
Future<Uint8List> buildInvoicePdf({
  required Client client,
  required List<InvoiceLine> lines,
  required DateTime from,
  required DateTime to,
}) async {
  final doc = pw.Document();
  final billable = lines.where((l) => l.amount != null);
  final total = billable.fold<double>(0, (sum, l) => sum + l.amount!);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'INVOICE',
            style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('${client.name}${client.email != null ? ' · ${client.email}' : ''}'),
          pw.Text('Period: ${_date(from)} – ${_date(to)}'),
          pw.SizedBox(height: 24),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            headers: ['Code', 'Job', 'Hours', 'Rate', 'Amount'],
            data: [
              for (final l in lines)
                [
                  l.jobCode,
                  l.jobTitle,
                  _hours(l.seconds),
                  l.rate == null ? '—' : _money(l.rate!),
                  l.amount == null ? 'no rate' : _money(l.amount!),
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total: ${_money(total)}',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if (lines.any((l) => l.amount == null)) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Lines marked "no rate" are excluded from the total.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          ],
        ],
      ),
    ),
  );

  return doc.save();
}
