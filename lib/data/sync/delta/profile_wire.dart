import 'package:drift/drift.dart';

import 'package:timedart/data/database.dart';

// Delta-sync (#320) — the Postgres wire shape for an invoice `profiles` row
// (business identity + payment + branding). Mirrors the other wire codecs. The
// logo BLOB itself is NOT a wire column: the bytes go to Supabase Storage and
// the row carries only `logo_path` (+ `logo_mime`). Bools encode as 0/1 bigints;
// colours aren't here (they live on the template).

Map<String, dynamic> profileToWire(InvoiceProfile p) => {
  'id': p.id,
  'org_id': p.orgId,
  'name': p.name,
  'business_name': p.businessName,
  // logo bytes are replicated via Storage, not as a column.
  'logo_path': p.logoPath,
  'logo_mime': p.logoMime,
  'email': p.email,
  'phone': p.phone,
  'website': p.website,
  'address': p.address,
  'abn': p.abn,
  'payee_name': p.payeeName,
  'bank_name': p.bankName,
  'bank_bsb': p.bankBsb,
  'bank_account': p.bankAccount,
  'swift': p.swift,
  'payment_link': p.paymentLink,
  'currency': p.currency,
  'tax_label': p.taxLabel,
  'tax_rate': p.taxRate,
  'is_default': p.isDefault ? 1 : 0,
  'template_id': p.templateId,
  'region': p.region,
  'iban': p.iban,
  'sort_code': p.sortCode,
  'routing_number': p.routingNumber,
  'payid': p.payid,
  'institution_number': p.institutionNumber,
  'transit_number': p.transitNumber,
  'show_bank': p.showBank ? 1 : 0,
  'show_payment_link': p.showPaymentLink ? 1 : 0,
  'show_tax': p.showTax ? 1 : 0,
  'show_rate_column': p.showRateColumn ? 1 : 0,
  'show_time_column': p.showTimeColumn ? 1 : 0,
  'reverse_charge': p.reverseCharge ? 1 : 0,
  'created_at': _toMs(p.createdAt),
  'updated_at': _toMs(p.updatedAt),
  'deleted_at': _toMs(p.deletedAt),
};

class RemoteProfile {
  final String id;
  final String? orgId;
  final String name;
  final String businessName;
  final String? logoPath;
  final String? logoMime;
  final String? email;
  final String? phone;
  final String? website;
  final String? address;
  final String? abn;
  final String? payeeName;
  final String? bankName;
  final String? bankBsb;
  final String? bankAccount;
  final String? swift;
  final String? paymentLink;
  final String currency;
  final String? taxLabel;
  final double? taxRate;
  final bool isDefault;
  final String? templateId;
  final String region;
  final String? iban;
  final String? sortCode;
  final String? routingNumber;
  final String? payid;
  final String? institutionNumber;
  final String? transitNumber;
  final bool showBank;
  final bool showPaymentLink;
  final bool showTax;
  final bool showRateColumn;
  final bool showTimeColumn;
  final bool reverseCharge;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int? serverSeq;

  const RemoteProfile({
    required this.id,
    required this.orgId,
    required this.name,
    required this.businessName,
    required this.logoPath,
    required this.logoMime,
    required this.email,
    required this.phone,
    required this.website,
    required this.address,
    required this.abn,
    required this.payeeName,
    required this.bankName,
    required this.bankBsb,
    required this.bankAccount,
    required this.swift,
    required this.paymentLink,
    required this.currency,
    required this.taxLabel,
    required this.taxRate,
    required this.isDefault,
    required this.templateId,
    required this.region,
    required this.iban,
    required this.sortCode,
    required this.routingNumber,
    required this.payid,
    required this.institutionNumber,
    required this.transitNumber,
    required this.showBank,
    required this.showPaymentLink,
    required this.showTax,
    required this.showRateColumn,
    required this.showTimeColumn,
    required this.reverseCharge,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.serverSeq,
  });

  factory RemoteProfile.fromWire(Map<String, dynamic> m) => RemoteProfile(
    id: m['id'] as String,
    orgId: m['org_id'] as String?,
    name: m['name'] as String,
    businessName: (m['business_name'] as String?) ?? '',
    logoPath: m['logo_path'] as String?,
    logoMime: m['logo_mime'] as String?,
    email: m['email'] as String?,
    phone: m['phone'] as String?,
    website: m['website'] as String?,
    address: m['address'] as String?,
    abn: m['abn'] as String?,
    payeeName: m['payee_name'] as String?,
    bankName: m['bank_name'] as String?,
    bankBsb: m['bank_bsb'] as String?,
    bankAccount: m['bank_account'] as String?,
    swift: m['swift'] as String?,
    paymentLink: m['payment_link'] as String?,
    currency: (m['currency'] as String?) ?? 'USD',
    taxLabel: m['tax_label'] as String?,
    taxRate: (m['tax_rate'] as num?)?.toDouble(),
    isDefault: _fromB(m['is_default']),
    templateId: m['template_id'] as String?,
    region: (m['region'] as String?) ?? 'au',
    iban: m['iban'] as String?,
    sortCode: m['sort_code'] as String?,
    routingNumber: m['routing_number'] as String?,
    payid: m['payid'] as String?,
    institutionNumber: m['institution_number'] as String?,
    transitNumber: m['transit_number'] as String?,
    showBank: _fromB(m['show_bank'], orElse: true),
    showPaymentLink: _fromB(m['show_payment_link'], orElse: true),
    showTax: _fromB(m['show_tax'], orElse: true),
    showRateColumn: _fromB(m['show_rate_column'], orElse: true),
    showTimeColumn: _fromB(m['show_time_column'], orElse: true),
    reverseCharge: _fromB(m['reverse_charge']),
    createdAt: _fromMs(m['created_at']),
    updatedAt: _fromMs(m['updated_at']),
    deletedAt: _fromMs(m['deleted_at']),
    serverSeq: (m['server_seq'] as num?)?.toInt(),
  );

  /// The drift companion for a local apply. **`logo` is deliberately omitted**
  /// (Value.absent) — the bytes are replicated via Storage and reconciled
  /// separately (fetch-on-miss), so applying a pulled row never clobbers a local
  /// logo BLOB nor writes null over it. `logoPath`/`logoMime` ARE applied so the
  /// reconcile step knows what to fetch.
  ProfilesCompanion toCompanion() => ProfilesCompanion(
    id: Value(id),
    orgId: Value(orgId),
    name: Value(name),
    businessName: Value(businessName),
    logoPath: Value(logoPath),
    logoMime: Value(logoMime),
    email: Value(email),
    phone: Value(phone),
    website: Value(website),
    address: Value(address),
    abn: Value(abn),
    payeeName: Value(payeeName),
    bankName: Value(bankName),
    bankBsb: Value(bankBsb),
    bankAccount: Value(bankAccount),
    swift: Value(swift),
    paymentLink: Value(paymentLink),
    currency: Value(currency),
    taxLabel: Value(taxLabel),
    taxRate: Value(taxRate),
    isDefault: Value(isDefault),
    templateId: Value(templateId),
    region: Value(region),
    iban: Value(iban),
    sortCode: Value(sortCode),
    routingNumber: Value(routingNumber),
    payid: Value(payid),
    institutionNumber: Value(institutionNumber),
    transitNumber: Value(transitNumber),
    showBank: Value(showBank),
    showPaymentLink: Value(showPaymentLink),
    showTax: Value(showTax),
    showRateColumn: Value(showRateColumn),
    showTimeColumn: Value(showTimeColumn),
    reverseCharge: Value(reverseCharge),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
    deletedAt: Value(deletedAt),
  );
}

int? _toMs(DateTime? d) => d?.millisecondsSinceEpoch;

DateTime? _fromMs(Object? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());

bool _fromB(Object? v, {bool orElse = false}) =>
    v == null ? orElse : (v as num).toInt() != 0;
