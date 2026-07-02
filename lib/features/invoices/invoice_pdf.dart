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

/// Build an invoice PDF for a single job over [from]..[to] from [inv].
/// Pure: data in, bytes out — no DB or UI dependency.
Future<Uint8List> buildInvoicePdf({
  required JobInvoice inv,
  required DateTime from,
  required DateTime to,
}) async {
  final doc = pw.Document();
  final rate = inv.rate;

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
          pw.SizedBox(height: 8),
          pw.Text(
            '${inv.job.code} · ${inv.job.title}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Client: ${inv.client.name}'
            '${inv.client.email != null ? ' · ${inv.client.email}' : ''}',
          ),
          pw.Text('Period: ${_date(from)} – ${_date(to)}'),
          pw.Text(rate == null ? 'Rate: not set' : 'Rate: ${_money(rate)}/hr'),
          pw.SizedBox(height: 24),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            headers: ['Date', 'Task', 'Hours', 'Amount'],
            data: [
              for (final e in inv.entries)
                [
                  _date(e.startedAt),
                  e.task,
                  _hours(e.seconds),
                  rate == null ? '—' : _money((e.seconds / 3600) * rate),
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              inv.total == null
                  ? 'Total hours: ${_hours(inv.totalSeconds)} (no rate set)'
                  : 'Total: ${_money(inv.total!)}',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}
