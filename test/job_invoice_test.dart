import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';

// Fixed timestamp — the arithmetic doesn't depend on it.
final _t = DateTime(2026, 1, 1);

Client _client({double? defaultRate}) => Client(
  id: 1,
  name: 'Acme',
  defaultRate: defaultRate,
);

Job _job({double? rate}) => Job(
  id: 1,
  clientId: 1,
  code: 'A-1',
  title: 'Work',
  rate: rate,
  status: 'active',
  createdAt: _t,
);

TimeEntry _entry(int seconds) => TimeEntry(
  id: 1,
  jobId: 1,
  task: 'task',
  startedAt: _t,
  endedAt: _t.add(Duration(seconds: seconds)),
  seconds: seconds,
);

JobInvoice _invoice({
  double? jobRate,
  double? clientRate,
  required List<int> secs,
}) => JobInvoice(
  job: _job(rate: jobRate),
  client: _client(defaultRate: clientRate),
  rate: jobRate ?? clientRate,
  entries: [for (final s in secs) _entry(s)],
);

void main() {
  group('JobInvoice arithmetic', () {
    test('sums hours across entries', () {
      final inv = _invoice(jobRate: 100, secs: [3600, 1800]); // 1h + 0.5h
      expect(inv.totalHours, closeTo(1.5, 1e-9));
    });

    test('per-line amount = hours * rate', () {
      final inv = _invoice(jobRate: 100, secs: [1800]); // 0.5h
      expect(inv.lines.single.hours, closeTo(0.5, 1e-9));
      expect(inv.lines.single.amount, closeTo(50, 1e-9));
    });

    test('total = sum of hours * rate', () {
      final inv = _invoice(jobRate: 100, secs: [3600, 1800]);
      expect(inv.total, closeTo(150, 1e-9));
    });

    test('no effective rate → amounts and total are null', () {
      final inv = _invoice(secs: [3600]); // neither job nor client rate
      expect(inv.rate, isNull);
      expect(inv.lines.single.amount, isNull);
      expect(inv.total, isNull);
      // hours are still known even when un-billable
      expect(inv.lines.single.hours, closeTo(1, 1e-9));
    });

    test('one line per entry', () {
      final inv = _invoice(jobRate: 50, secs: [60, 120, 180]);
      expect(inv.lines.length, 3);
    });
  });
}
