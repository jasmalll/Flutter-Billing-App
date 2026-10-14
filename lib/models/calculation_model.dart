import 'dart:convert';

class StaffAllowance {
  final String id;
  final String staffName;
  final String role;
  final double basePay;
  final double amount;
  final String sourceCategory; // Other Expenses or Setting Bill
  final String auditTag;

  const StaffAllowance({
    required this.id,
    required this.staffName,
    required this.role,
    required this.basePay,
    required this.amount,
    required this.sourceCategory,
    required this.auditTag,
  });

  double get finalTotal => basePay + amount;

  Map<String, dynamic> toMap() => {
        'id': id,
        'staffName': staffName,
        'role': role,
        'basePay': basePay,
        'amount': amount,
        'sourceCategory': sourceCategory,
        'auditTag': auditTag,
      };

  factory StaffAllowance.fromMap(Map<String, dynamic> map) => StaffAllowance(
        id: map['id']?.toString() ?? '',
        staffName: map['staffName']?.toString() ?? '',
        role: map['role']?.toString() ?? 'sp',
        basePay: (map['basePay'] as num?)?.toDouble() ?? 0,
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        sourceCategory: map['sourceCategory']?.toString() ?? 'Other Expenses',
        auditTag: map['auditTag']?.toString() ?? '',
      );
}

class EventSettlement {
  final String eventDate; // YYYY-MM-DD
  String auditoriumName;
  String auditorIdentifier;
  double originalOtherExpenses;
  double originalSettingBill;
  List<StaffAllowance> allowances;
  DateTime updatedAt;

  EventSettlement({
    required this.eventDate,
    this.auditoriumName = '',
    this.auditorIdentifier = '',
    this.originalOtherExpenses = 0,
    this.originalSettingBill = 0,
    List<StaffAllowance>? allowances,
    DateTime? updatedAt,
  })  : allowances = allowances ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  double get otherDeductions => allowances
      .where((a) => a.sourceCategory == 'Other Expenses')
      .fold(0.0, (sum, a) => sum + a.amount);
  double get settingDeductions => allowances
      .where((a) => a.sourceCategory == 'Setting Bill')
      .fold(0.0, (sum, a) => sum + a.amount);
  double get remainingOther => originalOtherExpenses - otherDeductions;
  double get remainingSetting => originalSettingBill - settingDeductions;
  double get totalBasePay => allowances.fold(0.0, (sum, a) => sum + a.basePay);
  double get totalAllowances => allowances.fold(0.0, (sum, a) => sum + a.amount);
  double get totalDisbursed => totalBasePay + totalAllowances;

  Map<String, dynamic> toMap() => {
        'eventDate': eventDate,
        'auditoriumName': auditoriumName,
        'auditorIdentifier': auditorIdentifier,
        'originalOtherExpenses': originalOtherExpenses,
        'originalSettingBill': originalSettingBill,
        'allowances': allowances.map((e) => e.toMap()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  String toJson() => jsonEncode(toMap());

  factory EventSettlement.fromJson(String source) {
    final map = Map<String, dynamic>.from(jsonDecode(source) as Map);
    return EventSettlement(
      eventDate: map['eventDate']?.toString() ?? '',
      auditoriumName: map['auditoriumName']?.toString() ?? '',
      auditorIdentifier: map['auditorIdentifier']?.toString() ?? '',
      originalOtherExpenses: (map['originalOtherExpenses'] as num?)?.toDouble() ?? 0,
      originalSettingBill: (map['originalSettingBill'] as num?)?.toDouble() ?? 0,
      allowances: (map['allowances'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => StaffAllowance.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
